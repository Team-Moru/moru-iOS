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

## 현재 연동 범위

2026-08-05 운영 Swagger는 29개 경로, 31개 HTTP operation입니다.
현재 제품 흐름에 연결된 operation은 17개입니다.

| 기능 | API | 앱 연결 상태 |
| --- | --- | --- |
| 소셜 로그인 | `POST /auth/login/{provider}` | 운영 경로 연결 |
| 토큰 재발급 | `POST /auth/reissue` | single-flight 재시도와 세션 갱신 연결 |
| 로그아웃 | `POST /auth/logout` | 운영 경로 연결 |
| 회원 탈퇴 | `DELETE /auth/withdrawal` | 운영 경로 연결 |
| AI 루틴 초안 | `POST /routine-groups/ai-generate` | 로그인 계정에 결합해 연결, 실패 시 로컬 추천 |
| 온보딩 목표 추천 | `GET /onboarding/recommendations` | 최초 목표 선택에 연결, 실패·잘못된 응답 시 로컬 추천 |
| History 주간·월간 | `GET /routine-executions/weekly`, `GET /routine-executions/monthly` | 로컬 History 요약을 서버 집계로 보강 |
| History 일별 | `GET /routine-executions/daily/{date}` | 서버 heatmap 날짜의 읽기 전용 상세 화면에 연결 |
| History 기상 패턴 | `GET /routine-executions/wake-pattern` | 로컬 계산값이 없을 때만 서버 값으로 보강 |
| 계정 프로필·스트릭 | `GET /members/me/profile`, `GET /members/me/streak` | Profile의 읽기 전용 계정 정보에 연결 |
| 계정 음성 | `GET /tts`, `PATCH /members/me/tts` | 서버 생성 음성 목록과 선택 변경에 연결 |
| 구독 조회 | `GET /subscriptions/me` | Profile의 읽기 전용 플랜 상태에 연결 |
| 계정 루틴 보관함 | `GET /routine-groups`, `GET /routine-groups/{routineGroupId}` | Profile에서 목록·상세를 읽기 전용으로 표시. 로컬 루틴과 병합·실행하지 않음 |
| 서버 상태 | `GET /health` | Target과 계약 테스트만 존재 |

전체 Swagger 기준 operation 커버리지는 `17/31`(`54.8%`)입니다.
제품 앱에서 연결하면 안 되는 개발 토큰과 화면 없는 health를 제외하면
`17/29`(`58.6%`)입니다. 이 수치는 계약 연결 수이며 실제 기기·QA 완료율은
아닙니다.

홈, 루틴 관리, 실행 저장, 편집 가능한 로컬 프로필의 기준 데이터는
계속 SwiftData입니다. History는 로컬 기록을 기준으로 서버 집계를 보강하고,
Profile의 서버 계정 정보는 로컬 설정과 섞지 않는 읽기 전용 snapshot입니다.
계정 루틴 보관함도 서버 응답을 메모리에만 보관하며, 같은 제목의 그룹을
합치거나 로컬 `RoutineRepository`에 쓰지 않습니다.
서버 API가 존재하더라도 로컬 ID와 서버 ID의 매핑, 충돌, 시간대,
멱등성 계약이 확정되지 않은 기능은 임의로 연결하지 않습니다.

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
- 서버 응답을 SwiftData에 반영하지 않고 편집 가능한 핵심 상태로 직접 사용
- 읽기 전용 서버 snapshot을 로컬 설정과 같은 값처럼 덮어쓰기
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

현재 인증 경로는 아래 항목을 구현합니다.

- Keychain Access/Refresh Token 저장
- `/auth/login/{provider}`
- `/auth/reissue`
- `/auth/logout`
- `/auth/withdrawal`
- 동시 401 요청의 single-flight 재발급
- 재발급 후 원 요청 최대 1회 재시도
- 로그인 계정과 요청 계정을 결합하는 `AccountBoundAPIClient`

APIClient actor는 요청마다 Access Token을 한 번 읽습니다.
그 값을 `MoyaTargetAdapter`에 snapshot으로 넣고,
Plugin은 같은 snapshot으로 Bearer 헤더를 만듭니다.

Token Provider는 Keychain을 매 요청마다 읽지 않습니다.
lock으로 보호된 메모리 snapshot을 제공하며,
로그인·재발급·로그아웃 시 Keychain과 함께 갱신합니다.

기존 `SessionStore`는 LocalProfile과 온보딩 상태를 계속 담당합니다.
로그인 상태는 별도 `AccountSessionStore`에서 관리합니다.
로그아웃은 토큰과 동기화만 중단하고
로컬 루틴과 기록을 유지합니다.

재발급의 `401`, 잘못된 성공 응답, 회전된 토큰 저장 실패처럼
기존 자격 증명을 더 사용할 수 없는 경우에만 계정 세션을 해제합니다.
timeout, 연결 끊김, `408`, `429`, `5xx` 같은 일시 장애에서는
자격 증명을 보존해 다음 요청에서 다시 시도할 수 있게 합니다.

## v1 호환성

앱 부트스트랩은 인증, 두 추천 경로, History 집계, 계정 조회와
서버 생성 음성 선택에 APIClient를 연결합니다.
AI 추천은 로그인한 계정에서만 서버를 우선 사용하고,
로그아웃 상태, 오프라인, timeout, 서버 오류, 잘못된 응답에서는
기존 로컬 템플릿으로 즉시 대체합니다.
추천 응답은 사용자가 확인하기 전 SwiftData에 저장하지 않습니다.

최초 온보딩 목표 추천은 단일 `goalType` 계약에 맞춰 첫 목표만 사용합니다.
응답 배열에서 첫 유효 그룹을 편집 가능한 `localOnly` 초안으로 바꾸며,
서버 ID·알람·날씨·중첩 step은 동기화 계약 전까지 저장하지 않습니다.
자유 입력과 추천 루틴 추가는 기존 AI 생성 API를 유지합니다.

History의 주간·월간·기상 요청은 서로 독립적으로 실패할 수 있습니다.
로컬 데이터는 항상 유지하며, 서버 일별 상세도 서버 heatmap에서 온
날짜에만 진입합니다. 계정 전환 뒤 도착한 응답은 화면에 게시하지 않습니다.

Profile은 로컬 닉네임·번들 안내 음성과 서버 닉네임·서버 생성 음성을
별도 상태로 표시합니다. 구독 조회 실패를 FREE로 간주하지 않으며,
PRO 음성은 활성 PRO 응답이 확인된 경우만 변경합니다.
계정 루틴 보관함은 로그인한 사용자가 직접 진입했을 때만 목록을 요청하고,
항목을 선택했을 때만 상세를 요청합니다. 응답은 읽기 전용이며 로컬 루틴의
추가·수정·실행 또는 알람 설정으로 이어지지 않습니다.

서버 기능을 조립할 때도 Local Repository는 교체하지 않습니다.
APIClient, AccountSessionStore, Remote Data Source, 조회 Service,
필요한 Coordinator를 선택 기능으로 추가합니다.

## 계약 확인 전 보류하는 연동

- 루틴 그룹 쓰기와 실행용 조회
  - `POST /routine-groups`, 루틴 추가, `PATCH`, `DELETE`는 연결하지 않습니다.
  - `GET /routine-groups/active`, `GET /routine-groups/today`도 로컬 루틴과
    실행 기준을 정하지 않아 연결하지 않습니다.
  - 로컬 UUID와 서버 `Int64` ID의 영속 매핑이 없습니다.
  - 수정·재정렬, client mutation ID, idempotency, revision,
    tombstone, 증분 동기화 계약이 없습니다.
- 실행 결과 저장과 AI 단계 판정
  - 서버 routine ID, 오프라인 outbox, 중복 전송 방지 키가 없습니다.
  - 실행 중 계정 전환·재시도·부분 완료 정책도 필요합니다.
- 온보딩 상태 조회
  - 현재 Swagger에는 완료 상태를 맞춰 쓰는 mutation이 없습니다.
  - 서버 상태와 로컬 온보딩·초기 루틴 생성 순서의 기준이 필요합니다.
- 루틴 TTS 조회
  - 로컬 routine UUID와 서버 routine ID의 연결이 없습니다.
  - `s3Url` 수명, 다운로드 인증, 캐시 만료·fallback 계약이 필요합니다.
- 구독 등록
  - StoreKit 거래 검증, 중복 transaction, 복원, sandbox 정책이 없습니다.
  - `POST /subscriptions`를 결제 UI 없이 단독 호출하지 않습니다.
- 프로필 이미지
  - 조회 응답은 key만 제공하며 URL 해석·수정 API가 없습니다.
- 서버 음성과 번들 안내 음성 통합
  - 서버 `voiceCode`와 번들 `VoiceProfile` 매핑 계약이 없습니다.
  - 현재 두 설정은 의도적으로 분리합니다.

## 쓰기 연동 전 서버 계약

현재 백엔드 동작을 직접 확인한 결과는 다음과 같습니다.

- 같은 루틴 그룹 생성 요청을 두 번 보내면 서로 다른 그룹 두 개가 생성됩니다.
- 같은 루틴 추가 요청을 두 번 보내면 루틴 두 개가 생성됩니다.
- 같은 실행 결과를 다시 보내면 실행 기록이 중복 저장됩니다.
- 요청 중복을 식별할 idempotency key 또는 correlation key가 없습니다.

따라서 네트워크 재시도만으로 중복 쓰기가 생길 수 있습니다. 아래 계약이
Swagger와 서버 구현에 포함되기 전에는 쓰기 API를 제품 흐름에 연결하지
않습니다.

- 생성·수정 요청에 `Idempotency-Key` 또는 `clientMutationId`를 받습니다.
- 같은 키와 같은 payload를 다시 보내면 새 데이터를 만들지 않고 최초 결과를
  재사용합니다.
- 같은 키에 다른 payload가 오면 `409 Conflict`로 거절합니다.
- 루틴 그룹·루틴·step에 앱이 재전송 후에도 사용할 안정적인 client ID를
  지원합니다.
- 실행 업로드는 batch ID와 `clientExecutionId`로 중복을 판별합니다.
- timeout 뒤 이전 요청의 성공 여부를 조회할 reconciliation API를 제공합니다.
- 수정 충돌을 감지할 revision 또는 ETag 계약을 제공합니다.
- 삭제와 증분 동기화를 위한 tombstone과 delta 조회 계약을 제공합니다.

## TTS 경계

현재 Swagger의 계정 음성 목록 조회(`GET /tts`)와
내 음성 타입 변경(`PATCH /members/me/tts`)은
`Data/Remote/AccountServer`에 연결되어 있습니다.
이 선택은 서버가 루틴 음성을 생성할 때 쓰며,
기존 번들 MP3 안내 음성과 미리듣기에 연결하지 않습니다.

루틴별 생성 결과 조회(`GET /routine-tts/{routineGroupId}/tts`)는
별도 계약입니다. 서버 routine ID와 안전한 캐시 정책이 없어 보류합니다.

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

### 계정 루틴 보관함 QA

- 서버 그룹이 0개, 1개, 여러 개인 계정에서 목록·빈 상태를 확인합니다.
- 선택 필드가 누락된 목록과 상세가 “확인 불가” 상태로 안전하게 표시되는지
  확인합니다.
- 제목이 같은 그룹이 여러 개여도 서버 ID별 행을 그대로 표시하는지 확인합니다.
- 오프라인, timeout, `401`에서 재시도와 기존 읽기 결과 보존을 확인합니다.
- 목록 또는 상세 요청 중 계정을 전환하면 이전 계정 데이터가 즉시 사라지고
  늦게 도착한 응답도 표시되지 않는지 확인합니다.
- 새로고침을 반복해도 로컬 루틴이 추가·수정되지 않고 서버 순서와 개수가
  그대로 유지되는지 확인합니다.
