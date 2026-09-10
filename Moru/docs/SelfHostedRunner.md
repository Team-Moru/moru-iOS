# Self-hosted macOS 러너 설정

`.github/workflows/ios-tests.yml`은 `runs-on: [self-hosted, macOS]` 러너에서
`Scripts/run-tests.sh`를 실행합니다. GitHub 호스팅 macOS 러너는 분당 과금이 Linux의
10배라, 팀 Mac 한 대를 러너로 등록해 비용 없이 테스트를 돌리는 구성을 기본으로 합니다.

러너가 등록되기 전에는 `iOS Tests` 워크플로가 `queued` 상태로 남습니다. **러너를 등록하기
전까지 브랜치 보호 규칙의 required check에 `iOS Tests`를 추가하지 마세요.**

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
  - `MoruTests/FinalScreenVisualTests.swift`
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

## 7. 알려진 사전 실패 (2026-09-10 기준)

`MoruSmoke`를 처음 돌렸을 때 아래 3건은 `main`에서 이미 실패하고 있었다. 단독 실행에서도
같은 값으로 재현되므로 플레이키가 아니라 코드와 기대값이 어긋난 상태다. 러너를 켜면
이 3건 때문에 PR 체크가 빨간불이 되니, 별도 작업으로 원인을 정리한 뒤 required check로
올린다.

| 테스트 | 증상 |
| --- | --- |
| `AccountServerRemoteContractTests/testProfileRequiresMatchingMemberAndText` | 빈 닉네임 프로필을 `invalidResponse`로 기대하지만 통과시킨다 (닉네임 없는 프로필 허용 수정과 충돌) |
| `ServerRoutineSuggestionTests/testImmediateDisappearanceAfterCTAStopsRequestBeforeItStarts` | 화면 이탈 직후에도 추천이 진행돼 `step`이 `suggestedRoutine`이 된다 |
| `OnboardingStatusRuntimeCoordinatorTests/testAccountSwitchDoesNotPublishDelayedPreviousAccountResponse` | 계정 전환 뒤 이전 계정(memberID 21)의 지연 응답이 채택된다 |

뒤의 두 건은 온보딩·계정 전환의 stale 응답 처리 문제일 수 있어 로드맵 5·6단계에서
제품 코드 쪽을 먼저 확인한다.

### 간헐적으로 멈추는 테스트

| 테스트 | 증상 |
| --- | --- |
| `RoutineTTSAudioStorageTests/testPurgeCancelsOldLoadAndDoesNotRemoveSameKeyReplacement` | 세 번 중 두 번 await에서 돌아오지 않았다. 테스트 플랜의 실행 시간 상한(180초)에 걸려 실패로 기록된다. |
| `HistoryRunReportingTests/testRunDetailDestinationRejectsMissingAndDuplicateRunIDs` | 한 번 실패한 뒤 단독 실행 2회는 통과했다. |

플레이키가 반복되면 해당 테스트만 `MoruSmoke`의 `skippedTests`에 넣고 `MoruFull`에서만 돌린다.

