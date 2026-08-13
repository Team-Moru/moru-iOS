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
| 온보딩 상태 | `GET /onboarding/status` | 로그인·저장 세션 복원 후 읽기 전용으로 조회, 로컬 라우팅은 유지 |
| History 주간·월간 | `GET /routine-executions/weekly`, `GET /routine-executions/monthly` | 로컬 History 요약을 서버 집계로 보강 |
| History 일별 | `GET /routine-executions/daily/{date}` | 서버 heatmap 날짜의 읽기 전용 상세 화면에 연결 |
| History 기상 패턴 | `GET /routine-executions/wake-pattern` | 로컬 계산값이 없을 때만 서버 값으로 보강 |
| 계정 프로필·스트릭 | `GET /members/me/profile`, `GET /members/me/streak` | Profile의 읽기 전용 계정 정보에 연결 |
| 계정 음성 | `GET /tts`, `PATCH /members/me/tts` | 서버 생성 음성 목록과 선택 변경에 연결 |
| 구독 조회 | `GET /subscriptions/me` | Profile의 읽기 전용 플랜 상태에 연결 |
| 계정 루틴 보관함 | `GET /routine-groups`, `GET /routine-groups/{routineGroupId}` | Profile에서 목록·상세를 읽기 전용으로 표시. 로컬 루틴과 병합·실행하지 않음 |
| 서버 상태 | `GET /health` | Target과 계약 테스트만 존재 |

전체 Swagger 기준 operation 커버리지는 `18/31`(`58.1%`)입니다.
제품 앱에서 연결하면 안 되는 개발 토큰과 화면 없는 health를 제외하면
`18/29`(`62.1%`)입니다. 이 수치는 계약 연결 수이며 실제 기기·QA 완료율은
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
-> 로그인 상태면 같은 transaction에 typed Outbox intent 저장
-> `waitingForServerContract`로 보관
-> contract-gated sender core만 있고 production transport/trigger는 없어 서버 write를 호출하지 않음
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

기존 Routine/Run Mapper는 계속 `localOnly`만 허용하고
remote metadata를 제거합니다. 서버 식별자를 기존 모델의 문자열 필드에
혼합하지 않습니다.

`MoruSchemaV4`는 다음 account-scoped 동기화 기반을 별도 모델로 추가합니다.

- `PersistedRoutineServerBinding`
  - server namespace, account, entity kind, local UUID별 remote Int64 ID
  - 기존 local UUID 자체를 stable client UUID로 사용
- `PersistedRoutineSyncMutation`
  - typed command별 영속 Outbox와 payload generation
  - 동일 payload는 같은 로컬 `generationID`를 유지
  - payload가 바뀌면 coalesce하고 새 generation과 ID를 발급

현재 최신 스키마 이름은 `MoruSchemaV4`입니다.
제품 버전과 SwiftData 스키마 타입 이름을 혼동하지 않습니다.

현재 CRUD는 로그인 중에만 Outbox intent까지 저장할 수 있습니다. 그러나
서버가 client entity ID, idempotency, reconciliation, 안전한 삭제와 단일 활성
계약을 제공하기 전에는 production transport나 자동 양방향 동기화를 켜지 않습니다.
현재 Outbox 항목은 `waitingForServerContract`로만 저장하며 자동 전송하지
않습니다. timeout처럼 서버 반영 여부를 알 수 없는 결과는
`needsReconciliation`로 전환하고 자동 재시도하지 않습니다.

데이터 원본은 SwiftData입니다. 서버는 계정 백업·공유·통계용 projection입니다.
현재 서버 요청이 로컬 필드 전부를 받지 않으므로 완전 백업으로 간주하지 않습니다.

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

`GET /onboarding/status`는 로그인 직후와 저장 세션 복원 직후에
`AccountSessionIdentity(memberID, sessionID)`로 결합해 조회합니다.
조회 성공값은 로그인 응답 또는 Keychain에 저장된 `onboardingCompleted`보다
최신 서버 snapshot으로 우선합니다. 그러나 이 우선순위는 읽기 전용 진단
snapshot에만 적용합니다. 앱 라우팅과 온보딩 완료 데이터의 기준은 계속
로컬 `LocalProfile`이며, 서버 상태로 `SessionStore`, SwiftData, 루틴을
덮어쓰거나 생성·삭제하지 않습니다.

로그인 응답과 status 조회가 다르거나 서버와 로컬 상태가 다르면 mismatch를
명시적으로 기록합니다. status 응답이 없거나 잘못됐고, offline, timeout,
취소 또는 서버 오류가 발생하면 로그인/Keychain 값을 fallback snapshot으로
사용하며 기존 로컬 앱 흐름을 그대로 유지합니다. fallback과 로컬의 차이는
서버 불일치가 아닌 로그인 힌트 불일치로 구분하고, 로컬 프로필 조회가
실패하거나 진행 중이면 로컬 비교를 생략합니다. 특히 서버 `false`는
로컬 온보딩 데이터나 루틴을 초기화하라는 신호가 아닙니다. 요청이 진행되는
동안 계정이나 같은 member의 `sessionID`가 바뀌면 이전 응답과 fallback을
모두 폐기합니다.

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
  - `POST /routine-groups`, `POST /routine-groups/{routineGroupId}/routines`,
    `PATCH /routine-groups/{routineGroupId}/active`,
    `DELETE /routine-groups/{routineGroupId}`, `DELETE /routines/{routineId}`,
    `POST /routine-executions`는 sender에 연결하지 않습니다.
  - `GET /routine-groups/active`, `GET /routine-groups/today`도 로컬 루틴과
    실행 기준을 정하지 않아 연결하지 않습니다.
  - 로컬 UUID와 서버 `Int64` ID의 account-scoped mapping/Outbox 기반은
    `MoruSchemaV4`에 있습니다. 다만 서버가 stable client ID를 돌려주지 않아
    새 그룹의 자식 ID를 제목·순서로 추측해 연결하지 않습니다.
  - 수정·재정렬, client mutation ID, idempotency, revision,
    tombstone, 증분 동기화 계약은 서버에 없습니다.
- 실행 결과 저장과 AI 단계 판정
  - 실행 결과용 Outbox 기반은 있지만, 서버 routine ID, 응답 client ID,
    중복 전송 방지 키가 없습니다.
  - 실행 중 계정 전환·재시도·부분 완료 정책도 필요합니다.
- 온보딩 상태 쓰기
  - 조회는 읽기 전용 snapshot으로 연결했습니다.
  - 현재 Swagger에는 완료 상태를 맞춰 쓰는 mutation이 없습니다.
  - 따라서 서버 조회값으로 로컬 온보딩·초기 루틴을 변경하지 않습니다.
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

2026-08-10 live Swagger에는 루틴 mutation용 `Idempotency-Key`, stable client
ID echo, reconciliation 조회, revision/ETag가 선언되어 있지 않습니다.
따라서 재시도만으로 중복 생성·실행 기록이 생길 수 있으며, sender는 의도적으로
차단합니다. 상세 P0/P1/P2 요청과 수용 기준은
[서버 루틴 동기화 계약 요청서](ServerRoutineSyncContractRequest.md)에 둡니다.
P0이 Swagger와 실서버에 배포되고 E2E로 검증되기 전에는 어떤 새 루틴 write도
제품 흐름에서 호출하지 않습니다.

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
