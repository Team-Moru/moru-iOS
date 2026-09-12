# Self-hosted macOS 러너 설정

> **상태 (2026-09-10): 보류.** 당분간 GitHub에 올리기 전 로컬에서 개발·테스트를 끝내는
> 흐름을 기준으로 하므로 self-hosted 러너와 자동 CI는 도입하지 않는다. 팀 PR이 늘거나
> 자동 테스트가 필요해지면 이 문서대로 도입한다. 그때까지는:
>
> - `.github/workflows/ios-tests.yml`은 **수동 실행(`workflow_dispatch`)만** 받는다.
>   러너가 없어도 `queued` 실행이 쌓이지 않는다. `pull_request`/`push` 트리거는 파일 안에
>   주석으로 남겨 두었다.
> - 브랜치 보호 규칙의 required check에 `iOS Tests`를 **추가하지 않는다**.
> - 로컬 검증은 `bash Scripts/run-tests.sh smoke|full`
>   (`Moru/docs/iPhoneFunctionalGate.md` 자동 검증 절)로 한다.
>
> 재도입 절차: (1) §2대로 러너 등록 → (2) `ios-tests.yml`의 트리거 주석 해제와 fork 가드
> `if:` 복원 → (3) required check 지정.
>
> ~~사전 실패 3건 정리~~는 2026-09-12에 끝났다(§7). 남은 걸림돌은 러너 등록뿐이다.

`.github/workflows/ios-tests.yml`은 `runs-on: [self-hosted, macOS]` 러너에서
`Scripts/run-tests.sh`를 실행합니다. GitHub 호스팅 macOS 러너는 분당 과금이 Linux의
10배라, 팀 Mac 한 대를 러너로 등록해 비용 없이 테스트를 돌리는 구성을 기본으로 합니다.

`pull_request`/`push` 트리거를 되살린 뒤 러너가 없으면 `iOS Tests` 워크플로가 `queued`
상태로 남습니다. **러너를 등록하기 전까지 브랜치 보호 규칙의 required check에
`iOS Tests`를 추가하지 마세요.**

## 1. 요구 사항

- Apple Silicon Mac, macOS 15 이상, 로그인된 GUI 세션(시뮬레이터가 필요합니다).
- Xcode 26.5 이상. 처음 한 번 `sudo xcodebuild -runFirstLaunch`.
- iOS 26.5 시뮬레이터 런타임 (Xcode → Settings → Components).
- `brew install ripgrep` — `Scripts/check-swiftdata-boundary.sh`가 `rg`를 사용합니다.
- 선택: `brew install xcbeautify` — 있으면 `run-tests.sh`가 출력을 정리합니다.

## 2. 러너 등록

1. GitHub에서 `Team-Moru/moru-iOS` → Settings → Actions → Runners → New self-hosted runner
   → macOS / ARM64 를 고릅니다. 화면에 표시되는 다운로드·설정 명령을 그대로 따릅니다.
   등록 토큰은 1시간만 유효하며 리포 관리자 계정으로만 발급됩니다.
2. `./config.sh` 실행 시 라벨은 기본 `self-hosted, macOS, ARM64`에 추가 라벨 없이 두면
   워크플로의 `[self-hosted, macOS]`와 일치합니다. 러너 이름은 `moru-mac-1` 처럼 기기를
   식별할 수 있게 짓습니다.
3. 서비스로 등록해 재부팅 후에도 살아 있게 합니다.

   ```bash
   ./svc.sh install
   ./svc.sh start
   ./svc.sh status
   ```

4. 시스템 설정에서 자동 잠자기·화면 잠금 시 세션 종료를 끕니다. 러너는 GUI 세션이
   있어야 시뮬레이터를 띄울 수 있습니다.

## 3. 시뮬레이터 준비

`run-tests.sh`는 `MORU_SIMULATOR_UDID` → `xcodebuild -showdestinations`의 첫 iOS
Simulator → `simctl list`의 첫 iPhone 순으로 대상을 고릅니다. CI 전용 기기를 하나 만들어
두고 UDID를 고정하는 것을 권장합니다.

```bash
xcrun simctl list runtimes            # iOS 26.5 런타임 식별자 확인
xcrun simctl create "Moru CI" "iPhone 17" "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
```

러너 디렉터리의 `.env` 파일에 다음을 추가하면 워크플로 환경변수로 전달됩니다.

```
MORU_SIMULATOR_UDID=<위에서 만든 UDID>
```

## 4. 보안

- 워크플로는 fork에서 온 PR을 실행하지 않습니다
  (`github.event.pull_request.head.repo.full_name == github.repository` 가드).
- Settings → Actions → General 에서 "Require approval for all outside collaborators"를
  켭니다.
- 러너 계정에는 서명 인증서·프로비저닝 프로파일·Keychain 항목을 두지 않습니다.
  `run-tests.sh`는 `CODE_SIGNING_ALLOWED=NO`로 빌드합니다.
- `persist-credentials: false`로 체크아웃하므로 워크스페이스에 토큰이 남지 않습니다.

## 5. 운영

- 산출물은 `build/`(DerivedData, SourcePackages, TestResults, captures)에 쌓입니다.
  디스크가 부족해지면 러너 작업 디렉터리의 `build/`를 지웁니다.
- 시뮬레이터가 이상하면:

  ```bash
  xcrun simctl shutdown all
  xcrun simctl erase all
  ```

- 실패한 실행의 `.xcresult`는 워크플로 아티팩트(`smoke-test-results`,
  `full-test-results`)로 올라갑니다. Xcode에서 열어 확인합니다.
- 다음 테스트는 `MORU_CAPTURE_OUTPUT_DIR`를 따르지 않고 `/private/tmp` 또는 `/tmp`에
  직접 씁니다. 러너 계정이 해당 경로에 쓸 수 있어야 하고, 동시 실행 시 서로 덮어씁니다.
  (`FinalScreenVisualTests.swift`는 2026-09-10에 공용 캡처 픽스처로 옮겨져
  `MORU_CAPTURE_OUTPUT_DIR`를 따르므로 이 목록에서 뺐다.)
  - `MoruTests/HistoryRunReportingTests.swift`
  - `MoruTests/OnboardingFigmaVisualTests.swift`
  - `MoruTests/HomeProfileFigmaVisualTests.swift`
  - `MoruTests/HomeRoutineIntegrationTests.swift`
  - `MoruTests/HomeRoutineServerNoticeTests.swift`

## 6. 테스트 플랜

| 플랜 | 대상 | 용도 |
| --- | --- | --- |
| `MoruSmoke` | `MoruTests`에서 화면 캡처(렌더) 테스트를 제외한 전부 | PR마다 실행 |
| `MoruFull` | `MoruTests` 전체 + `MoruUITests` | `main` 푸시마다 실행 |

로컬에서도 같은 스크립트를 씁니다.

```bash
bash Scripts/run-tests.sh smoke
bash Scripts/run-tests.sh full -only-testing:MoruTests/FinalScreenVisualTests
bash Scripts/run-tests.sh build
```

## 7. 알려진 사전 실패 — 해소됨 (2026-09-12)

2026-09-10에 `main`에서 이미 실패하던 3건을 정리했다. **셋 다 제품 코드 버그가
아니라 테스트 기대값이 낡은 것**이었고, 각각 제품 쪽 사실을 확인한 뒤 테스트를
고쳤다. 이제 `MoruSmoke`는 `main`에서 초록이므로 required check로 올릴 수 있다.

| 테스트 | 실제 원인 | 조치 |
| --- | --- | --- |
| `AccountServerRemoteContractTests/testProfileRequiresMatchingMemberAndText` | 닉네임 없는 프로필을 허용하도록 제품 코드를 고친 적이 있는데(`RemoteAccountServerService.swift`의 주석 참고 — 닉네임 scope 없는 카카오 가입) 테스트만 예전 기대값을 들고 있었다 | 해당 케이스를 제거하고, "닉네임 미설정은 오류가 아니라 빈 문자열"을 `testProfileTreatsMissingNicknameAsNotSetYet`으로 새로 고정했다. 나머지 4개 불변식은 그대로 |
| `ServerRoutineSuggestionTests/testImmediateDisappearanceAfterCTAStopsRequestBeforeItStarts` | 온보딩 흐름의 `.goals`는 코디네이터를 거치지 않는다. `refreshPreview()`가 동기로 성공해 그 자리에서 단계를 넘긴다. 취소할 요청이 애초에 없어 취소를 검증할 수 없었다 | 코디네이터가 실제로 호출되는 `.freeform`으로 옮겨 취소를 검증하고, 전제였던 "`.goals`는 로컬이 이긴다"를 `testOnboardingGoalsResolvesLocallyWithoutConsultingCoordinator`로 따로 고정했다 |
| `OnboardingStatusRuntimeCoordinatorTests/testAccountSwitchDoesNotPublishDelayedPreviousAccountResponse` | 테스트 레이스. `waitUntil { latestResolution != nil }`을 아직 지워지지 않은 **이전 계정의 결과**가 즉시 만족시켰다. 정작 요지인 "지연 응답을 채택하지 않는다"(뒤쪽 단언)는 통과하고 있었다 | 기다리는 조건을 `latestResolution?.identity == secondIdentity`로 바꿨다. stale 방어 자체는 제품 코드가 이미 하고 있다 |

### 간헐적으로 멈추던 테스트 — 해소됨 (2026-09-12)

| 테스트 | 실제 원인 | 조치 |
| --- | --- | --- |
| `RoutineTTSAudioStorageTests/testPurgeCancelsOldLoadAndDoesNotRemoveSameKeyReplacement` | 제품 코드가 아니라 **테스트 헬퍼 `TestGate`의 lost wakeup**. `open()`이 이미 저장된 continuation만 깨우기 때문에, 로더가 `wait()`으로 게이트 액터에 들어오기 전에 `open()`이 이기면 깨움이 사라지고 뒤늦게 park한 `wait()`이 영원히 매달린다. 그대로 180초 상한에 걸렸다. 실기기는 스케줄링이 달라 재현되지 않아 제품 문제로 오해하기 쉬웠다 | 게이트가 열림을 기억하게 했다(`isOpen`). 더불어 `Task.yield()` 한 번으로 "로드가 진행 중"을 가정하던 부분을 `waitUntilWaiting()`으로 바꿔, 테스트가 의도한 "진행 중인 로드를 purge가 취소한다"를 실제로 만들도록 했다. 30회 연속 통과(합계 0.22초) |
| `HistoryRunReportingTests/testRunDetailDestinationRejectsMissingAndDuplicateRunIDs` | 2026-09-10에 한 번 실패한 뒤 재현되지 않았다. 이후 전체 실행에서도 나오지 않는다 | 관찰만 유지. 재발하면 원인을 따로 찾는다 |

`MoruSmoke`는 이제 `main`에서 초록이고, 알려진 실패도 간헐 정지도 없다.
`skippedTests`로 회피한 테스트는 없다.

