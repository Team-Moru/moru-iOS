# 서버 공통 TTS 및 온보딩 완료 동기화 구현 계획

## 문서 목적

이 문서는 다음 두 서버 기능을 현재 iOS 구조에 안전하게 연결하기 위한 실행 계획이다.

1. 선택 음성별 공통 `DONE` / `REMIND` 음원을 내려주는 `GET /tts`
2. 서버 루틴 그룹 생성 이후 회원 온보딩을 완료하는 `POST /onboarding/complete`

새 작업 세션에서는 이 문서를 기준으로 범위를 복원하고, 각 단계의 완료 조건을
검증하면서 구현한다. 서버 변경은 범위에 포함하지 않는다.

## 근거가 되는 병합 PR

- 서버 PR #125: 목소리 변경 시 루틴 INTRO 재합성 및 회원 음성 선택 버전
- 서버 PR #129: 온보딩 완료 API
- 서버 PR #131: 선택 음성별 공통 DONE / REMIND 음원
- 서버 PR #132: 위 서버 변경의 `main` 반영
- iOS PR #135: 영속 Outbox, exact replay, account-session generation 보호

## 확정된 서버 계약

### 공통 음원 목록

`GET /tts`의 각 `voices` 원소에는 기존 필드와 함께 다음 값이 내려온다.

```json
{
  "ttsId": 1,
  "voiceCode": "Leda",
  "previewAudioUrl": "https://.../leda.mp3",
  "previewAudioStatus": "READY",
  "doneAudioUrl": "https://.../leda-done.mp3",
  "doneAudioStatus": "READY",
  "remindAudioUrl": "https://.../leda-remind.mp3",
  "remindAudioStatus": "READY",
  "selectionVersion": 1,
  "proOnly": false
}
```

- 음원 상태는 `READY` 또는 `PENDING`이다.
- URL은 준비되지 않았거나 서버 asset base URL이 없으면 `null`일 수 있다.
- `READY`와 유효한 HTTPS URL을 모두 만족해야 재생 가능한 것으로 본다.
- `timerRemindAudioUrl`은 없으며 추가하지 않는다.

### 온보딩 완료

```http
POST /onboarding/complete
Authorization: Bearer ...
Content-Type: application/json

{
  "routineGroupId": 15
}
```

성공 응답의 핵심 결과는 다음과 같다.

```json
{
  "onboardingCompleted": true
}
```

- 요청에 `true`를 보내는 API가 아니다.
- `routineGroupId`는 현재 회원이 소유하고 서버에 생성된 그룹 ID여야 한다.
- 이미 완료된 회원이 같은 요청을 다시 보내도 성공하는 replay-safe set-to-true 동작이다.
- 그룹이 아직 없거나 다른 회원 소유이면 서버가 거절한다.

## 반드시 분리할 두 버전

서버는 의미가 다른 값을 모두 `selectionVersion`이라는 JSON 필드명으로 사용한다.
앱 내부 이름과 모델은 반드시 분리한다.

| 출처 | 앱 내부 의미 | 권장 이름 |
| --- | --- | --- |
| `GET /tts`의 voice 항목 | 공통 DONE / REMIND 파일 버전 | `commonAudioVersion` |
| `PATCH /members/me/tts` 응답 | 회원 목소리 선택 및 루틴 INTRO 재합성 버전 | `routineVoiceSelectionVersion` |
| 루틴 TTS step 응답 | 해당 INTRO가 합성된 회원 음성 버전 | `generatedVoiceSelectionVersion` |

공통 음원 버전을 루틴 INTRO readiness gate에 사용하거나, 회원 음성 선택 버전을
공통 음원 캐시 버전으로 사용하면 안 된다.

## 제품 동작 결정

### 로그인 계정

- INTRO는 기존처럼 루틴별 서버 TTS와 버전 gate를 사용한다.
- DONE은 선택 음성의 공통 서버 음원을 모든 프리셋·커스텀 단계에서 사용한다.
- REMIND는 입력 단계에서 음성이 감지되지 않았을 때만 공통 서버 음원을 사용한다.
- 공통 음원이 준비되지 않았거나 캐시에 없으면 다른 목소리의 번들 음원을 재생하지
  않고 무음으로 정상 진행한다.
- 공통 cue 실패는 INTRO처럼 재시도 화면을 띄우지 않는다. 재생 결과를 정상 완료로
  처리해 완료 화면 전환이나 STT 재개가 멈추지 않게 한다.

### 로그아웃·로컬 전용 상태

- 기존 번들 음원 동작을 유지한다.
- 서버 계정 음성이 없는데 임의의 서버 voice를 추측하지 않는다.

### 타이머

- 현재 타이머 절반 시점의 `.remind` 재생을 제거한다.
- 마지막 5초 카운트다운은 유지한다.
- 타이머 종료 후 다음 항목 자동 전환은 유지한다.
- 타이머 전용 공통 음원은 구현하지 않는다.

## 현재 코드와의 차이

1. `TTSVoiceResponseDTO`와 `ServerTTSVoice`는 미리듣기 URL만 표현한다.
2. `GET /tts`는 프로필 화면이 열릴 때 주로 조회되어 루틴 재생 전 공통 음원 준비를
   보장하지 않는다.
3. `RoutineTTSAudioCacheKey`는 루틴 그룹/루틴/step ID 전용이라 음성별 공통 asset을
   가짜 루틴 ID 없이 표현할 수 없다.
4. `RemoteFirstRoutineGuidancePlayer`는 `.intro`만 원격 캐시를 사용한다.
5. `RoutineGuidanceCoordinator.stepDidComplete`는 `presetItemID`가 없는 커스텀 단계의
   DONE을 생략한다.
6. 타이머 단계 시작 시 절반 시점에 번들 `.remind`를 예약한다.
7. 온보딩 완료는 로컬 저장까지만 수행하고 `/onboarding/complete`를 호출하지 않는다.
8. 로그인 backfill은 루틴 그룹 생성 intent를 등록하지만 서버 온보딩 완료 intent는
   등록하지 않는다.
9. README와 iPhone 기능 게이트는 DONE/REMIND가 번들 음원이라는 이전 계약을 담고 있다.

## 목표 구조

```text
계정 세션 활성화 / 앱 활성화 / 음성 변경
  -> GET /members/me/profile + GET /tts
  -> profile.ttsId와 voices[].ttsId 매칭
  -> READY인 DONE/REMIND 다운로드
  -> version 기반 공통 asset 캐시
  -> RoutineGuidancePlayer가 로컬 파일만 재생
```

```text
로컬 온보딩 저장
  -> createRoutineGroup(localGroupID) Outbox
  -> 서버 성공 + group binding 저장
  -> completeOnboarding(localGroupID) dependency 해제
  -> POST /onboarding/complete(remoteGroupID)
  -> 성공 settlement
  -> Keychain/session/status hint를 true로 갱신
```

## 구현 단계

### 1. `GET /tts` 계약과 도메인 모델 확장

대상 경계:

- `Data/Remote/AccountServer/AccountServerDTO.swift`
- `Data/Remote/AccountServer/RemoteAccountServerService.swift`
- `Domain/Models/AccountServerModels.swift`
- `MoruTests/AccountServerRemoteContractTests.swift`

작업:

- preview/done/remind 상태, URL, 공통 asset 버전을 DTO에 추가한다.
- 상태는 forward compatibility를 위해 `ready`, `pending`, `unknown(rawValue)`처럼
  도메인에서 표현하고 unknown은 재생 불가로 취급한다.
- URL은 기존 preview와 같은 HTTPS/host/credential/fragment 검증을 재사용한다.
- 새 필드가 누락된 이전 응답은 voice 목록 전체를 실패시키지 않고 해당 공통 cue만
  unavailable로 처리한다.
- 서버 JSON의 `selectionVersion`을 도메인 `commonAudioVersion`으로 매핑한다.
- `/members/me/tts` 응답 모델의 기존 버전은 `routineVoiceSelectionVersion` 의미가
  드러나도록 이름을 정리한다. JSON key는 CodingKeys로 유지한다.

완료 조건:

- READY + HTTPS URL만 playable이다.
- PENDING, null URL, malformed URL, unknown status는 playable이 아니다.
- 두 종류의 selectionVersion을 혼용하지 않는 계약 테스트가 있다.

### 2. 공통 음원 캐시 identity와 수명주기 추가

대상 경계:

- `Platform/TTS/RoutineTTSAudioCache.swift`
- `Platform/TTS/RoutineTTSAudioDownloader.swift`
- `Domain/Services/RoutineTTSWarmupCoordinator.swift`
- 필요 시 작은 공통 asset helper 파일
- `MoruTests/RoutineTTSAudioStorageTests.swift`

작업:

- cache key가 명시적인 asset 종류를 표현하도록 확장한다.
  - routine intro: group/routine/step/URL
  - common voice cue: ttsID/voiceCode/commonAudioVersion/cue kind/URL
- 공통 cue에 가짜 routine/step ID를 사용하지 않는다.
- cache digest에는 query를 제외한 검증된 URL identity와 위 논리 identity를 포함한다.
- 공통 파일은 만료 없는 고정 URL이고 버전으로 교체되므로 routine INTRO의 24시간/7일
  TTL을 그대로 적용하지 않는다. 다음 조건에서만 제거되도록 별도 freshness 정책을 둔다.
  - voice 또는 commonAudioVersion 변경
  - 계정 정리/로그아웃 정책상 purge
  - 전체 데이터 초기화/회원 탈퇴
  - quota eviction 또는 파일 무결성 실패
- 기존 account/namespace purge와 in-flight cancellation을 공통 asset에도 적용한다.
- 같은 cache를 여러 coordinator가 독립적으로 purge하지 않게 한다. 현재
  `RoutineTTSWarmupCoordinator`가 account/session/cache invalidation의 단일 owner로
  남고, 공통 asset helper가 필요하면 이 coordinator가 소유한다.
- 캐시 포맷 변경으로 기존 recoverable 파일이 orphan될 수 있으면 format version 또는
  시작 cleanup 정책을 명시한다.

완료 조건:

- 동일 voice/version/cue는 한 번만 다운로드된다.
- voice 또는 version이 달라지면 이전 bytes가 재사용되지 않는다.
- 계정 전환 중인 다운로드 결과가 새 계정 캐시에 commit되지 않는다.
- 앱 재실행 뒤 무결성이 확인된 공통 파일을 재사용한다.

### 3. 공통 음원 catalogue 조회와 선다운로드

대상 경계:

- `Domain/Services/RoutineTTSWarmupCoordinator.swift`
- `App/DependencyContainer.swift`
- `App/AppBootstrapper.swift`
- `App/AppRouter.swift`
- 프로필의 서버 음성 선택 성공 callback

작업:

- 현재 계정의 profile과 voices를 조회해 `profile.ttsId == voice.ttsId`로 선택 voice를
  결정한다. 로컬 `VoiceProfile` 문자열로 서버 voice를 추측하지 않는다.
- 다음 trigger에서 선택 voice의 READY DONE/REMIND를 비동기 선다운로드한다.
  - account session 활성화/변경
  - scene active
  - 루틴 TTS warmup
  - `PATCH /members/me/tts` 성공
- 계정/session generation을 요청 전후에 검증한다.
- 음성 변경 callback에서는 기존 INTRO cache purge barrier를 먼저 완료하고, 그 다음
  새 `ttsId`의 voice catalogue를 다시 조회하여 공통 asset을 준비한다.
- 공통 cache 준비 실패는 루틴 시작을 차단하지 않으며 진단 event만 남긴다.
- 재생 경로는 원격 URL을 스트리밍하거나 cue 시점에 다운로드 완료를 기다리지 않는다.

완료 조건:

- 프로필 화면을 열지 않아도 루틴 실행 전에 공통 asset warmup이 시작된다.
- 음성 변경 직후 이전 voice의 DONE/REMIND가 재생될 수 없다.
- 같은 회원 재로그인과 다른 회원 전환에서 stale 응답이 publish되지 않는다.

### 4. DONE/REMIND 재생 경로 전환과 타이머 정리

대상 경계:

- `Platform/TTS/RemoteFirstRoutineGuidancePlayer.swift`
- `RoutineFlow/RoutinePlayer/RoutineGuidanceCoordinator.swift`
- `RoutineFlow/RoutinePlayer/RoutinePlayerViewModel.swift`는 동작 검증 위주
- `MoruTests/RemoteFirstRoutineGuidancePlayerTests.swift`
- 필요 시 guidance coordinator 전용 테스트 추가

작업:

- remote-first player에 공통 cue local URL provider를 연결한다.
- `.intro`는 기존 routine-specific provider를 유지한다.
- `.done`과 입력 `.remind`는 선택 voice의 공통 local file을 사용한다.
- remote playback이 시작된 뒤 cancel/interruption이 발생하면 번들로 이어 재생하지 않는다.
- 로그인 서버 voice가 예상되지만 공통 cache가 없으면 silent `.completed`로 fail-open한다.
  `.unavailable`은 기존 server-required INTRO retry UI에만 사용한다.
- `stepDidComplete`의 `presetItemID` guard를 제거해 custom 단계도 공통 DONE을 요청한다.
  로그아웃 로컬 cue에는 기존 fallback item이 있을 때 번들을 유지한다.
- 타이머 절반 reminder task와 관련 delay scheduling을 제거한다. 다른 용도가 없어지면
  `RoutineGuidanceDelaying` seam도 함께 정리하되 테스트에서 사용 중이면 범위를 확인한다.
- `timerCountdownDidReach(1...5)`의 system countdown은 유지한다.
- 입력 단계 no-speech reminder 실패 후 listener가 멈추지 않도록 silent completion을
  정상 완료로 반환한다.

완료 조건:

- preset/custom 단계 DONE이 동일한 선택 서버 voice로 재생된다.
- 입력 no-speech REMIND가 선택 서버 voice로 재생되고 이후 입력이 재개된다.
- timer 중간 REMIND 호출이 0회다.
- common cache miss가 화면 전환이나 입력 재개를 막지 않는다.
- signed-out local flow의 기존 bundle 동작은 회귀하지 않는다.

### 5. 온보딩 완료 원격 계약 추가

대상 경계:

- `Data/Remote/OnboardingStatus` 또는 목적에 맞춘 `OnboardingCompletion` remote 폴더
- `Domain/Repositories/OnboardingStatusRemoteServing.swift` 분리 여부 검토
- `MoruTests/OnboardingStatusRemoteContractTests.swift` 또는 completion 전용 테스트

작업:

- request DTO `routineGroupId: Int64`와 response `onboardingCompleted: Bool`을 추가한다.
- endpoint는 `POST /onboarding/complete`, bearer 인증, JSON body로 고정한다.
- positive remote group ID와 `onboardingCompleted == true`만 성공으로 인정한다.
- read-only status service와 write service의 책임이 섞이지 않도록 completion remote
  protocol을 분리하는 편을 우선한다.
- exact `AccountSessionIdentity`로 요청하고 stale session을 fail-closed한다.

완료 조건:

- method/path/body/auth/COMMON200/result 계약 테스트가 통과한다.
- 요청 body에 `true`가 들어가지 않는 테스트가 있다.

### 6. 온보딩 완료를 영속 Outbox operation으로 추가

단발 coordinator나 fire-and-forget Task 대신 PR #135의 영속 wire artifact/replay 구조를
확장한다.

대상 경계:

- `Domain/Models/RoutineSyncModels.swift`
- `Domain/Repositories/RoutineSyncRepositories.swift`
- `Data/Local/SwiftDataRoutineSyncRepository.swift`
- `Data/Remote/RoutineSync/ProductionRoutineSyncRequestPreparer.swift`
- `Data/Remote/RoutineSync/ProductionRoutineSyncResponseDecoder.swift`
- `Domain/Services/RoutineSyncSender.swift`
- Routine sync 관련 테스트 묶음

권장 command 모델:

```swift
case completeOnboarding(groupLocalID: UUID)
```

- operation은 account-level `completeOnboarding`이다.
- entity kind는 `.account`를 사용한다.
- local entity ID는 계정별 한 행으로 coalesce되는 고정
  `accountOnboardingCompletionID`를 사용한다.
- payload에는 remote ID가 아니라 local group UUID를 저장한다.
- 첫 전송 artifact를 만들 때 검증된 routineGroup binding의 remote ID를 body로 변환한다.

Outbox 규칙:

- 같은 계정에는 완료 intent가 최대 한 개다.
- group create mutation이 남아 있거나 binding이 없으면 admission하지 않는다.
- binding이 생긴 뒤에만 `POST /onboarding/complete` wire artifact를 만든다.
- 참조 그룹 delete는 onboarding completion보다 먼저 전송되지 않게 dependency를 둔다.
- endpoint의 set-to-true 멱등성을 명시하는 delivery policy/capability를 추가한다.
- 최초 method/path/body/idempotency key는 전송 전에 영속화하고 재시도 시 exact replay한다.
- 성공 응답은 `onboardingCompleted == true`를 검증한 뒤 Outbox 행만 원자적으로 제거한다.
  새 server binding은 만들지 않는다.
- ambiguous response는 같은 body를 replay한다. definitive 4xx는 blocked하고 새 key로
  자동 재시도하지 않는다.
- Gemini consent gate 대상에 포함하지 않는다.
- 기존 SwiftData 모델 필드를 추가할 필요는 없다. operation raw value와 Codable payload를
  기존 row에 저장하므로 schema 변경 없이 가능한지 테스트로 확인한다.

완료 조건:

- create group이 settle되기 전에 completion request가 나가지 않는다.
- binding 저장 직후 같은 drain에서 completion이 후속 전송될 수 있다.
- timeout/앱 종료 뒤 같은 bytes로 replay된다.
- session generation 변경 뒤 온 응답이 Outbox나 session state를 변경하지 않는다.
- 성공 후 재로그인해도 불필요한 completion intent가 반복 생성되지 않는다.

### 7. 온보딩 intent 등록 지점 연결

대상 경계:

- `Data/Local/SwiftDataOnboardingRepository.swift`
- `Domain/Services/RoutineSyncLoginBackfiller.swift`
- `Domain/Services/RoutineSyncRuntimeCoordinator.swift`
- `App/AppBootstrapper.swift`

로그인 상태에서 온보딩을 완료하는 경우:

- 로컬 profile/routine 저장과 `createRoutineGroup`, `completeOnboarding` stage enqueue를
  같은 ModelContext transaction에서 수행한다.
- 저장이 성공한 뒤 기존 wakeup relay를 한 번 호출한다.
- 로컬 온보딩 화면은 서버 응답을 기다리지 않고 기존처럼 완료할 수 있다.

로그인 전에 로컬 온보딩을 완료한 경우:

- 로그인 backfill이 local-only 그룹 create를 등록한다.
- 로컬 profile이 존재하고 계정의 완료 hint가 false라면 선택한 projectable group을
  참조하는 completion intent도 등록한다.
- active group을 우선 사용하되 없으면 결정적인 우선순위로 유효한 local group 하나를
  선택한다.
- 같은 snapshot/intent 재등록은 기존 generation을 재사용한다.

예외:

- 이미 로그인/status hint가 true이면 새 completion intent를 만들지 않는다.
- 참조 group create가 definitively 취소되고 다른 그룹도 없다면 잘못된 remote ID를
  보내지 않고 waiting/diagnostic 상태로 남긴다.
- account restoration barrier가 해제되기 전에 local data를 backfill하지 않는다.

완료 조건:

- signed-in onboarding과 local-first 후 로그인 두 경로 모두 서버 true로 수렴한다.
- 로컬 저장 실패 시 group/completion Outbox도 함께 rollback된다.
- 서버/네트워크 실패가 로컬 온보딩 완료와 루틴 실행을 막지 않는다.

### 8. 성공 후 account/session/status 상태 갱신

대상 경계:

- `App/AccountSessionStore.swift`
- `Data/Secure/CredentialStore.swift`는 모델 재사용
- `Domain/Services/OnboardingStatusRuntimeCoordinator.swift`
- `Domain/Services/RoutineSyncRuntimeCoordinator.swift`
- 관련 session/status/runtime 테스트

작업:

- exact current `AccountSessionIdentity`에 대해서만 onboarding completion을 적용하는
  `AccountSessionStore` API를 추가한다.
- Keychain의 기존 token/provider/user identifier를 보존하고
  `onboardingCompleted`만 true로 저장한다.
- 저장 성공 후 `SignedInAccount`도 true로 publish하되 access-token session generation은
  교체하지 않는다.
- remote settlement의 operation 정보를 runtime callback으로 전달한다. 기존 무인자
  `onMutationCompleted`를 typed completion event로 확장하거나 동등하게 검증 가능한
  구조를 사용한다.
- 기존 routine TTS warmup wake와 onboarding account update를 각각 올바른 operation에
  연결한다.
- 같은 sessionID라 status coordinator가 account state 변화를 무시할 수 있으므로,
  completion 성공을 명시적으로 반영하거나 강제 status refresh하는 seam을 추가한다.
- Keychain 갱신 실패는 서버 성공을 되돌릴 수 없으므로 진단하고 다음 status 조회에서
  복구한다. 다른 계정 credentials를 절대 덮어쓰지 않는다.

완료 조건:

- 성공 후 재실행해도 로컬 credential hint가 true다.
- 다른 계정 또는 같은 회원의 새 session 응답은 현재 credentials를 변경하지 않는다.
- `/onboarding/status` 최신 결과와 in-memory resolution이 false로 남지 않는다.

### 9. 문서와 기능 게이트 갱신

대상:

- `README.md`
- `Moru/docs/iPhoneFunctionalGate.md`
- `Moru/docs/RoutineSyncFoundation.md`
- `Scripts/check-iphone-functional-gate.sh`

작업:

- “DONE/REMIND는 번들 MP3” 계약을 로그인 계정의 공통 서버 음원 계약으로 교체한다.
- signed-out bundle fallback과 server common cache miss silent progression을 구분한다.
- 실제 iPhone E2E 문구를 server INTRO + common DONE/REMIND 흐름으로 갱신한다.
- 기능 게이트 스크립트의 이전 고정 문자열을 새 계약 문자열로 교체한다.
- RoutineSyncFoundation에 account-level onboarding completion command, dependency,
  replay/settlement 규칙을 추가한다.

완료 조건:

- 문서와 코드의 fallback 정책이 서로 모순되지 않는다.
- `check-iphone-functional-gate.sh`가 새 계약을 검증한다.

## 테스트 매트릭스

### TTS 계약/캐시

- 새 `GET /tts` 전체 응답 decode
- missing optional common fields
- READY + null URL
- PENDING + URL
- unknown status
- malformed/non-HTTPS URL
- 같은 voice/version single-flight
- commonAudioVersion 증가 후 cache miss/re-download
- ttsId 변경 후 이전 voice 미사용
- 계정 전환 중 download cancellation
- 파일 tamper 및 quota cleanup

### 재생

- preset/custom DONE 원격 local file 재생
- input REMIND 원격 local file 재생
- common cache miss silent completion
- remote playback cancel 후 bundle 미재생
- signed-out bundle 회귀
- timer 절반 reminder 미예약
- 5초 countdown 유지
- DONE 완료 대기 후 다음 step 순서 유지
- REMIND 완료/무음 후 STT 재개

### 온보딩 remote/Outbox

- exact POST path/body/auth/result
- group create보다 completion이 먼저 admission되지 않음
- create settlement 후 remote group ID body 생성
- ambiguous exact replay
- processing conflict bounded replay
- definitive rejection blocked
- app reopen replay
- same member new session stale response 무시
- other member transition 무시
- 성공 settlement 후 Outbox 제거
- account cleanup/reset에서 completion row 제거

### 사용자 시나리오

- 로그인 상태에서 온보딩 완료
- 로그아웃 상태에서 온보딩 완료 후 소셜 로그인
- 로그인 직후 오프라인, 이후 네트워크 복구
- group create 성공 후 completion 응답 유실
- completion 성공 직후 앱 종료/재실행
- 서버 상태가 이미 true인 재로그인
- voice A 캐시 후 voice B 선택
- 공통 asset version 증가

## 구현 순서와 권장 커밋 단위

1. `GET /tts` DTO/domain/contract tests
2. 공통 cache identity와 storage tests
3. common warmup/provider 및 dependency wiring
4. DONE/REMIND player 전환과 timer reminder 제거
5. onboarding completion remote contract
6. Outbox command/admission/request/response/settlement
7. signed-in onboarding 및 login backfill enqueue
8. account credentials/status completion 반영
9. 문서·gate 갱신과 전체 회귀 검증

각 단계는 관련 focused test를 통과시킨 뒤 다음 단계로 진행한다. TTS와 onboarding
작업을 하나의 거대한 변경으로 묶지 말고, 중간 상태에서도 빌드 가능한 단위로 유지한다.

## 자동 검증

최소 검증:

1. 변경된 계약/서비스/player/sync focused XCTest
2. 전체 `MoruTests`
3. `bash Scripts/check-iphone-functional-gate.sh`
4. `bash Scripts/check-swiftdata-boundary.sh`
5. iPhone Simulator Debug build
6. generic iPhone Debug/Release build
7. `git diff --check`

SwiftData schema를 변경하지 않았다면 schema/migration delta가 없음을 확인한다. 변경이
생기면 기존 저장소 reopen migration 테스트를 추가하고 검증 전까지 완료로 표시하지 않는다.

## 실제 서버/기기 QA

자동 테스트만으로 다음 항목을 통과 처리하지 않는다.

- 운영/스테이징 `GET /tts`에서 선택 voice의 공통 파일 실제 다운로드
- voice 변경 뒤 INTRO 재합성 version과 공통 cache version의 독립 동작
- 실제 스피커/Bluetooth/interruption에서 DONE/REMIND 재생
- local-first 소셜 로그인 뒤 서버 `/onboarding/status == true`
- offline/relaunch 후 Outbox 재전송

검증하지 못한 항목은 최종 보고에서 미검증으로 명시한다.

## 완료 정의

- 로그인 사용자는 선택한 서버 voice로 INTRO, DONE, 입력 REMIND를 듣는다.
- 서버 voice가 준비되지 않았을 때 다른 voice를 듣지 않으며 루틴은 멈추지 않는다.
- custom 단계에도 DONE이 적용된다.
- timer 중간 REMIND는 없고 5초 countdown과 자동 전환은 유지된다.
- voice/common version 변경 시 stale 공통 파일이 재생되지 않는다.
- signed-in 및 local-first 로그인 온보딩이 모두 서버 true로 최종 수렴한다.
- 앱 종료, 오프라인, 재로그인, 계정 전환에도 intent가 유실되거나 오염되지 않는다.
- 문서, focused tests, 전체 XCTest, 기능 gate, 빌드 검증이 통과한다.

## 새 작업 세션 시작 지침

1. 이 문서 전체를 읽는다.
2. `git status --short`로 사용자 변경사항을 확인하고 보존한다.
3. 현재 코드가 이 문서 작성 이후 변경됐는지 관련 파일을 다시 검색한다.
4. 위 구현 순서로 계획을 등록하고 1단계부터 구현한다.
5. 서버 계약을 추측해 바꾸지 않는다. 불일치는 실제 병합 코드/응답으로 재확인한다.
6. 각 단계의 focused test와 마지막 전체 gate까지 실행한다.

