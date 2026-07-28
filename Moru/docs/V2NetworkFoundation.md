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

서버 AI 추천은 저장 전 편집 가능한 일시적 preview이므로 예외적으로 메모리 상태에
머물고, 사용자가 확정한 뒤에만 SwiftData에 저장한다.

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
   -> Domain Repository / Service Port
      -> Local Repository
      -> SwiftData
      -> Sync Coordinator
      -> Remote Service Adapter
         -> Remote Data Source
         -> APIClient
            -> MoyaProvider
```

각 계층의 책임은 다음과 같습니다.

| 계층 | 책임 |
| --- | --- |
| View / ViewModel | 화면 상태와 사용자 입력, UseCase 호출 |
| UseCase | 기능 단위 규칙과 로컬 저장 시점 결정 |
| Domain Port | UseCase가 저장·원격 구현의 구체 타입을 알지 않게 하는 경계 |
| Local Repository | SwiftData 읽기와 쓰기, 저장된 화면 상태의 Source of Truth |
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
authoritative 서버 목록 응답
-> DTO 검증
-> local ID / remote ID 매핑
-> 사용자 선택과 충돌 정책 적용
-> 계정별 SwiftData cache 원자적 교체
-> 화면이 SwiftData 변경을 관찰
```

현재 `MoruSchemaV4`는 서버 음성 선택에 필요한 아래 범위만 구현합니다.

- 계정별 영속 Outbox와 idempotency generation
- 계정별 음성 catalogue cache와 authoritative 선택 metadata
- retry 횟수, 다음 시도 시각, 마지막 오류
- 로그아웃·회원 탈퇴 시 account-scoped 정리

Routine/Run의 remote link, tombstone, revision 동기화는 아직 추가하지 않았습니다.
제품 버전과 SwiftData 스키마 타입 이름은 서로 다른 버전 축입니다.

서버가 client entity ID, idempotency, revision,
삭제 및 증분 조회 계약을 제공하기 전에는
자동 양방향 동기화를 구현하지 않습니다.
v2.0은 사용자 선택형 백업/가져오기를 우선합니다.

## 인증과 세션

`AccountSessionStore`는 device-only Keychain credential과
lock으로 보호된 `MemoryAccessTokenProvider` snapshot을 함께 관리합니다.

현재 인증 경로는 아래 계약을 구현합니다.

- Keychain Access/Refresh Token 저장
- `/auth/login/{provider}`
- `/auth/reissue`
- 동시 401 요청의 single-flight 재발급
- 재발급 후 원 요청 최대 1회 재시도
- 로그아웃·회원 탈퇴와 provider SDK session 정리
- 앱 재실행 뒤 유효 session 복원

APIClient actor는 요청마다 Access Token을 한 번 읽습니다.
그 값을 `MoyaTargetAdapter`에 snapshot으로 넣고,
Plugin은 같은 snapshot으로 Bearer 헤더를 만듭니다.

음성·AI처럼 계정에 귀속되는 요청은 token과 함께 `memberID` 및 account session
generation을 고정합니다. 요청 완료 또는 오류 시 같은 generation인지 다시 검증해
계정 전환 뒤 stale 결과를 사용하지 않습니다.

기존 `SessionStore`는 LocalProfile과 온보딩 상태를 계속 담당합니다.
로그인 상태는 별도 `AccountSessionStore`에서 관리합니다.
로그아웃은 토큰과 동기화만 중단하고
로컬 루틴과 기록을 유지합니다.

## 로컬 fallback 호환성

`DependencyContainer.local(modelContext:)`은 Local Repository와 local 추천을
항상 조립하고, Remote service와 account provider는 선택적으로 받습니다.
production bootstrap은 capability가 켜졌을 때만 인증된 Remote 구현을 연결합니다.
로그아웃, 서버 장애, 잘못된 응답에서도 기존 SwiftData와 번들 MP3 동작을 유지합니다.

서버 기능을 조립할 때도 Local Repository는 교체하지 않습니다. APIClient,
AccountSessionStore, Remote Data Source, Sync Coordinator를 선택 기능으로 추가합니다.

## TTS 경계

현재 Swagger의 TTS 관련 계약은 음성 목록 조회(`GET /tts`)와
내 음성 타입 변경(`PATCH /members/me/tts`)입니다.
이 API는 `Data/Remote/Voice`에 둡니다.

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
- 계정 귀속 요청이 member와 session generation 변경을 차단하는지
- 인증 헤더와 요청 본문이 로그 메시지에 남지 않는지
