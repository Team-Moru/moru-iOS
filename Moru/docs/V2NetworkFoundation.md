# v2 공통 서버 통신 및 확장 구조

## 목적

v1 로컬 실행 경로를 유지합니다.
로그인, 루틴, 실행 기록, TTS가 함께 사용할 서버 통신 기반과
계층 경계를 정의합니다.

이 문서의 핵심 원칙은 다음과 같습니다.

```text
서버가 없어도 핵심 루틴은 동작한다.
화면의 기준 데이터는 SwiftData다.
APIClient는 Remote 구현 내부에서만 사용한다.
```

## 서버 계약

- Base URL: `https://moru-api.duckdns.org`
- Swagger: `https://moru-api.duckdns.org/swagger-ui/index.html`
- 인증 헤더: `Authorization: Bearer {accessToken}`
- 공통 응답: `isSuccess`, `code`, `message`, `result`

`HTTP 2xx`여도 `isSuccess`가 `false`이면 서버 오류로 처리합니다.
인증이 필요한 Target은 Access Token이 없을 때 요청을 보내지 않습니다.

## 계층과 의존성 방향

```text
View
-> ViewModel
-> UseCase
   -> Local Repository
      -> SwiftData
   -> Sync Coordinator
      -> Remote Data Source
         -> APIClient
            -> MoyaProvider
```

각 계층의 책임은 다음과 같습니다.

| 계층 | 책임 |
| --- | --- |
| View / ViewModel | 화면 상태와 사용자 입력, UseCase 호출 |
| UseCase | 기능 단위 규칙과 로컬 저장 시점 결정 |
| Local Repository | SwiftData 읽기와 쓰기, 화면의 Source of Truth |
| Sync Coordinator | Outbox 처리, 업로드, 가져오기, 충돌 정책 |
| Remote Data Source | Target 호출, DTO와 Domain 변환 |
| APIClient | HTTP 상태, 공통 응답, 오류, 인증 헤더, 취소 |
| MoyaProviderFactory | timeout, Session, 필수 Plugin 조립 |

금지하는 의존성은 다음과 같습니다.

- View 또는 ViewModel에서 Target/APIClient 직접 호출
- 서버 응답을 SwiftData에 반영하지 않고 핵심 화면 상태로 직접 사용
- Remote 구현으로 기존 Local Repository 교체
- 로그인 실패나 서버 장애를 앱 부팅 실패로 처리
- 루틴 실행 시점에만 필요한 음성을 네트워크에서 즉시 요청

## Network Core 책임

### NetworkConfiguration

Base URL과 timeout을 보유합니다.
Target은 운영 URL을 알지 못합니다.
APIClient가 요청 직전에 `MoyaTargetAdapter`로 환경을 적용합니다.

```swift
let configuration = NetworkConfiguration(
  baseURL: stagingURL,
  requestTimeout: 15,
  resourceTimeout: 30
)
let client = DefaultAPIClient(configuration: configuration)
```

일반 JSON API와 큰 파일 다운로드의 timeout 요구가 달라지면
별도 Configuration과 Client를 조립합니다.
하나의 전역 mutable 환경은 만들지 않습니다.

### DefaultAPIClient

전용 actor가 MoyaProvider와 JSONDecoder를 소유합니다.

- 네트워크 디코딩을 MainActor에서 분리합니다.
- 여러 요청은 네트워크 응답을 기다리는 동안 병행할 수 있습니다.
- DTO와 Target은 `Sendable` 값 타입을 사용합니다.
- Moya 응답은 `statusCode`와 `Data`만 Sendable snapshot으로 변환합니다.

### MoyaProviderFactory

MoyaProvider는 직접 주입하지 않고 Factory가 항상 조립합니다.

- `AccessTokenPlugin`
- 개인정보를 기록하지 않는 `NetworkLogPlugin`
- 요청 및 리소스 timeout
- 테스트/관찰용 추가 Plugin

이 규칙으로 테스트나 커스텀 환경에서도
인증 Plugin이 빠지는 일을 막습니다.

## 기능 API 추가 방법

1. Swagger 태그에 맞는 기능 폴더를 `Data/Remote/<Feature>` 아래에 만듭니다.
2. Target에 경로, HTTP 메서드, Task, 인증 여부를 선언합니다.
3. 요청/응답 DTO는 서버 형식으로 만들고 `Sendable`을 채택합니다.
4. DTO와 Domain 모델 변환은 Remote 계층에 둡니다.
5. 공통 응답은 `APIClient.request(_:as:)`로 `result`를 받습니다.
6. 결과가 없는 공통 응답과 204/205는 `requestVoid(_:)`를 사용합니다.
7. 공통 응답이 아닌 작은 데이터만 `requestData(_:)`를 사용합니다.
8. MP3는 계약 확정 후 다운로드·디스크 캐시 전용 경로를 만듭니다.

```text
Data/Remote
├─ Auth
│  ├─ AuthTarget.swift
│  ├─ AuthDTO.swift
│  └─ RemoteAuthDataSource.swift
├─ Routine
├─ RoutineExecution
└─ TTS
```

```swift
nonisolated enum ExampleTarget: MoruTargetType {
  case detail

  var path: String { "/example" }
  var method: Moya.Method { .get }
  var task: Task { .requestPlain }
  var authenticationRequirement: AuthenticationRequirement { .bearer }
}
```

날짜와 시간은 서버 형식과 timezone 합의 전까지
DTO에서 `String`으로 받은 뒤 Mapper에서 검증합니다.
형식이 합의되면 공통 JSONDecoder 전략과 계약 테스트를 추가합니다.

## Local-first 쓰기와 읽기

쓰기 흐름은 다음과 같습니다.

```text
사용자 변경
-> SwiftData에 먼저 저장
-> Outbox에 업로드 작업 저장
-> 로그인/네트워크 가능 시 서버 전송
-> 성공 시 remote link와 sync 상태 갱신
```

가져오기 흐름은 다음과 같습니다.

```text
서버 응답
-> DTO 검증
-> local ID / remote ID 매핑
-> 사용자 선택과 충돌 정책 적용
-> SwiftData upsert
-> 화면이 SwiftData 변경을 관찰
```

현재 v1 Mapper는 `localOnly`만 허용하고
remote metadata를 제거합니다.
실제 동기화 전에 다음 SwiftData 스키마에 아래 항목을 추가해야 합니다.

- 영속 Outbox
- account ID를 포함한 local/remote link
- pending upload/delete 상태 또는 tombstone
- retry 횟수와 마지막 오류

현재 최신 스키마 이름은 `MoruSchemaV3`입니다.
다음 스키마는 `MoruSchemaV4`를 사용합니다.
제품 버전과 SwiftData 스키마 타입 이름을 혼동하지 않습니다.

서버가 client entity ID, idempotency, revision,
삭제 및 증분 조회 계약을 제공하기 전에는
자동 양방향 동기화를 구현하지 않습니다.
v2.0은 사용자 선택형 백업/가져오기를 우선합니다.

## 인증과 세션

현재 기반은 `AccessTokenProviding`에서 Access Token을 읽고
Bearer 헤더를 붙이는 경계까지만 제공합니다.

다음 인증 작업에서 아래 항목을 구현합니다.

- Keychain Access/Refresh Token 저장
- `/auth/login/{provider}`
- `/auth/reissue`
- 동시 401 요청의 single-flight 재발급
- 재발급 후 원 요청 최대 1회 재시도
- 재발급 실패 시 계정 세션 해제

APIClient actor는 요청마다 Access Token을 한 번 읽습니다.
그 값을 `MoyaTargetAdapter`에 snapshot으로 넣고,
Plugin은 같은 snapshot으로 Bearer 헤더를 만듭니다.

향후 실제 Token Provider는 Keychain을 매 요청마다 읽지 않습니다.
lock으로 보호된 메모리 snapshot을 제공하고,
로그인·재발급·로그아웃 시 Keychain과 함께 갱신합니다.

기존 `SessionStore`는 LocalProfile과 온보딩 상태를 계속 담당합니다.
로그인 상태는 별도 `AccountSessionStore`에서 관리합니다.
로그아웃은 토큰과 동기화만 중단하고
로컬 루틴과 기록을 유지합니다.

## v1 호환성

현재 `DependencyContainer.local(modelContext:)`과
앱 부트스트랩에는 APIClient를 연결하지 않습니다.
따라서 앱 실행만으로 서버 요청이 발생하지 않습니다.
기존 SwiftData와 번들 MP3 동작을 유지합니다.

서버 기능을 조립할 때도 Local Repository는 교체하지 않습니다. APIClient,
AccountSessionStore, Remote Data Source, Sync Coordinator를 선택 기능으로 추가합니다.

## TTS 경계

현재 Swagger의 TTS 관련 계약은 음성 목록 조회(`GET /tts`)와
내 음성 타입 변경(`PATCH /members/me/tts`)입니다.
이 API는 `Data/Remote/TTS`에 둡니다.

MP3 또는 음성 URL 계약이 추가되면 아래 흐름으로 구현합니다.

```text
루틴 멘트 확정
-> 서버에서 Chirp 3 HD 생성
-> iOS가 파일 다운로드
-> 디스크 캐시 저장
-> 루틴 실행 시 캐시 재생
-> 캐시가 없거나 실패하면 기존 번들 MP3 fallback
```

실제 재생 시점의 네트워크 성공 여부에
핵심 루틴을 의존시키지 않습니다.

## 테스트 기준

Network Foundation 테스트는 다음 계약을 유지합니다.

- 운영/커스텀 Base URL 적용
- public/bearer 인증 헤더 분리
- 필수 Plugin 조립 경로
- request/resource timeout
- HTTP 오류와 2xx 논리 오류
- result 필수/void/raw 응답
- 204/205 빈 응답
- 전송 오류와 retry 가능 여부
- Swift Task 취소와 실제 Alamofire 취소 오류 매핑
- 인증 토큰을 요청마다 한 번만 snapshot하는지
- 인증 헤더와 요청 본문이 로그 메시지에 남지 않는지
