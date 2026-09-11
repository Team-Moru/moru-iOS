# UI · UX · 아키텍처 감사 브리프 (2026-09-10)

> 8개 관점(앱 조립·라우팅 / 디자인 시스템 / 온보딩·홈·루틴설정 UX / 플레이어·알람·이력·프로필 UX /
> 계층 구조 / 상태·동시성 / 테스트·도구 / 문서 대비 실제)을 읽기 전용으로 매핑하고, 각 관점을
> 적대적으로 재검증한 뒤 종합·비평한 결과입니다. 코드 인용은 `main` @ `bcb0d86` 기준입니다.
>
> 이 브리프를 바탕으로 결정된 사항과 로드맵은 아래 "결정 요약"에 있습니다.
> 구현 순서·커밋 분할은 각 단계 브랜치의 커밋 메시지를 따릅니다.

## 결정 요약 (2026-09-10)

| 항목 | 결정 |
|---|---|
| 우선 축 | UX·아키텍처 공동 1순위. UI는 iOS 26 Liquid Glass 네이티브 전면 채택. Figma는 참고. |
| 집중 영역 | 온보딩·계정 진입 / 홈·루틴 설정 / 루틴 실행. 이력·프로필 후순위. |
| 0단계 | 공유 scheme + smoke/full 테스트 플랜 + `Scripts/run-tests.sh` + self-hosted Mac 러너 워크플로. |
| 1단계 | 토큰·CTA 통일, 고정폭 제거, 미사용 자산 삭제, 텍스트 스타일 단일화, `MoruPilot*` → `Moru*`. |
| CTA 대비 | 주요 CTA 배경 orange550(#E84000). 요일 미선택 대비도 함께 상향. |
| 시각 기준선 | dHash + after.png 방식 유지·재승인. `FinalScreenVisualTests` 우회로 제거. |
| 저장 실패 | 종료 의도 게이트를 분리해 "기록 없이 나가기"를 항상 허용. |
| 마이크 거부 | 권한 거부·인식기 불가 같은 영구 실패에만 큰 완료 버튼 노출. |
| 홈 대표 카드 | 다음 알람 시각 + 예약 상태가 주인공, 시작은 명시 버튼, 본문 탭은 해당 루틴 편집. |
| 탭 상태 | 네이티브 TabView 상태 보존 수용. 기록 탭만 재진입 시 데이터 새로고침. |
| 알람 정지 실패 | 플레이어 상단 재시도 배너. 표시 승인 후 정지, `.deferredBusy`는 정지하지 않음. |

로드맵: 0 안전망 → 1 토큰·CTA 통일 → 2 루틴 실행 탈출구·안전 → 3 Liquid Glass 전환 →
4 홈·루틴 설정 UX → 5 온보딩·계정 진입 → 6 아키텍처 심화·음성 코칭.

---

# 모루(Moru) iOS 결정 브리프 — 감사 결과 종합 (개정판)

> 근거는 8개 차원 매핑 + 8개 적대적 검증입니다. `refuted` 항목은 제외, `partially`는 교정된 증거로 교체, 검증자가 새로 찾은 `missed` 항목은 ★로 표기했습니다. 초판에서 누락·오기된 부분은 본문에 반영했고, 무엇을 왜 고쳤는지는 맨 끝 「검토 메모」에 있습니다.

---

# 1. 현재 상태 한눈에

| 항목 | 수치 | 근거 |
|---|---|---|
| 프로덕션 Swift 파일 / 라인 | 304개 / 63,525줄 | 폴더별: Features 18,870 · Domain 12,583 · Data 11,126 · Platform 7,429 · **RoutineFlow 5,680(Features 하위가 아니라 10번째 top-level ★)** · App 3,484 · DesignSystem 2,966 · Network 1,234 |
| 500줄 초과 프로덕션 파일 | 33개 | 최대: `RoutineTTSWarmupCoordinator.swift` 1,975 / `SwiftDataRoutineSyncRepository.swift` 1,953 / `OnboardingFlowView.swift` 1,799 / `ProfileView.swift` 1,427 / `HistoryView.swift` 1,213 |
| 테스트 | 79 클래스 · 1,027 함수 · 3,948 assert · 52,965줄 | 파일에 기록된 소스 대비 비율 0.84는 교정 전 53,208줄 기준이며, 교정값으로는 ≈0.83 |
| **CI에서 실행되는 테스트/빌드** | **0** | 워크플로 3개·잡 4개 전부 `ubuntu-latest`, `xcodebuild` grep 0건, 실측 소요 38~56초 |
| shared scheme / xctestplan / swiftlint / swiftformat / xcconfig / fastlane | 0 / 0 / 0 / 0 / 0 / 0 | `git ls-files` 기준 xcodeproj 추적 파일 3개뿐 |
| 프로토콜(리포 전체) / UseCase | 117개 / UseCase 16개 3,168줄 | pass-through 아님 (`RoutineSettingUseCase.swift:78-96` 등). **117은 Domain 한정이 아니라 리포 전체 수치** |
| DI 컨테이너 | 프로퍼티 28개, existential 20개, Optional 19개, 구상 Platform 타입 8개 | `App/DependencyContainer.swift:11-41`. 경계 테스트는 초기 5개만 검사(`FoundationSwiftDataTests.swift:579`) ★ |
| 관찰 모델 분열 | `@Observable` 14 / `ObservableObject` 8(프로덕션 7) / 수동 `objectWillChange` 2 | `OnboardingViewModel.swift:35` + willSet 8개, `SessionStore.swift:19` |
| Task 소유권 | `Task {` 149개 중 프로퍼티 소유 22개, 비소유 93개, deinit 3개 | `Task.detached` 1, `DispatchQueue` 1 |
| stale 폐기 관용구 | 18개 파일에 최소 5가지 방식 ★ | UUID requestID / Int generation / identity 비교 / in-flight 딕셔너리(`TokenRefreshCoordinator.swift:32`, `RoutineTTSAudioCache.swift:122`, `OnboardingRecommendationCoordinator.swift:158`) / continuation fan-out(`HomeWeatherService.swift:454-479`) |
| 공용 컴포넌트 사용 | 21개 중 9개 프로덕션 0회, `MoruCard`·`MoruBottomCTA`는 전역 참조 0 | 아이콘 struct 23개 중 참조 0인 것 10개 ★ |
| 미사용 토큰 | AppColor 14/56, AppFont 11/24, AppIcon 18/52(이미지 에셋 18개 실재, 전체 imageset 66개의 27%) ★ | `AppShadow` 프로덕션 사용 0 |
| 토큰 시스템 이중화 | Features의 `MoruPilot*` 764회 vs `AppSpacing` 121 · `AppRadius` 11 | 같은 이름 다른 값: `textStrong` #1C1C36(AppColor) vs #3C3D5E(MoruPilot) |
| 화면 거터 | `.padding(.horizontal)`에 8종 — `MoruPilotSpacing.twenty` 39 · `.sixteen` 16 · raw 20 10 · `AppSpacing.screenHorizontal` 6 · raw 18 4 · raw 22 2 | spacing 토큰을 radius로 오용: `cornerRadius: MoruPilotSpacing.sixteen` 9회, `.twelve` 8회 |
| RoutineFlow raw 값 | padding 50 · spacing 66 · cornerRadius 9 · 고정 frame 41, `AppSpacing`/`AppRadius` 각 0회 | 들여쓰기 4-space 13파일 vs 2-space 291파일, 포매터 설정 없음 |
| 대비비 (WCAG) | CTA 흰글씨/orange350 **2.12:1** · 비활성 카드 설명 **1.45:1** · 요일 미선택 **1.70:1** ★ · coral300 에러 2.37:1 · textTertiary 2.64:1 | orange500로 올려도 3.09:1 |
| 다크 모드 | colorset 57개 전부 dark variant 0, `MoruApp.swift:97 .preferredColorScheme(.light)` | 도달 불가 다크 분기 `HomeView.swift:481,496` |
| 텍스트 스타일 | 이름 8종 · 구현 5벌 · 호출 약 217회 | AX 크기에서 line-height 처리가 화면마다 다름 |
| 접근성 | `isAccessibilitySize` 분기 111곳, a11y 라벨/힌트/값 166곳(메트릭 합계), 44pt 명시 20곳 ★ | `isIdleTimerDisabled` **0곳**, RoutineFlow 포그라운드 복귀 핸들러 **0곳** |
| 애니메이션 | 호출부 14곳(Features 9 · RoutineFlow 5), duration 다수·spring 파라미터 4종, reduceMotion 존중 5곳 | 모션 토큰 0 |
| 리팩터링 계획 진척 | 10개 항목 중 **0개 착수**, 대상 파일 합계 14,661 → 14,734줄(**+73**) | `SwiftDataRoutineSyncRepository` +48, `RoutineTTSWarmupCoordinator` +45 |
| 리포 크기 | size-pack **937.51 MiB**, `figma-pilot-review-bundle` PNG 941장 854MB, LFS 없음 ★ | 추적 파일 1,169개 |
| 미추적 문서 | **원인이 둘로 다름** ★ — `mydocs/`는 `.git/info/exclude:9`로 제외되어 8/10 파일 3,679줄이 다른 클론에 존재조차 안 함 / `Moru/docs/VoiceCoachingUXHandoff.md` 821줄은 gitignore 대상이 아닌 단순 미추적(`git status`의 유일한 `??`) | 합계 약 4,500줄 |
| Swift 버전 불일치 | 앱 타깃 6.0(+`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`), 6.2 타깃 4개(테스트·UI테스트, 플래그 없음) | `project.pbxproj:456,457,460 / 526,551,570,588`, README는 6.2 표방(`README.md:9,52`) |

---

# 2. 잘 되어 있는 것 (리팩터링이 반드시 보존해야 함)

1. **모달 네비게이션이 순수 reducer로 분리**되어 있고 UUID presentation token + dismissalArmed 2단계 해제까지 모델링됨. `AppNavigationCoordinator.swift:146-304`, `RouterRuntimeContractTests.swift`(1,580줄)가 이를 고정. *단, 라우터 테스트가 갈아끼울 수 있는 FlowBuilder는 5종 중 3종뿐이다(`AppRouter.swift:102-104`) — History/Profile 빌더는 `mainTabView` 안에서 하드코딩 생성되므로 메인 탭 조립은 계약 테스트 밖이다 ★.*
2. **스키마 마이그레이션 전략이 실제로 지켜짐.** `MoruSchema.swift`에 V1~V6 + lightweight 5단계, 단계별 마이그레이션 테스트 5개 실재(`AlarmSchedulingFoundationTests.swift:415`, `RoutineSyncFoundationTests.swift:586,805`, `ServerRoutineRestorationTests.swift:1220`).
3. **Network 계층이 코드베이스에서 가장 잘 설계됨.** `APIClient.swift:106`의 actor가 요청 전(468-500)·응답 후(502-515) memberID+sessionID를 이중 검증하고, 비멱등 경로는 `requestOnce`(207-239)로 401 replay에서 분리. `MemoryAccessTokenProvider.swift:49-60`은 NSLock + memberID/snapshot/sessionID 3중 일치 compare-and-swap으로 계정 전환 중 토큰 덮어쓰기를 막고, `APIClient.swift:613-633`의 `RequestCancellation`은 cancel-before-store 경합을 lock으로 정확히 처리한다 ★.
4. **outbox 직렬 드레인의 교과서적 구현** — `RoutineSyncRuntimeCoordinator`의 단일 drainTask + generation + wakePending 합류. 토큰 재발급도 `TokenRefreshCoordinator.swift:32`가 in-flight 합류 + `lastSuccessfulRotation`으로 늦게 온 401까지 흡수.
5. **UseCase가 pass-through가 아님.** 활성 루틴 요일 충돌 정책(`RoutineSettingUseCase.swift:78-96`), 서버-로컬 바인딩 8단계 정합성(`EnrichHomeRoutinesUseCase.swift:191-299`).
6. **홈 상태 모델링.** `HomeViewState`가 `loading(previousContent:)`로 새로고침 중 콘텐츠 유지, 실패를 배너/전체화면으로 분기(`HomeView.swift:124-135, 147-158`). 서버 실패해도 로컬 루틴을 계속 보여줌.
7. **플레이어 상태 게이트가 단일화**되어 있고, 다이얼로그 중 도착한 완료 이벤트를 `pendingStepCompletion`으로 보류·재적용(`RoutinePlayerViewModel.swift:300-317, 552-567`). 안내 재생 완료를 실제로 await한 뒤 STT 시작(`VoiceInputControlView.swift:104-116`). **⚠️ 이 강점과 §3.3 C1은 같은 코드다** — `isStepInteractionDisabled`(`:107`)가 그 단일 게이트이며 `pendingSave`까지 포함해 종료를 막는다. 게이트를 없애는 게 아니라 "종료 의도"만 별도 게이트로 빼야 강점이 보존된다.
8. **결정적 캡처 인프라.** `MoruVisualCaptureFixture.swift:41-62,95-157` — 393×852@3x, ko_KR, Asia/Seoul, 고정 시각, view/layer 트리를 **2회 연속 동일해질 때까지 최대 8패스** 안정화.
9. **동결 계약을 CI가 문구 단위로 강제.** `check-iphone-functional-gate.sh:23,36,58,61-69,74-82` — README 7문구 + 게이트 문서 7문구.
10. **Swift 6 격리를 진지하게 지킴.** `@MainActor` 484 / `nonisolated` 499 / actor 6, `CancellationError` 명시 분기 99곳, GCD 잔재 1곳. `nonisolated(unsafe)` 3곳도 전부 `completionLock` 내부 접근 ★.

---

# 3. 집중 영역별 핵심 문제

## 3.1 온보딩·계정 진입

**A1. 첫 실행 온보딩의 AI 추천은 구조적으로 도달 불가능한데 4초 가짜 연출로 AI인 척한다.** `AppRouter.swift:375`가 온보딩 체험 완료 후에만 AccountEntry로 보내므로 온보딩 시점은 항상 signedOut이고, `RoutineSuggestionCoordinator.swift:137`이 즉시 로컬 템플릿을 반환한다(성공 경로가 `OnboardingViewModel.swift:567`에서 `.localFallback(.signedOut)`을 하드코딩). 그런데 `OnboardingViewModel.swift:1038-1092`가 1초×3단계+1초 = 약 4초 체크리스트를 재생하고 `OnboardingFlowView.swift:424`는 "모루가 추천하는 나만의 루틴이에요"라고 말한다. 사용자가 200자를 써넣고 받은 결과가 자기 입력과 무관하면 "AI가 별로"가 아니라 "내 입력이 무시됐다"로 읽힌다. **영향: 첫 인상 신뢰 붕괴 / 노력 S(카피+연출) ~ M(정책 변경 시)**

**A2. ⚠️ 알람 예약 실패·권한 거부가 어디에도 도달하지 않는다.** `CompleteOnboardingUseCase.swift:107-111`이 `_ = try? await alarmScheduleMutator.apply(...)`로 결과를 버리고, 추천 추가 경로도 `RoutineCreationSheet.swift:100-102`가 `requiresAlarmRepair`를 폐기한다. 온보딩 완료 화면(`OnboardingFlowView.swift:909-937`)은 기상 시각·요일·예약 여부를 한 번도 재확인시키지 않는다 ★. **알람 앱이 "내일 안 울림"을 침묵으로 처리 / 노력 M — AlarmKit·스케줄링 계약 접촉**

**A3. 로그인 화면이 로컬 우선 메시지를 렌더링하지 않는데 테스트는 그걸 검증한다.** `AccountEntryView.swift:319-332`(header)와 `:334-358`(localFirstCard)이 정의만 되고 body(`:235-279`)에서 호출되지 않는다. 반면 `OptionalLoginEntryVisualTests.swift:134-147`은 화면에 없는 `localFirstGuidance` 장문으로 레이아웃을 검증한다. 게다가 정책 URL 미비 시 소셜 버튼 3개가 전부 disabled 되는데(`:488/494/500`) 안내 문구(`:539-548`)는 이유를 말하지 않는다 ★. **노력: S**

**A4. 목소리를 두 번 들을 수 없고, 온보딩 전체에 마이크 진입점이 0개다.** `MoruVoiceCard.swift:27-30`의 `isSelected.toggle()`이 `OnboardingFlowView.swift:894-901`의 setter에서 false로 무시돼, 이미 선택한 목소리를 다시 누르면 미리듣기가 재생되지 않는다. 카드에는 재생 아이콘이 있어 재생을 약속하고, `previewVoice`의 실패 결과도 버려진다(`OnboardingViewModel.swift:426`). 같은 카드는 a11y 라벨/`.isSelected` trait이 0개, 폰트는 `relativeTo` 없는 16/12pt 절대 크기, 높이 minHeight 65 고정 ★. 자연어 입력 단계(`OnboardingFlowView.swift:595-670`)도 TextEditor + 키워드 칩뿐으로 받아쓰기·마이크가 없다 — STT 인프라(`AppleSpeechRecognitionSession.swift:184`)는 이미 있으므로 기술 부재가 아니라 설계 누락이다. **음성 우선 제품의 마지막 선택 단계 / 노력: S(재청취·a11y) ~ M(마이크 입력)**

**A5. 첫 화면(experience)이 오탭 즉시 다음 단계로 넘어가고 되돌아와도 선택이 안 보인다** ★. `OnboardingFlowView.swift:331-338`이 `isSelected: false` 하드코딩 상태로 `selectExperience` + `primaryButtonDidTap`을 연속 호출하고, 이 단계엔 footer가 없다(`:1629`). 이 선택이 이후 분기 전체(`OnboardingViewModel.swift:711-733`의 progress 배열 포함)를 좌우한다. **노력: S**

**A6. 비활성 CTA가 이유를 말하지 않는다.** `OnboardingFlowView.swift:225-235`가 `.disabled(!canAdvance)`인데 이유 문구는 `OnboardingViewModel.swift:433-437`의 도달 불가 코드에만 있다(footer에 표시 자리는 `:202-207`에 있으므로 "표시 수단이 없다"가 아니라 "설정될 일이 없다"가 정확). 알람 단계에서 요일을 모두 해제하면 CTA가 조용히 회색이 된다. 같은 패턴이 `RoutineStepAddSheet.swift:171,174`에도 있다. **노력: S**

**A7. 추천 추가 플로우 진행률이 5/8에서 시작해 7/8에서 끝난다.** `OnboardingViewModel.swift:157-159`가 비온보딩 모드에 상수 8을 쓰고 `OnboardingStep.swift:36-43`의 freeform=5를 그대로 노출한다. 온보딩 모드 진행률만 테스트가 있고(`OnboardingHappyPathTests.swift:286-322`) 추천 추가 모드는 테스트가 없다. **노력: S**

**A8. AI 동의 시트 유실 시 추천이 무기한 정지한다.** `GeminiDataConsentStore.swift:213-215`의 `guard isConsentPresentationRequested`가 이미 true여서 `.deferred`로 빠지지 못하고 `waitForDecision()`에 매달린다. 탈출구는 우상단 취소뿐. **유실이 실제로 일어날 수 있는 경로는 한 곳으로 특정된다 ★** — `AppRouter.swift:307`에서 동의 시트를 요청한 직후 `:315-317`이 같은 앵커에 알람 fullScreenCover 표시를 요청한다(초판이 든 "온보딩 체험 커버 위에 겹침" 시나리오는 `rootDestination`(`:375-398`)상 도달 불가이므로 근거에서 제외). **노력: M**

**A9. 권한 요청이 전부 최악의 타이밍에 처음 뜬다.** 위치는 홈 첫 진입 `task`에서 자동(`HomeView.swift:176` → `HomeViewModel.swift:355`), 알람은 온보딩 완료 화면의 "루틴 체험하기"를 누른 순간(`AlarmScheduleMutationCoordinator.swift:284-292`가 첫 호출 지점), 마이크는 **새벽 루틴 도중 입력형 단계**(`AppleSpeechRecognitionSession.swift:182-186`)다. 알람 단계의 유일한 안내는 "알람 소리와 음량은 iPhone 설정을 따라요."(`OnboardingCopy.swift:17`)로 권한 예고가 없다. **노력: S(사전 설명) ~ M(요청 시점 이동)**

**A10. 온보딩 체험 도중 앱이 죽으면 사용자는 로그인 화면을 영영 보지 못한다** ★. 루트 전이 입력 4개가 `AppRouter.swift:67-70`의 View-local `@State`라 프로세스 종료 시 리셋되는데, 프로필은 이미 저장돼 있으므로 `AppRouter.swift:401-403`의 `if hasLocalProfile { return .main }`이 AccountEntry를 건너뛰고 곧장 홈으로 보낸다. `deferredOnboardingTrialRoutineID`도 함께 소실된다. 계정 연결은 마이 탭으로 직접 찾아가야만 가능해진다. **노력: M(플래그를 `AppRouterState`로 승격 + 무엇을 영속화할지 결정)**

## 3.2 홈·루틴 설정/편집

**B1. 대표 카드의 "루틴 시작"이 보이지 않고, 한 카드가 두 목적지를 갖는다.** `CurrentRoutineCard.swift:34`의 요약 블록 전체가 라벨·힌트·버튼 스타일 없는 Button으로 루틴을 즉시 실행하고, 헤더는 설정 시트를 연다. 아래 활성 루틴 섹션은 명시적 "루틴 시작" 알약 버튼을 갖는다(`HomeActiveRoutineSection.swift:183-197`). 오탭하면 `.interactiveDismissDisabled()`(`AppRouter.swift:248`) 전체화면 플레이어가 뜬다. 실행 거부 메시지는 화면 최하단(`HomeView.swift:267-273`). **반쯤 잠든 사용자의 오탭이 곧 0% 실행 기록 / 노력: S~M**

**B2. ⚠️ 대표 카드에 알람 시각이 없고, 앱 전체에 "예약 성공 여부" 표면이 사실상 없다.** `HomeRoutineState`(`HomeViewState.swift:266-277`)에 `alarmDeliveryState`가 없다. `scheduleText`는 존재하며 활성 루틴 섹션에서 alarm 아이콘과 함께 실제로 렌더된다(`HomeActiveRoutineSection.swift:125`) — 즉 문제는 "홈에 알람 시각이 전혀 없다"가 아니라 **대표 카드에 없고, 예약 상태는 루틴 탭 카드 한 곳(`RoutineSettingViewState.swift:83-84`)에만 있다**는 것이다. **노력: M**

**B3. 새벽 기상 시 홈 인사말이 "편안한 밤 되세요!"다.** `HomeHeaderView.swift:63-72`가 6시 이전을 전부 evening으로 분류하고 `HomeFigmaStyle.swift:13`이 그 문구다. 루틴을 막 끝내고 홈으로 돌아온 성취 순간에 앱이 잘 자라고 인사한다. 게다가 프로덕션에서 안 쓰이는 `HomeCopy.greeting`을 테스트가 아침 문구로 고정하고 있어 회귀로도 안 잡힌다 ★(`HomeProfileFigmaVisualTests.swift:18`). `#Preview`도 8/13/20시만 있어 새벽이 시각 검증에서 빠져 있다. **노력: S**

**B4. 특정 루틴을 눌러도 목록 시트가 열리고, 그 시트엔 닫기 버튼이 없다.** `HomeView.swift:259-261`이 routine.id를 버리고, a11y 라벨은 "설정 열기"를 약속한다(`HomeActiveRoutineSection.swift:105`). 시트로 뜬 `RoutineSettingView`는 toolbar가 0건(`:36-72`)이라 스와이프만이 탈출구. 더 근본적으로 **루틴 설정 화면이 탭(`MainTabView.swift:99-100`)과 시트로 이중 존재**한다 ★ — 홈 탭 액션을 "루틴 탭으로 전환"으로 바꾸면 모달 계층 하나가 통째로 사라진다. (중첩 시트는 3겹이 아니라 2겹이다 — `RoutineCreationSheet.swift:49-72`는 같은 시트 안 콘텐츠 교체다.) **노력: M**

**B5. 편집기의 "뒤로"가 확인 없이 모든 편집을 폐기한다.** `RoutineEditorView.swift:211-221`이 dirty 검사 없이 `dismiss()`를 호출한다. 같은 화면의 삭제에는 다이얼로그가 있어(`:397-430`) 파괴성 기준이 불일치하고, 시트도 `interactiveDismissDisabled` 미적용(`RoutineSettingView.swift:93`). **노력: S**

**B6. 생성 시점에 비활성 저장을 할 수 없어 충돌 다이얼로그를 강제로 통과해야 한다.** `RoutineSettingViewState.swift:145-150`의 `canSave`가 요일 1개 이상을 요구하고 편집기에 `isActive` UI가 0건. 목록에는 토글이 있으므로(`RoutineSettingView.swift:237-243, 293-301`) 막힌 건 "미리 만들어두기"다. `HomeViewModel.swift:775-778`의 "수동 실행" 분기는 앱 내 생성 경로가 항상 `AlarmSchedule`을 만들기 때문에(`RoutineSettingUseCase.swift:236-263`) 사실상 도달 불가다 — 단 `Routine.swift:62`에 `alarmSchedule: AlarmSchedule? = nil` 기본값이 있어 타입상 불가능한 것은 아니므로, 이건 확인이 아니라 추론이다. **노력: M**

**B7. 항목 재정렬 어포던스가 0이고 같은 행에 편집 경로가 2개다.** `RoutineEditorView.swift:538-571`이 0.18초 롱프레스+드래그인데 핸들·안내가 없고, `RoutineStepDraftRow.swift:27`의 인라인 TextField와 `:61-64`의 탭→시트가 공존한다. 시트(`RoutineStepAddSheet.swift:35-68`)엔 닫기 버튼이 없다(detent 499/559는 접근성 크기에서는 `[.large]`로 분기됨). **노력: M**

**B8. 파괴적 액션이 취소보다 강조돼 있다.** `MoruDialog.swift:66-79`가 primary(취소)=`moruTextSecondary`, secondary(실행)=`moruTextStrong`. destructive 컬러 미사용. `adaptsForAccessibility: true`는 RoutineFlow 두 다이얼로그(`EndRoutineDialogView.swift:33`, `SkipStepDialogView.swift:33`)에만 전달되고 Features의 4개는 legacy 경로. **legacy 고유 결함은 `relativeTo` 부재(`:52,58,160`)와 높이 54 고정이며, 폭 320 고정은 adaptive 경로(`:148`)에도 있다.** **노력: S(색 반전) / M(다이얼로그 통합)**

## 3.3 루틴 실행(알람·플레이어)

**C1. 저장이 한 번 실패하면 플레이어에서 나갈 방법이 사라진다.** `RoutinePlayerViewModel.swift:794-797`의 catch가 `pendingSave`를 남기고, `:107` 게이트가 이를 포함해 `requestExitDialog`(`:541-543`)·`confirmExit`(`:570-572`)를 막는다. 상단바는 `.disabled`(`RoutinePlayerView.swift:241`), 스와이프는 이중 차단(`:40`, `AppRouter.swift:248`). 살아 있는 컨트롤은 "다시 시도" 하나뿐. 자연 완료 경로는 `isExitEligible`(`:531-538`)이 `.stepCompleted`를 false로 두어 한 겹 더 두껍다 ★. **강제 종료가 유일한 탈출구 / 노력: S(코드) — 제품 결정 필요**

**C2. 화면이 잠기면 루틴이 회복되지 않는다.** `isIdleTimerDisabled` 0곳, RoutineFlow에 포그라운드 복귀 핸들러 0곳. 백그라운드 진입이 `RoutinePlayerView.swift:50-57` → `runtimeDidInterrupt` → `stopCurrentCue`로 generation을 올려 `waitUntilIntroFinishes`가 false를 반환하고, `VoiceInputControlView.swift:109-115`가 `automaticStartState = .manualOnly`로 **영구 고착**된다(`:149-158`이 `.ready`만 허용) ★. 타이머는 `TimerStepContentView.swift:101-103,65`가 1초 감산이라 **화면이 얼어붙는 게 아니라 백그라운드 경과 시간을 통째로 잃고 그만큼 길어지는 드리프트**가 생긴다. **핵심 사용 자세(폰 내려놓기)를 정면 부정 / 노력: M~L**

**C3. 마이크 권한이 거부되면 완수율이 강제로 0%가 된다.** `ConfirmStepContentView.swift:31-90`·`InputStepContentView.swift:20-85`에 수동 완료 버튼이 없고, 완료는 `VoiceInputControlView.onFinished` 하나뿐. 권한 거부 시 "설정 열기"만 뜨고(`:386-394`), 자동 건너뛰기는 `.failed(.silence)`에서만 발동(`:124-127`)한다. `transcriberUnavailable` 같은 영구 실패에도 "다시 시도"만 제공(`:396-404`). 유일한 탈출구인 건너뛰기는 14pt `gray300`(`RoutineStepSkipFooterView.swift:22-31`). **노력: S(버튼 추가) — 제품 결정 필요**

**C4. ⚠️ 침묵 구간이 전부 화면으로만 설명된다.** 30초 서버 음성 대기는 스피너+텍스트뿐이고 잔여 시간·즉시 시작이 없다(`RoutinePlayerView.swift:177-195`, 30초는 `RoutineTTSWarmupCoordinator.swift:20`). 두 번째 무발화에서 `VoiceInputControlView.swift:296-300`이 음성 고지 없이 즉시 건너뛰고, `RoutinePlayerViewModel.swift:374-402`가 `stepCompleted`를 거치지 않고 다음 단계로 간다. 핸드오프 문서 리트머스(`VoiceCoachingUXHandoff.md:260-268`) 실패. **(리마인더 구간은 실제로 음성이 재생되는 유일한 청각 개입이므로(`RoutineGuidanceCoordinator.swift:169-206`) 고지 부재는 '대기'와 '자동 건너뛰기' 두 곳에 한정 ★.)** **노력: M — TTS 무음 폴백 계약 접촉**

**C5. 타이머가 안내 음성 중에 이미 흐르고, 조기 완료·일시정지가 없다.** `TimerStepContentView.swift:153-158`이 `isGuidancePlaying` 게이팅 없이 `.onAppear`에서 시작하는데(그 값은 `:255-261` 라벨 렌더에만 쓰임), 확인형/입력형은 `waitUntilGuidanceFinishes`로 기다린다(`ConfirmStepContentView.swift:71`, `InputStepContentView.swift:64`). 유일한 액션은 건너뛰기(`:147-150`). 카운트다운 시스템 음성은 `RoutineGuidanceCoordinator.swift:208-220`에서 generation을 올려 **진행 중인 안내 큐를 문장 중간에 죽인다** ★(1~5초짜리 타이머는 `TimerStepContentView.swift:52-63`이 시작 즉시 announce를 반환해 intro가 첫 음절부터 잘린다). 핸드오프의 mid/wrap 큐를 얹으면 이 충돌이 매 단계 발생한다. **노력: M**

**C6. "닫기"와 "종료"가 구분 불가능하고 둘 다 0% 기록을 남긴다.** `RoutinePlayerView.swift:417-428/438-449`가 동일 폰트·색·크기이고 `:368-377`이 `.exit(_)` 와일드카드로 같은 다이얼로그를 띄우는데 결과는 summary/exit로 갈린다(`RoutinePlayerViewModel.swift:270-276, 707-735`). 되돌릴 수단 없음 — 플레이어에 이전 단계·취소 API가 하나도 없고(`:192-523`에 previous/undo 계열 0, 전이는 `:659-671` 단방향) 오인식만으로 자동 완료된다(`VoiceInputControlView.swift:180-182, 225-239`) ★. **노력: S**

**C7. ⚠️ AlarmKit 직접 진입이 admission 전에 알람을 끄고, stop 실패를 로그로만 처리한다.** `AppRouter.swift:729-730`이 결과 확인 전에 `stopAlarmWithoutBlockingRoutinePresentation`을 호출하고 `:757`이 `logger.error`로 끝난다(`AlarmRuntimeCoordinator.swift:95-97`이 `stopFailed`를 던지므로 실제로 알람이 계속 울린다). 대조군 `AlarmRingView.swift:209-211,163`은 오류 표시+재시도를 제공. `.deferredBusy`는 유실되지 않지만(`AppNavigationCoordinator.swift:371-374` → `AppRouter.swift:803-815`) **부활 경로가 dismissal 하나뿐**이고 in-memory `claimedNonces`(`OpenMoruRoutineIntent.swift:82-104`) 때문에 같은 프로세스 내 재진입(`AppRouter.swift:289-292, 315-317, 332-340`)이 전부 no-op ★. **같은 in-memory 집합이 반대 방향 위험도 만든다 ★** — 프로세스 재시작 후에는 이미 claim된 봉투가 다시 claim되어 루틴이 두 번 뜰 수 있다(크래시 복구를 위한 의도된 설계일 수 있으나 결정이 필요). 또 링 화면은 **사용자가 알람을 끄기 전에** occurrence를 complete 처리해(`AppRouter.swift:720-723`) 그 순간 앱이 죽으면 30분(`OpenMoruRoutineIntent.swift:33`) 동안 같은 알람이 다시 뜨지 않는다 ★. **노력: S(순서 교정) — AlarmKit 직접 진입 계약 접촉**

**C8. ⚠️ AlarmRing에 알람을 끄는 수단이 없다.** 액션은 슬라이드 시작(임계 82%, `SlideToStartControl.swift:35`)과 다시 알림뿐. 탭 폴백은 VoiceOver 전용(`:95-100`). 시각은 `"HH:mm"` 하드코딩(총 5곳 ★: `AlarmRingView.swift:181,188` / `TodayRoutineRecordView.swift:514,525` / `HomeView.swift:598`)으로 12시간제 설정을 무시 — History는 `Date.FormatStyle`을 쓰므로 앱 안에서 표기가 갈린다. 본문은 `.dynamicTypeSize(.xSmall ... .accessibility1)`로 AX2 이상이 AX1에 고정된다(`:71`, 단 `:115`에 `minimumScaleFactor(0.7)` 완충 있음). **노력: S~M**

**C9. 부트스트랩 실패 시 알람을 끌 방법이 앱 안에 없다.** `AppBootstrapper.swift:462-471`이 모든 예외를 한 문구로 붕괴시키고 `retry()`(`:148`)는 백오프 없이 재시도. `MoruApp.swift:87`의 `.failed` 분기엔 `.onOpenURL`도 alarm 훅도 없다 — `.idle`/`.loading` 스플래시 구간(`:51-64`)도 마찬가지라 OAuth 콜백도 유실된다 ★. **노력: M**

**C10. ⚠️ 알람 콜드 스타트가 첫 프레임 전 동기 작업에 묶여 있다.** `AppBootstrapper.swift:167-472`의 `constructReadyGraph()`가 전부 동기 MainActor이고, `:501`의 `await preflight.prepare(...)` **다음 줄**에서야 `state = .ready(app)`가 실행되며, 알람 ingress 소비는 `sessionStore.phase == .ready`를 요구한다(`AppRouter.swift:690`). 즉 알람이 울려 콜드 런치될 때 사용자는 그 동안 스플래시를 본다. 단 초판이 든 근거 두 개는 조건부다 — `prepareInstallationState`(`:258`)의 SwiftData 읽기는 설치 후 첫 실행에만, `alarmScheduleMutator.apply(.synchronize)`(`:96`)는 취소 대상이 있을 때만 실행된다. **매 콜드 스타트마다 확실히 도는 동기 작업은 `:321 sessionStore.load()`와 `:338 serverRoutineRestorer?.localDataState()`다 ★.** **노력: M — preflight를 `.ready` 이후로 미룰지는 §9 결정**

**C11. 완료 요약이 도달하지 못한 단계를 통째로 숨겨 다이얼로그의 약속과 History가 어긋난다.** `EndRoutineDialogView.swift:23-28`은 "나머지는 미완료로 기록됩니다"라고 약속하지만 `stepResults`에는 완료·건너뜀만 들어간다(`RoutinePlayerViewModel.swift:347, 395`). 5단계 루틴을 1단계에서 종료하면 요약에 1개만 보이는데 완수율은 20%로 표시된다(분모는 `routine.steps.count`, `RoutineExecutionContract.swift:112-140`). History는 `run.plannedSteps` 스냅샷 기준이라 미완료 4개를 정상 표시한다(`LoadHistoryUseCase.swift:155-188`) — 같은 실행이 화면에 따라 항목 수가 다르다. (`RoutineFinishedView.swift:75-77`의 필터는 추가 손실을 만들지 않는 no-op이므로 원인이 아니다.) **노력: S~M — Q3와 함께 결정**

## 3.4 History·Profile (우선순위 낮음 — 확정된 high만 기록)

- **⚠️ 알람 앱인데 Profile에 알람 표면이 0개다.** `ProfileViewModel`은 `alarmStatus`와 권한 요청/재예약/설정 열기를 모두 구현했고(`ProfileViewModel.swift:32,156-182`) `ProfileView.swift:217-225`가 scenePhase마다 `refreshAlarmStatus()`를 부르는데, 그 값을 읽는 뷰가 0개다. `AppRouter.swift:584-590`의 `onOpenSettings` 배선까지 있으나 호출부가 없다. **뷰만 붙이면 되는 가장 싼 알람 표면.**
- **Profile에 도달 불가 UI 약 783~819줄.** `isDisplayNameEditorPresented`를 true로 만드는 코드 0(`ProfileView.swift:63,226,853,859`), `presentArchive()` 프로덕션 호출 0 → `AccountRoutineGroupArchiveView.swift` 593줄 전체, `AccountServerSettingsView.swift:8-198`(190줄) 참조 0. 초판 매핑의 "793줄"은 근사치다.
- **월간 히트맵 요일 헤더가 격자와 하루 어긋난다.** `LoadHistoryUseCase.swift:289-290`은 월요일 시작 격자인데 `HistoryComponents.swift:674-677` 헤더는 일요일 시작이다(같은 화면의 주간 스트립 `HistoryView.swift:503-511`도 월요일 시작). `.noData`와 `.zero`가 같은 색(`:780-783`)이고, **아직 오지 않은 날까지 '기록 없음'으로 칠해진다 ★**(`LoadHistoryUseCase.swift:312-321`이 이번 달 전체를 생성, VoiceOver 라벨도 동일).
- 하루치 기록 화면이 4개(`TodayRoutineRecordView` 702줄 / `HistoryDailyDetailView` / `HistoryRunDetailView` / `HistoryAccountDailyDetailView`)이고, 702줄짜리는 트라이얼 경로에서만 도달한다(`RoutinePlayerView.swift:490-497`). 기록 탭 리셋의 주원인은 `.id(historyReloadToken)`가 아니라 `MainTabView.swift:95-106`의 if/else다 — `.id` 제거만으로는 증상이 사라지지 않는다.
- 서버 보강 실패가 "기록 없음"을 "불러오지 못함"으로 둔갑시킨다(`HistoryViewModel.swift:64-71`) — 로컬 우선 철학과 반대.

---

# 4. 아키텍처·상태·동시성 문제 (심각도 순, 12개)

| # | 문제 | 증거 | 왜 중요한가 | 노력 | §3과의 관계 |
|---|---|---|---|---|---|
| 1 | **CI가 빌드도 테스트도 안 함** — 1,027개 테스트가 자동 실행 0회 | 워크플로 전부 `ubuntu-latest`, `xcodebuild` 0건; `4192956`·`810a193`이 머지 후 stale 테스트 수습 | 모든 리스크 있는 리팩터링의 선행 조건. 11단계 수동 게이트가 리팩터링을 멈춘 유력 원인 | M | §3 전체를 unblock |
| 2 | **AppRouter 832줄 God View** — 조립 + 탭 조립 + alarm ingress + 씬 팬아웃 + Platform 싱글턴 configure | `:151-189`, `:253-340`(훅 6개), `:680-815`, `:256`; 계획 문서가 변경빈도 1위(50/18)로 지목 | AlarmKit 직행 규칙(`launchTarget == .scheduledRoutine`)이 저장소 전체에서 View 한 줄(`:719`)에만 존재 ★. 알람 로직 수정=View 수정 | L | C7·C9·C10 |
| 3 | **AVAudioSession을 4개 타입이 중재 없이 조작** | `RoutineAudioSessionCoordinator:292-313`, `LocalFileRoutineAudioPlayer:350-387`, `BundledRoutineGuidancePlayer:136-158`, `SystemRoutineSpeechAnnouncer:90-95`; `stopCurrentCue`가 스텝마다 **무조건** deactivate 2회 | 스텝 전환마다 세션 왕복 → 첫 음절 잘림·무음. 인스턴스 2개(`DependencyContainer:241`, `ServerVoicePreviewPlayer:50`)가 같은 전역 세션을 만짐. `LocalFileRoutineAudioPlayer`는 재진입 안전하지 않아 호출자 순서에만 의존(`:307-324`) | L | C2·C4·C5 |
| 4 | **핵심 도메인 정책이 Data 리포지토리 안에 산다** | `SwiftDataRoutineRepository.swift:245`(165줄 intent 파생), `:434`(서버 atomicSingleActive 지식), `SwiftDataRoutineSyncRepository.swift:1029,1077,1133` | 정책 검증에 항상 ModelContext 필요. 단, `:140/:143`의 단일 트랜잭션 요구가 정당화 근거. **같은 불변식이 `RoutineSettingUseCase.swift:78-96`과 `SwiftDataRoutineRepository.swift:646-660`에 이중 구현 ★** — 갈라지면 UI는 통과시키는데 저장이 throw | L | B6 |
| 5 | **의존 방향이 양쪽으로 뒤집혀 있다** | (a) Data/Domain → App: `TokenRefreshCoordinator.swift:31`, `OnboardingStatusRuntimeCoordinator.swift:108`이 `AccountSessionStore`(ObservableObject) 보유, 후자는 `:165`에서 `$state` Combine 구독 ★ (b) **Domain → Network ★**: `AccountAuthorizationContext`/`AccountSessionIdentity`가 `Network/Core/AuthenticationRequirement.swift:17,26`에 선언되고 Domain 12파일·Data 4파일이 참조 (c) **전송 아티팩트가 Domain에 ★**: `RoutineSyncModels.swift:430-442`의 HTTP 메서드 enum + `RoutineSyncWireRequest` | 401 재발급 단위 테스트에 SwiftUI 객체가 필요하고, "누가 로그인했나"라는 도메인 개념이 전송 계층에 산다 | M | — |
| 6 | **관찰 모델 이원화 + 수동 objectWillChange** | `OnboardingViewModel.swift:35` + willSet 8개 → `draft` 한 글자 변경이 18개 `@ObservedObject` 뷰를 무효화 | 온보딩 입력 지연 = 첫 인상. `@Observable` 전환은 A1~A7 작업의 선행 | M | §3.1 전체 |
| 7 | **stale 폐기 프리미티브가 "없다"가 아니라 "Features가 모른다"** — 18개 파일 5가지 관용구 ★ | `HomeViewModel:618`, `HistoryViewModel:42,58,65,73`, `AccountRoutineGroupViewModels:40,153-154` vs 이미 존재하는 in-flight 딕셔너리 3벌 | 새 화면마다 판단 필요, 한 곳 누락 시 "이전 계정 데이터 잔상". 신규 작성이 아니라 기존 구현 승격이 정답 | M | B2·B4 |
| 8 | **mainTabView가 계산 프로퍼티** — body 평가마다 UseCase·빌더 6종 + 4개 탭 전부 생성 | `AppRouter.swift:526-605`; `HomeFlowBuilder.swift:65-66` 때문에 `RoutineSettingView`가 1회당 **3개** 생성 ★ | 아침 첫 진입 낭비. 홈/플레이어 VM도 매번 생성 후 폐기 ★(`RoutinePlayerBuilder`는 VM+GuidanceCoordinator+SpeechInputController 한 벌) | M | B1·B4 |
| 9 | **커스텀 탭 if/else가 비선택 탭 상태를 파괴** | `MainTabView.swift:83-93, 97-105`; ProfileView는 navigationDestination 3단계(`:148,161,173`) | 네이티브 TabView 전환의 전제. `ProfileFlowBuilder.swift:76-100`만 계정 `.id` 누락 ★ | M | §5 전체 |
| 10 | **RoutineTTSWarmupCoordinator(1,975줄)가 Domain인 척하는 Platform 오케스트레이터** | `:320,769,1000,1512,1539`가 `RoutineTTSBackgroundLifecycleBridge.shared` 직접 호출, `:188`이 Platform 프로토콜 채택 | "30초 대기 후 무음" 규칙이 파일시스템·백그라운드 전송과 한 덩어리 | L | C4 |
| 11 | **Task 149개 중 소유 22개** — 온보딩 저장 Task 3개는 화면 이탈 후에도 콜백 실행 | `OnboardingViewModel.swift:494,499,540` vs `:527` viewDidDisappear가 3개만 취소 | 사라진 화면 기준 내비게이션. (중복 탭 방어 자체는 `:908`·`:944` 사이에 await가 없어 구조적으로 성립 ★) | S | A1·A7 |
| 12 | **DI 경계가 타입으로도 테스트로도 안 지켜진다** | `DependencyContainer.swift:11-41` 28개 중 구상 Platform 8개, Optional 19개; 경계 테스트는 5개만 assert(`FoundationSwiftDataTests.swift:579`); `ProfileView.swift:53`이 `ServerVoicePreviewPlayer` 직접 보유; **`RoutinePlayerBuilder.swift:31-32`·`RoutineGuidanceCoordinator.swift:22`도 구상 Platform 타입 보유 ★** | README:428 위반. `AppRouter.swift:553`처럼 배선 누락이 "기능 없음"으로 조용히 강등 | S~M | C2·C5 |

**그 밖에 확인된 것(단독 항목으로 세우진 않았으나 계획에 넣을 것):** `RoutineSyncRepositories.swift:9-205`가 34메서드 god interface(소비처는 이미 4개 부분집합) ★ · Features가 `LoginResponseDTO`/`APIError`를 직접 다루고(4파일 2폴더) `AppleLoginReadiness.swift:67`이 `kSecRandomDefault`를 화면 폴더에서 호출 ★ · `HomeWeatherService.swift:8,47,64,512`가 Domain 유일의 CoreLocation/WeatherKit/UIKit 의존 · 동형 원격 에러 enum 5개 + `catch APIError.cancelled` 10곳 · 루틴 표현 6종 + 매핑 3레이어 · 영속화가 Data/Local·Data/Secure·Platform/TTS 3곳 분산 · `RoutineGuidanceCoordinator`의 `reminderTask`는 대입 0회의 죽은 상태(4줄 삭제) · `SpeechInputController`/`AppleSpeechRecognitionSession` 기본 인자가 `NoopRoutineGuidancePlayer`로 이어져 잘못 배선하면 STT 전 안내 정지가 조용히 no-op(`RoutinePlayerBuilder.swift:125-128`만 올바름) · `Platform/Alarm/AlarmKitDebugView.swift`가 Platform에 있는 SwiftUI View ★.

---

# 5. 디자인 시스템 현황과 Liquid Glass 전환 영향

**전환 전에 반드시 정리해야 하는 것**

1. **토큰 이중화 해소가 1순위.** `MoruPilot*`이 Features에서 764회로 사실상 주 시스템인데 문서(`FigmaPilotFoundation.md:10`)와 컴포넌트 기본값(`MoruButton.swift:28 = .legacy`)은 파일럿이라 말한다. 이름 충돌이 실재한다 — `textStrong`이 #1C1C36 vs #3C3D5E, `textPrimary`가 #3C3D5E vs #515574. Glass는 재질 위 텍스트 대비가 더 민감하므로, 어느 값이 정본인지 **먼저 확정하지 않으면 유리 위 카피가 화면마다 다른 명도로 앉는다.**
2. **`MoruButton` legacy 4개 호출부가 지금도 출하 중** ★. `.figmaPilot`를 넘기는 곳은 7곳뿐이고 `HomeView.swift:766,791,809`·`SplashScreenView.swift:37`은 기본값 legacy다. 같은 문구 "새 루틴 만들기"가 홈(legacy: `pretendardSemiBold(16)`·verticalPadding 16·minHeight 없음)과 루틴 목록(`RoutineSettingView.swift:159-162`, figmaPilot: `moruTextStyle(.b4.semiBold)`·minHeight 54)에서 다르게 그려진다. **이 4곳만 바꾸면 `MoruPilotComponentStyle` enum과 모든 분기를 안전하게 삭제할 수 있다.**
3. **하드코딩 캡슐 CTA 6벌 → glass button style로 교체.** 높이 48/52/54, 가로 여백 20/22가 섞여 있다: `RoutinePlayerView.swift:119,148,556`, `SnoozeSheetView.swift:74,79,97`, `TodayRoutineRecordView.swift:405,410`, `RoutineFinishedView.swift:364`. 동시에 **공용 컴포넌트가 393pt 고정폭** ★ — `MoruButton.swift:109-118`(349/353, **componentStyle 분기 자체가 없어 figmaPilot도 고정폭**), `MoruSelectionCard.swift:53,67`, `MoruProgressBar.swift:18`(352), `MoruDialog.swift:55,148`(320). 사설 CTA는 전부 `maxWidth: .infinity`라 **공용 컴포넌트를 쓸수록 덜 반응형이 되는 역전**이 일어난다.
4. **커스텀 탭바 → 네이티브 TabView.** `MainTabView.swift:83-93`이 `safeAreaInset`에 `MoruTabBar`를 붙이고 `:97-105` if/else로 화면을 고른다. `MoruTabBar.swift:106`은 그림자 색을 raw RGB로 박고 있다. 네이티브 전환 시 (a) 탭별 상태 보존이 자동으로 생기고(§4-9 해소), (b) `app.tab.*` a11y 식별자(`MoruTabBar.swift:46-50`)를 유지해야 UI 테스트·`FinalScreenVisualTests.swift:145`의 식별자 계약이 깨지지 않는다. **참고: "매일 아침 초기 상태"는 기록 탭에만 의도적으로 구현돼 있고(`MainTabView.swift:36-40, 102`), 나머지 탭의 리셋은 if/else의 부작용이다.**
5. **헤더/뒤로가기 4종 → 네이티브 toolbar.** `HistoryView.swift:888-893`(텍스트 "뒤로", 대비 2.64:1, 44pt), `OnboardingFlowView.swift:179-180`(chevron.left 24pt), `TodayRoutineRecordView.swift:98`(프레임 없음), `RoutinePlayerView.swift:421-424`("닫기", 56×40). trailing chevron도 `MoruChevron` 11회 ★ + raw 3종.
6. **Profile 서브트리만 시스템 크롬 — glass와 가장 잘 맞는 동시에 가장 어긋난 곳.** `ProfileView.swift:147`이 네비바를 숨기고 커스텀 헤더를 그리는데 하위 화면(`:848,878,1278`, `AccountRoutineGroupArchiveView.swift:25,252`, `AccountServerSettingsView.swift:253`, `GeminiDataConsentView.swift:91` — 합계 7곳)은 다시 켠다. `:1075-1076`은 `.borderedProminent` + `.tint(AppColor.moruBlue)`(#417DFF) — **파란 tint는 이 한 곳뿐** ★이며 `GeminiDataConsentView.swift:75`는 이미 `.tint(MoruPilotColor.accent)`라 형태만 시스템 버튼이다.
7. **`MoruDialog` → 네이티브 alert/sheet 여부 결정 필요.** 현재 스크림이 두 종류(Features 0.22 탭 무반응 / RoutineFlow 0.35 탭 취소), `adaptsForAccessibility` 기본값 false, **폭 320 고정은 두 경로 모두**. 네이티브 alert로 가면 destructive role·Dynamic Type·glass 배경이 공짜로 따라오지만, 6곳의 카피·강조 위계가 바뀐다.
8. **대비 결정이 선행되어야 한다.** Glass는 배경이 비쳐 실효 대비가 더 낮아진다. 지금도 CTA 2.12:1, 비활성 카드 설명 1.45:1, **요일 미선택 1.70:1**(`RoutineWeekdaySelector.swift:50,59`) ★ 이다. orange500로 올려도 3.09:1이므로 orange550(#E84000) 또는 글자색 변경 중 선택이 필요하다.
9. **Light 고정 vs Glass의 양방향 적응.** `MoruApp.swift:97`이 루트에서 light 고정, colorset 57개 dark variant 0, `check-iphone-functional-gate.sh:58`이 이 줄을 CI로 강제한다 — **즉 다크를 열려면 CI 계약 문구부터 바꿔야 한다.** 남은 작업: colorset 57개, raw RGB 11곳, `Color.white/black` 9곳, `grayWhite.opacity(0.2)` 계열 표면 4종. 도달 불가 다크 분기(`HomeView.swift:481,496`)는 지금 삭제.
10. **중복 구현·규격 정리.** `RoutineSettingCard`(251줄)가 `MoruRoutineCard`(247줄)의 준-복제(단 shadowRadius는 `figmaPilot ? 7.5 : 10` vs `isActive && !isAddCard ? 0 : 7.5` ★, `MoruRoutineCard`는 isAddCard 모드를 따로 가짐), `ProfileSkeletonBlock`≡`HistorySkeletonBlock`, 요일 선택 3벌(40/40/42, 온보딩판은 `fixedSize: 18`로 Dynamic Type 무시), Weekday 도메인 API마저 온보딩에 복제 ★(`OnboardingDraft.swift:110-137` vs `Weekday.swift:24-45`). `RoutinePlayerView.swift:451-478`의 인라인 진행바는 `MoruProgressBar`의 "복제"는 아니고 폭 제약·라벨 폰트가 다른 별개 구현이다.
11. **거터·radius 토큰 오용 ★.** 화면 거터 8종(위 §1 표)에 더해 `cornerRadius: MoruPilotSpacing.sixteen` 9회 / `.twelve` 8회처럼 spacing 토큰을 radius로 쓴다(`ProfileView.swift:362`, `HistoryComponents.swift:539`, `AccountEntryView.swift:380`). `AppRadius`는 sm/md가 둘 다 16, lg/xl이 둘 다 24로 이름이 중복(`AppLayout.swift:38`). 스페이싱 스케일을 조정하면 카드 모서리가 같이 변한다 — glass 컨테이너 규격을 잡기 전에 분리해야 한다.
12. **터치 타깃·모션 ★.** `MoruToggle` 52×28(`:29`), `MoruSelectControl`→`MoruSelectIcon` 24×24인데 **같은 삭제 액션이 편집기에서는 44×44**(`RoutineStepDraftRow.swift:45`), `TodayRoutineRecordView.swift:280` 복사 버튼 20×20, `:98` "뒤로"는 프레임 없음. (`MoruChip`은 Button이 아니라 표시 전용이므로 타깃 목록에서 제외.) 모션 토큰은 0이고 호출부 14곳에 duration·spring이 제각각이며 `RoutineFinishedView.swift:110`의 완료 축하 애니메이션에 reduceMotion 가드가 없다.
13. **문서화된 컴포넌트 표가 실물과 어긋난다 ★.** `CommonComponentsMap.md:35-53`은 19개만 싣고 있고 프로덕션 사용 공동 2위인 `MoruSocialLoginIconButton`(6회)과 `MoruVoiceSegmentedControl`이 표에 없다. 반대로 표가 "루틴 목록 카드"라 설명한 `MoruRoutineCard`의 유일한 프로덕션 용도는 `RoutineSettingView.swift:261-264`의 "+ 새 루틴 추가" 행이다. 문자열은 Copy enum 96개 vs 뷰 인라인 한글 97개로 반반이고 `.strings`/`.xcstrings`는 0개.

**무효화되는 비주얼 베이스라인**

- `FinalScreenVisualTests.swift:487-503` dHash 20개(임계 Hamming 24) — 색·간격 변화는 원리상 못 잡지만 glass 재질은 잡힌다.
- `RoutineManagementFigmaVisualTests.swift:465`, `RoutinePlayerFigmaVisualTests.swift:150-152`(24를 인라인 매직넘버로 보유 ★) — **visualHash 구현이 3벌** ★이라 임계값 조정 시 3곳.
- 커밋된 기준 PNG 24장(`figma-pilot-review-bundle/P4-routine-player-completion/states/*/after.png`, `RoutinePlayerFigmaVisualTests.swift:130-143`)은 전량 재캡처 대상. 같은 디렉터리의 완료 화면 10장은 **어떤 테스트에도 연결돼 있지 않다** ★(`RoutineFinishedFigmaVisualTests.swift:39-41`은 size/scale/pngData 3개 assert뿐).
- `FigmaPilotFoundationTests.swift:15-34`(hex 12종) + `:183-188`(픽셀 RGBA 동일성) — 토큰 통합 시 필연적으로 실패.
- `HomeProfileFigmaVisualTests.swift:882`의 `profile-permission-off` 베이스라인은 ProfileView가 `alarmStatus`를 읽지 않아 regular와 시각적으로 동일 ★ — 알람 섹션 추가 시 먼저 정리해야 한다.
- 카피 잠금 26개(3개 파일 ★)와 `FinalScreenVisualTests.swift:396-400`의 게이트 우회로(8장이 "PNG > 1KB"만 검사) ★ 도 함께 손봐야 한다.

---

# 6. 테스트·도구·프로세스

1. **CI 테스트 0개** — 가장 큰 프로세스 결함이자 다른 모든 작업의 선행 조건.
2. **선행 조건이 scheme만이 아니다** ★ — 시각 테스트가 `UIApplication.shared.connectedScenes`를 강제 언랩(`FinalScreenVisualTests.swift:372-374`, `MoruVisualCaptureFixture.swift:83-85`)하고 출력이 `/private/tmp` 고정 경로(`:393`)라 병렬 실행 시 서로 덮어쓴다.
3. **`*.pbxproj binary merge=union`** — `git show`가 "Binary files differ"만 출력해 서명·번들 ID·OAuth 키 변경이 리뷰에서 안 보이고, 이미 중복 키를 만들었다(`project.pbxproj:424`와 `:429`에 `CURRENT_PROJECT_VERSION` 2회, 424는 알파벳 순서 파괴). `:39,167`의 `F1000000000000000000000X` 수기 UUID는 pbxproj가 손·에이전트로 편집되고 있다는 별도 정황 ★.
4. **`check-social-login-release-config.sh`(121줄)가 어떤 워크플로에도 연결되지 않음** — 하필 그 검증 대상이 diff가 안 보이는 pbxproj다.
5. **Task.sleep 21곳/11파일** — `RemoteFirstRoutineGuidancePlayerTests.swift:729`처럼 20ms 안에 아무 일도 안 일어난다는 시간 가정. CI를 붙이는 순간 첫 빨간불. XCTestExpectation 대기는 리포 전체 1곳, XCTSkip 0.
6. **'Figma 시각 테스트'는 대체로 결정성 검증** — 다만 RoutinePlayer/RoutineManagement/FinalScreen 3개는 실제 골든 비교를 하고 ★, `FigmaPilotFoundationTests`는 hex와 픽셀 RGBA까지 고정하므로 "색 토큰이 바뀌어도 전부 초록"은 사실이 아니다. `figma-visual-compare.swift`는 테스트·CI 어디서도 호출되지 않는다.
7. **다크 스냅샷이 라이트 베이스라인에 매핑** ★ — `FinalScreenVisualTests.swift:409`가 파일명의 `-dark-`를 `-light-`로 치환. Figma 계열 fixture는 다크를 아예 렌더하지 않는다(`MoruVisualCaptureFixture.swift:15-17`).
8. **알람 진입 UI에 XCUITest 0개** — UI 테스트 3개는 날씨 2 + 소셜 1이고, 좌표 4회 드래그(`MoruReviewWeatherUITests.swift:141-147, 194-206`)·30초 대기(`:101`)·외부 앱 전환(`:88-92`)에 의존. `AlarmRingView`는 `FinalScreenVisualTests:72`의 dHash 스냅샷 한 장뿐이고 `SnoozeSheetView`·`SlideToStartControl`은 스냅샷조차 없다. **다만 "플레이어 경로가 무방비"는 사실이 아니다** — `RoutinePlayerFigmaVisualTests.swift:210-266`이 12개 상태(다이얼로그 포함)를 골든으로 덮고 있고, `RouterRuntimeContractTests.swift:692-1213`이 저장 실패 재시도·다이얼로그 보류·조기 종료 저장 등 ViewModel 상태 전이를 20개 가까이 고정한다. 진짜 공백은 (a) 캡처 안 된 5개 상태(preparingServerVoice / 마이크 권한 거부 / 무발화 리마인더 / 저장 실패 배너 / summary), (b) "저장 실패 시 종료가 막힌다"는 사실 자체를 못 박은 테스트, (c) `VoiceInputControlView` 수준의 UI 배선이다.
9. **워크플로 트리거 불일치** ★ — `feat/**` 푸시에서는 `check-folder-convention.sh`가 아예 안 돈다. 같은 `check-swiftdata-boundary.sh`는 두 워크플로에서 중복 실행된다.
10. **리포 937MB / PNG 941장 854MB / LFS 없음 ★** — 그중 34장은 이미 살아 있는 baseline이다. "기준 PNG를 커밋할 것인가"는 이미 지나간 질문이고, 진짜 질문은 "이 1GB를 어떻게 할 것인가"다.
11. **앱 6.0 vs 테스트 6.2**(README는 6.2 표방), 공유 xcconfig 없음, `MARKETING_VERSION`이 6개 블록에 하드코딩.

**안전한 리팩터링의 전제 조건: (1) shared scheme + xctestplan 2종, (2) macOS 러너 xcodebuild test, (3) 시각 테스트의 씬 의존·출력 경로 주입화.** pbxproj `binary` 해제는 CI의 *기술적* 전제는 아니지만(scheme 공유는 `xcshareddata/`에 파일을 추가하는 작업이다) 설정 회귀를 리뷰에서 보려면 같은 시점에 처리하는 게 합리적이다.

---

# 7. 문서 대비 실제

| 문서·항목 | 상태 | 근거 |
|---|---|---|
| **2026-07-03 리뷰** 2.1 VersionedSchema + MigrationPlan | DONE | `MoruSchema.swift:11-99,101,113-121,151` |
| 2.1 PR 체크리스트에 schema 항목 추가 | **NOT DONE** | `.github/pull_request_template.md`에 항목 없음 |
| 2.2 `@Relationship` cascade + Run 스냅샷 | DONE | `PersistedModels.swift:16,17,125,126,129,130` |
| 2.3 `parseRoutine` 분리 / 2.4 TTSRepository 제거 / 2.5 release mock 차단 / 2.6 completionRate 저장 제거 | DONE | grep 0건, `DependencyContainer.swift:415-431` `#if DEBUG`, `RoutineExecutionContract.swift:131-140` |
| 4-1 ContentView DeviceQA 분리 | SUPERSEDED(삭제) | `ContentView.swift` 38줄, DeviceQA grep 0 |
| 4-2 Spike 제거 / 4-3 UseCase 실규칙 / 4-5 Auth 격리 | DONE | UseCase 411/405/339/333줄 |
| 4-4 문서 간 링크 정리 | **NOT DONE** | `local-first-server-optional-strategy.md:18,198`, `local-first-migration-plan.md:11,116`이 없는 파일을 개인 절대 경로로 링크 |
| **2026-08-22 계획** `OnboardingFlowView` 분리 | NOT DONE | 1,835→1,799(기능 삭제분, `1479abb`), 제안 9개 파일 0건 |
| `HistoryView` 분리 | NOT DONE + **문서가 거짓** | 계획서 `:283-287`이 `HistoryPresentationViews.swift` 분리 "완료"라 기록하나 워킹트리·git 전체 히스토리 0건 |
| `HomeView` / `ProfileView` 분리 | NOT DONE | 875·1,427줄 그대로, 08-22 이후 커밋 0건 |
| `HomeViewModel` / `OnboardingViewModel` 정책 분리 | NOT DONE | 정책 타입 grep 0건, 후자는 +11줄 |
| `AppRouter` 분리 | NOT DONE | 825→832 |
| `RoutinePlayer` View/VM 분리 | NOT DONE | 709/819 그대로 |
| `SwiftDataRoutineSyncRepository` / `RoutineTTSWarmupCoordinator` | NOT DONE(역행) | +48 / +45줄, 각각 커밋 4·6건(전부 버그 픽스) |
| ⚠️ **계획서 번호 체계가 내부 충돌** ★ | — | 우선순위 표(`:16-26`)는 2=History·3=Home·4=Profile인데 실제 섹션은 §2 ProfileView(`:224`)·§3 HistoryView(`:281`)·§4 HomeView(`:347`)이고, 인벤토리 표(`:41`,`:46`)는 ProfileView와 HomeView를 둘 다 "계획 4"로 라벨링한다. **그래서 이 표는 번호가 아니라 파일명으로 적었다.** |
| 계획 대신 실제 수행된 작업 | folder-restructure phase1~7 (PR #203) | 계획서 경로 `:644`, `:709`가 그 결과로 무효화됨 |
| `V2NetworkFoundation.md:325-331,343,365-366` "sender에 연결하지 않습니다" | **코드와 모순** | `ProductionRoutineSyncRequestPreparer.swift:114,186,230,260,280,310,330,362`(7경로), `AppBootstrapper.swift:275,283`, `RoutineSyncModels.swift:190-193` `isE2EVerified: true` (단 sender 조립은 `AppBootstrapper.swift:269`의 `shouldAllowServerRequests` 아래) |
| `RoutineSyncFoundation.md:219-226` "남음" 4개 | 2 DONE / 1 미구현(reconciliation) / 1 대체됨 | `deactivateRoutineGroup`(`RoutineSyncModels.swift:246`)은 문서에 전무 |
| `ServerRoutineSyncContractRequest.md:14,176-177` P0 게이트 ★ | 자기 기준 미충족 상태로 sender 켜짐 | `RoutineSyncModels.swift:156-170` 주석이 lookup/upsert 부재를 명시 |
| `CommonTTSAndOnboardingCompletionImplementationPlan.md`(561줄) ★ | 구현 완료됐는데 완료 표시 0, `:553-559`가 "1단계부터 구현하라"고 지시 | 구현 커밋 `cf774a1`과 문서 최종 커밋 동일 |

**Stale 문서 목록:** `README.md:1,3,18,42-43,110,127,370`(템플릿 잔재·표 렌더 깨짐·Kingfisher 배지·스키마 V1~V3), `V2NetworkFoundation.md`, `RoutineSyncFoundation.md`, `ServerRoutineSyncContractRequest.md`, `CommonTTSAndOnboardingCompletionImplementationPlan.md`, `mydocs/moru-ios-v1-master-plan.md:61-99`, 로그인 readiness 4종(2026-07-28 이후 미갱신, 그 사이 `1bc189d`가 로그인 직후 동의 화면을 추가) ★, `refactoring-plan-2026-08-22.md`(번호 충돌 ★ + 거짓 진행 기록), `CommonComponentsMap.md:35-53`(컴포넌트 표 불일치 ★).

---

# 8. 의존 관계 (무엇이 무엇을 막는가)

**0층 — 안전망.** CI(macOS 러너 + shared scheme + xctestplan)가 없으면 §4의 어떤 항목도 "안전하게" 할 수 없다. 시각 테스트의 씬 의존·`/private/tmp` 고정 경로는 CI 첫 실행에서 바로 걸리므로 함께 처리한다. pbxproj `binary` 해제는 CI의 기술적 전제는 아니지만 설정 회귀를 리뷰에 노출시키려면 같이 하는 게 낫다. **그리고 `mydocs/` 3,679줄(`.git/info/exclude:9`)과 `VoiceCoachingUXHandoff.md` 821줄(단순 미추적)은 지금 이 맥북에만 존재한다 — 이 브리프의 근거 문서 자체가 디스크 사고 한 번에 사라진다. 다만 "리포에 커밋한다"는 것은 사실이 아니라 결정이므로 §9 Q15로 뺀다.**

**1층 — 토큰 통일 → Liquid Glass.** `MoruButton` legacy 4곳 → `.figmaPilot` → `MoruPilotComponentStyle` 삭제 → 이름 충돌(`textStrong`) 확정 → 고정폭(349/353/352/320) 해제 → 거터/radius 토큰 분리. 이걸 하기 전에 glass를 얹으면 두 시맨틱 레이어 위에 유리를 깔아 **명도가 화면마다 다른 유리**가 나오고, 베이스라인을 두 번 재캡처하게 된다. 대비 결정(orange350 유지 여부)도 유리 위에서 더 악화되므로 여기서 함께.

**2층 — 네비게이션 소유권 → 네이티브 TabView.** 지금 상태는 coordinator(모달) / `AppRouterState`(탭·히스토리) / 각 View `@State` 3분할이고, `mainTabView`가 계산 프로퍼티라 body 평가마다 4탭 + 루틴설정 3개를 만든다. 소유권과 생성 시점을 정리하지 않고 TabView로 갈아타면 "탭 상태가 보존되는" 새 동작이 오히려 낡은 VM 인스턴스를 붙잡는다(`ProfileFlowBuilder`의 `.id` 누락 ★이 여기서 터진다).

**3층 — 관찰 모델 통일 → 온보딩 VM 분리.** `OnboardingViewModel`이 `ObservableObject` + 수동 발행인 한, VM을 쪼개도 무효화 범위는 그대로다. `@Observable` 전환이 §3.1 작업(A1·A4·A6·A7)의 전제. 루트 플래그 4개(A10) 승격도 같은 묶음에서 처리하는 게 싸다.

**4층 — 오디오 세션 일원화 → 코칭 확장.** mid/wrap 큐(핸드오프 A안)를 얹으려면 (a) 타이머 시작 시점이 intro 종료로 정의돼야 하고(C5), (b) 카운트다운 시스템 음성이 진행 중 큐를 죽이지 않아야 하며 ★, (c) 세션 왕복이 줄어야 한다. 셋 다 §4-3의 하위 작업이고, `RoutinePlayerBuilder`가 구상 Platform 타입을 보유하는 문제(§4-12)와 같은 파일군을 건드린다.

**5층 — 계약 문서 정정 → 서버 협의.** `V2NetworkFoundation.md`·`RoutineSyncFoundation.md`·`ServerRoutineSyncContractRequest.md`가 코드와 모순인 채로 핸드오프 12.7의 5개 서버 협의를 시작하면, 서버 팀이 "지금 연결하면 안 되는 것" 목록을 잘못 읽는다.

**독립 트랙(언제든 가능):** 카피/데드코드 정직화(A1·A3·B3), 다이얼로그 강조 반전(B8), AlarmKit stop 순서 교정(C7), Profile 알람 섹션 부착(§3.4 — ViewModel이 이미 완성돼 뷰만 붙이면 됨). 앞의 셋은 계약 접촉이거나 실기기 검증이 필요하다.

---

# 9. 사용자에게 물어야 할 질문

### 제품 정책

**Q1. 마이크 권한 거부/기기 미지원 시 수동 "완료" 버튼을 허용할 것인가?** *(지금은 확인형·입력형 완수율이 강제로 0%)*
(a) 항상 큰 완료 버튼 노출 (b) 영구 실패(`transcriberUnavailable`)에만 노출 (c) 현행 유지+건너뛰기 문구 강화. → (a)는 음성 우선 정체성을 희석, (b)는 코드 분기 1개 추가로 최악만 방어, (c)는 완주 불가를 수용.

**Q2. 저장 실패 시 사용자를 붙잡을 것인가, 내보낼 것인가?** *(현재 탈출구가 강제 종료뿐)*
(a) 배너에 "기록 없이 나가기" 추가 (b) `canRequestExit` 게이트를 분리해 종료 의도는 항상 통과 (c) 현행 유지+재시도 자동화. → (b)를 고르면 §2-7의 단일 게이트 강점을 보존하면서 감옥만 없앨 수 있다.

**Q3. 루틴 시작 직후(첫 단계 완료 전) 이탈을 0% 실행 기록으로 남길 것인가?** *(오탭 한 번이 스트릭을 끊는다)*
(a) 유예 구간 도입 (b) 현행 유지 (c) "닫기"만 유예, "종료"는 기록. **함께 결정:** 완료 요약을 전체 단계 기준으로 그려 C11의 "요약 1개 vs 완수율 20%" 불일치를 없앨 것인가?

**Q4. 타이머 단계에 조기 완료를 허용할 것인가?** *(3분 스트레칭을 30초에 끝낸 사용자에게 선택지가 없다)*
(a) "다 했어요" 버튼 (b) 일시정지만 (c) 현행. → (a)는 평균 소요 통계 의미가 바뀌고 mid/wrap 큐 트리거가 중간에 잘린다.

**Q5. 홈 대표 카드의 주인공은 무엇인가?** *(지금은 정보 카드가 라벨 없는 실행 버튼)*
(a) "다음 알람 + 예약 상태" 배지가 주인공, 시작은 명시 버튼 (b) "지금 루틴 시작"이 주인공 (c) 카드 탭=편집기 직행, 시작은 하단 섹션에만. → (a)는 알람 앱다워지나 낮 시간대에 비어 보임.

**Q6. ⚠️ AlarmKit 직접 진입에서 알람 정지가 실패하면?** *(현재 로그만 남고 TTS와 알람음이 겹칠 수 있다)*
(a) 현행 (b) AlarmRing으로 폴백 (c) 플레이어 상단 정지 재시도 배너. 함께: **`.deferredBusy`일 때 알람을 먼저 끄지 않도록 순서를 바꿀 것인가?** 그리고 **프로세스 재시작 후 `claimedNonces`가 비어 같은 알람이 다시 뜨는 것을 의도로 확정할 것인가?**

**Q7. 알람·마이크·위치 권한을 언제 요청할 것인가?** *(지금은 알람=「루틴 체험하기」 탭 순간, 마이크=새벽 루틴 도중, 위치=홈 첫 진입 자동)*
(a) 온보딩 알람 단계 앞에 사전 설명 (b) 현행 유지 + 결과를 완료 화면에 노출 (c) 마이크만 온보딩 목소리 단계로 앞당김. 위치는 별도로: 자동 요청을 유지할지, 이미 존재하는 "현재 위치 날씨 보기" 탭에서만 요청할지.

### Liquid Glass 범위

**Q8. 네이티브 `TabView` 전환은 확정 사항이므로, 남은 결정은 "탭 상태 보존을 받아들일 것인가"다.** *(현재 "매일 아침 초기 상태"는 기록 탭에만 의도적으로 구현돼 있고 나머지는 if/else의 부작용이다)*
(a) 상태 보존을 그대로 수용 (b) 홈 진입 시 명시적 리셋 규칙을 넣음 (c) 탭별로 다르게(기록만 리셋 유지).

**Q9. Profile·서버설정·개인정보 화면을 커스텀으로 통일할 것인가, 시스템 관용구로 남길 것인가?** *(우선순위는 낮지만 `.tint(AppColor.moruBlue)`는 앱 전체에서 이 한 곳뿐이라 (b)는 사실상 한 줄이다)*
(a) 전면 통일 (b) 시스템 관용구 유지 + tint만 브랜드 오렌지 (c) glass 도입 계기로 하위 화면만 네이티브 toolbar 통일.

**Q10. `MoruDialog` 6곳을 네이티브 alert/confirmationDialog로 대체할 것인가?** *(현재 스크림 밝기·바깥 탭 동작·접근성 경로가 화면마다 다르고, 폭 320은 두 경로 모두 고정)*
(a) 전부 네이티브 (b) 파괴적 확인만 네이티브 (c) 커스텀 유지 + 스크림/강조 통일. → (a)는 destructive role·Dynamic Type·glass 배경이 공짜지만 6곳 카피 위계를 다시 쓴다. **부속 결정: 바깥 탭으로 닫히게 할 것인가 —** 지금은 루틴 실행 중 다이얼로그가 닫히고 설정 다이얼로그가 안 닫혀서 위험도와 반대다.

**Q11. CTA 대비 문제를 어떻게 풀 것인가?** *(흰글씨/orange350 2.12:1, orange500로 올려도 3.09:1)*
(a) orange550(#E84000) 이상 (b) 글자를 gray600으로 (c) 브랜드 유지 + 접근성 포기. → glass 위에서는 실효 대비가 더 낮아진다. **같은 결정에 요일 미선택 1.70:1(`RoutineWeekdaySelector.swift:50,59`)을 포함할 것 — 알람 요일은 색 하나로만 표현되는 핵심 상태다.**

### 순서·운영 (로드맵 순서를 바꾸는 질문)

**Q12. 0단계로 CI를 넣을 것인가, 곧장 UI 작업을 시작할 것인가?**
(a) CI(scheme + testplan + macOS 러너)를 0단계로 (b) 곧장 UI 작업, CI는 첫 PR 이후. → (a)는 1~2일 비용에 이후 모든 작업의 회귀 비용을 낮추고, (b)는 1,027개 테스트를 매번 손으로 돌려야 한다. *(초판의 "AppRouter 분해 먼저 / `@Observable` 먼저" 선택지는 §8이 이미 1~3층으로 답하므로 제거했다.)*

**Q13. (a)라면 러너를 무엇으로 할 것인가?** GitHub 호스팅 macOS(분당 과금, Linux의 10배) / 집의 Mac을 self-hosted 러너로 등록(비용 0, 가용성 리스크) / 우선 pre-push 훅으로 로컬 강제. 그리고 매 PR에 전체 1,027개를 돌릴지, PR은 빌드+스모크 플랜만 돌리고 main 머지에만 전체를 돌릴지. **이 답이 0층의 실제 소요를 결정한다.**

**Q14. 시각 회귀의 "정답"을 무엇으로 삼을 것인가, 그리고 937MB 리포를 어떻게 할 것인가?**
(a) 승인된 앱 스크린샷을 golden으로(현재 24장이 이미 그 방식) (b) dHash 유지 (c) Figma export 대조. 함께: 854MB PNG를 LFS로 옮길지·과거 번들을 잘라낼지·`FinalScreenVisualTests.swift:396-400` 우회로 8장을 정상 게이트로 되돌릴지. **이 답에 따라 후보 ①②③의 재캡처 횟수가 달라지므로 순서 결정과 직결된다.**

**Q15. `mydocs/` 3,679줄과 `VoiceCoachingUXHandoff.md` 821줄을 리포에 커밋할 것인가?** *(원인이 다르다 — 전자는 `.git/info/exclude:9`, 후자는 단순 미추적)*
(a) 둘 다 리포에 커밋 (b) 핸드오프만 `Moru/docs/`에 커밋하고 개인 메모는 리포 밖 백업 (c) 현행 유지. → 이 문서들은 이 브리프의 근거이자 재작성 비용이 가장 비싼 자산인데 지금은 이 맥북에만 있다. 다만 개인 절대 경로·개인 메모가 섞여 있어 팀 리포에 넣을지는 소유자만 결정할 수 있다.

**Q16. Profile의 도달 불가 UI 약 800줄(이름 변경 시트, 서버 루틴 보관함 593줄, 서버 계정 요약 190줄)을 되살릴 것인가 삭제할 것인가?** → 되살리면 Profile이 로드맵 범위에 들어오고, 삭제하면 "쓰이고 있다"는 착시가 사라진다. **알람 섹션 부착(§3.4)은 어느 쪽이든 별개로 값싸다.**

**Q17. 알람 콜드 스타트를 위해 `preflight.prepare`를 `.ready` 이후로 미룰 것인가?** *(현재 알람 콜드 런치가 부트 완료를 기다린다)* → 미루면 스플래시 체류가 줄지만 정리 전 알람으로 진입하는 짧은 창이 생기므로, `AlarmRuntimeCoordinator.resolve`(`:50-72`)의 유효성 검사가 그 창을 막는지 먼저 확인해야 한다. **부속: 부트 실패·스플래시 구간에서도 "알람 끄기"와 `.onOpenURL`을 노출할 것인가?**

**Q18. 미사용 자산을 일괄 삭제할 것인가?** 공용 컴포넌트 9개(`MoruCard`·`MoruBottomCTA`는 전역 참조 0), 아이콘 struct 10개, AppIcon 토큰 18개 + 대응 imageset 18개(전체의 27%), AppColor 14개, AppFont 11개, `AppShadow` 전체. → 후보 ③의 범위를 결정한다.

### 첫 단계 후보 (아래 셋 중 어느 것부터?)
**후보 ①** 홈 대표 카드 + 알람 상태 표면 · **후보 ②** 온보딩·계정 진입 정직화 · **후보 ③** 토큰/CTA 통일 1단계(Glass 선행)

---

# 10. 첫 단계 후보 상세

## 후보 ① 홈 대표 카드 정직화 + 알람 상태 표면 (영역 3.2)

**범위:** `Features/Home/Components/CurrentRoutineCard.swift`, `HomeActiveRoutineSection.swift`, `Features/Home/Views/HomeView.swift`, `Features/Home/ViewModels/HomeViewModel.swift`, `Features/Home/Models/HomeViewState.swift`, `Features/Home/Components/HomeHeaderView.swift`, `HomeFigmaStyle.swift`. (선택적으로 `Features/Profile/ProfileView.swift`에 알람 섹션 부착 — ViewModel이 이미 완성돼 있어 뷰만 붙이면 된다.)

**사용자에게 달라지는 것:** 대표 카드에 다음 알람 시각과 예약 상태가 뜨고, "루틴 시작"이 명시적 버튼이 되며, 카드 본문 탭은 해당 루틴 하나로 간다. 새벽 5시에 "편안한 밤" 대신 아침 인사를 받는다.

**위험:** 낮음. ⚠️는 `alarmDeliveryState`를 홈까지 끌어오는 부분만 — 읽기 전용이라 스케줄링 계약은 건드리지 않는다. `HomeViewState`에 필드 추가 시 `state` 전체 재구성 비용이 늘어나므로, 죽은 `HomeContentState.weather`(`HomeViewState.swift:199`, 프로덕션 독자 0) 제거를 같은 PR에 묶는 것이 좋다.

**테스트:** `HomeWeatherTests.swift:428`(weather 단언을 `viewModel.weatherState`로 이동 — 이 파일이 죽은 사본의 유일한 독자다), `HomeProfileFigmaVisualTests`(홈 캡처 재승인), `HomeProfileFigmaVisualTests.swift:18`의 `HomeCopy.greeting` 카피 잠금 정리, `FinalScreenVisualTests` 홈 관련 dHash. **Profile 알람 섹션을 함께 붙인다면 `HomeProfileFigmaVisualTests.swift:882`의 `profile-permission-off` 베이스라인을 먼저 정리해야 한다 ★.**

**커밋 분할:** (1) 죽은 상태 제거 — `HomeContentState.weather` 삭제 + 테스트 이동. (2) 인사말에 dawn 구간 추가 + 미사용 `HomeCopy` 상수 정리. (3) 대표 카드에 명시적 시작 버튼 + 본문 탭 목적지를 `routineID` 기반으로 교체(`HomeView.swift:259-261`). (4) `alarmDeliveryState`를 `HomeRoutineState`에 추가하고 카드에 배지 렌더. (5) *(선택)* Profile 알람 섹션.

## 후보 ② 온보딩·계정 진입 정직화 (영역 3.1)

**범위:** `Features/AccountEntry/AccountEntryView.swift`, `Features/Onboarding/OnboardingFlowView.swift`, `OnboardingViewModel.swift`, `OnboardingStep.swift`, `DesignSystem/Components/MoruVoiceCard.swift`.

**사용자에게 달라지는 것:** 로그인 화면이 "왜 로그인하는가 / 데이터는 이 기기에 먼저 저장된다"를 실제로 말한다. 4초 가짜 정리 연출이 사라지거나 카피가 정직해진다. 목소리를 몇 번이든 다시 들을 수 있고 VoiceOver로 선택 상태를 안다. 추천 추가 진행률이 5/8이 아니라 1/3부터 시작한다. 비활성 CTA와 비활성 소셜 버튼이 이유를 말한다. 첫 화면(experience)에 확정 단계가 생기고 되돌아왔을 때 선택이 보인다.

**위험:** 낮음~중간. `organizing` 연출 제거는 로컬 폴백 데드엔드(`OnboardingViewModel.swift:486-492`, footer 없음 `:1629`)와 얽혀 있으므로 `organizingDidFinish()`가 **프로덕션 호출부 0·테스트 호출부 2**(`RecommendedRoutineCreationTests.swift:220`, `OnboardingHappyPathTests.swift:396`)라는 사실 — 즉 테스트는 초록인데 실제 화면은 못 빠져나오는 형태 — 를 함께 정리해야 한다. A10(루트 플래그 승격)까지 넣으면 중간 위험으로 올라가므로 별도 PR을 권한다.

**테스트:** `OptionalLoginEntryVisualTests.swift:134-147`(이제 진짜 렌더되는 문자열을 검증하게 됨), `OnboardingHappyPathTests.swift:286-322`(진행률), `OnboardingFigmaVisualTests` 베이스라인, `RecommendedRoutineCreationTests`.

**커밋 분할:** (1) `header`/`localFirstCard`를 body에 복원(순수 렌더 복구) + 소셜 버튼 비활성 사유 문구. (2) 목소리 카드: 재생 아이콘을 선택과 분리 + a11y 라벨/`.isSelected` + `relativeTo` 폰트. (3) 진행률을 flowMode별 실제 단계 배열 기반으로 계산. (4) experience 단계에 선택 상태 표시 + 확정 액션. (5) organizing 연출을 실제 소요에 비례시키고 카피 조정 + 죽은 API 정리.

## 후보 ③ 토큰·CTA 통일 1단계 (Liquid Glass 선행 · 전 영역)

**범위:** `DesignSystem/Components/MoruButton.swift`, `MoruPilotTokens.swift`, `AppColor.swift`, `AppLayout.swift`, `Features/Home/Views/HomeView.swift:766,791,809`, `Features/Onboarding/SplashScreenView.swift:37`, `RoutineFlow`의 사설 CTA 6곳, 텍스트 스타일 래퍼 8종.

**사용자에게 달라지는 것:** 같은 문구의 버튼이 화면마다 다른 높이·폰트로 보이던 것이 사라지고, 스플래시 "시작하기"가 큰 아이폰에서 좌우 여백을 남기지 않는다. 저장 오류 재시도 버튼(48pt)이 다른 CTA와 같아진다. 접근성 글자 크기에서 화면마다 줄간격이 붕괴하던 문제가 없어진다.

**위험:** 중간. **모든 비주얼 베이스라인이 무효화**되므로 후보 ①②보다 먼저 하면 그쪽 캡처를 두 번 승인하게 된다. 반대로 나중에 하면 ①②의 캡처를 다시 찍는다 — **순서 결정이 곧 재캡처 횟수 결정이고, Q14의 답이 그 비용을 정한다.** `FigmaPilotFoundationTests.swift:15-34,183-188`은 정의상 실패하므로 hex 정본 확정이 선행.

**테스트:** `FigmaPilotFoundationTests`(hex·픽셀), `FinalScreenVisualTests` dHash 20개, `RoutineManagementFigmaVisualTests`, `RoutinePlayerFigmaVisualTests`의 커밋된 after.png 24장, 카피 잠금 26개(3파일). **주의: `FinalScreenVisualTests.swift:396-400`의 우회로가 적용된 8장은 dHash를 안 타므로 이번 기회에 우회로를 제거하지 않으면 변경이 검출되지 않는다** ★. 임계값 24를 조정한다면 `visualHash` 구현 3곳 모두(`RoutinePlayerFigmaVisualTests.swift:150-152`는 인라인 매직넘버)를 고쳐야 한다 ★.

**커밋 분할:** (1) `MoruButton` 4개 legacy 호출부를 `.figmaPilot`로 전환(동작만 통일, enum은 유지). (2) `MoruPilotComponentStyle`와 모든 `componentStyle` 분기 삭제 + `buttonWidth` 고정폭 → `maxWidth: .infinity` + `minHeight: 54`(`MoruSelectionCard`/`MoruProgressBar`/`MoruDialog`의 353/352/320도 동반). (3) 사설 캡슐 CTA 6벌을 `MoruButton`으로 교체(높이 48/52/54 → 단일, 가로 여백 20/22 → 단일). (4) 텍스트 스타일 래퍼 8종 → 정본 `moruTextStyle(_:)` 1종으로 통합하고 AX line-height 정책을 하나로 확정(현재 `RoutineFinishedView.swift:426`만 유지, 나머지는 붕괴).

**공통 전제(후보 무관):** 착수 전 근거 문서 4,500줄의 백업 방식을 Q15로 먼저 정한다 — 지금은 `.git/info/exclude:9`(mydocs)와 미추적 상태(핸드오프) 때문에 이 브리프의 근거가 이 맥북에만 존재한다.

---

## 검토 메모

**추가한 것 (누락된 확정·★ 항목)**

1. **C10 알람 콜드 스타트 지연** — app-composition의 high 항목인데 초판에 없었다. 검증에서 매퍼 근거 2개(`:258`, `:96`)가 조건부로 축소됐고, 매 부팅마다 확실히 도는 `AppBootstrapper.swift:321,338`이 교정 증거로 제시됐으므로 그 형태로 실었다. 알람 앱의 가장 중요한 순간을 막는 문제라 §3.3 소속.
2. **C11 완료 요약이 미방문 단계를 숨김** — 집중 영역(플레이어) 안의 confirmed medium인데 빠져 있었다. Q3와 직결돼 §9에 부속 결정으로 묶었다. 매퍼가 원인으로 지목한 `RoutineFinishedView.swift:75-77`은 no-op이라는 교정을 반영했다.
3. **A9 권한 요청 타이밍 / A10 루트 플래그 소실** — A9는 confirmed medium인데 초판이 질문(Q7)으로만 다뤄 발견 목록에서 사라졌다. A10은 "온보딩 중 종료 → 로그인 화면을 영영 못 봄"(`AppRouter.swift:401-403`)이라는 검증자의 교정 증거로, 집중 영역이 온보딩·계정 진입이므로 반드시 있어야 한다.
4. **§3.4 신설** — History·Profile은 우선순위가 낮지만 confirmed high가 4건(Profile 알람 표면 0, 죽은 UI ~800줄, 히트맵 헤더 어긋남, 하루치 기록 4화면)이라 통째로 지우는 대신 압축 기록했다. 특히 **Profile 알람 섹션은 ViewModel이 이미 완성돼 뷰만 붙이면 되는 가장 싼 알람 표면**이라 후보 ①의 선택 항목으로 올렸다.
5. **§4 5번을 "양방향 의존 역전"으로 확장** — 초판은 Data/Domain→App만 다뤘는데, 검증자가 반대 방향(`AccountAuthorizationContext` 등이 Network/Core에 있고 Domain 12파일이 참조)과 HTTP 전송 아티팩트의 Domain 상주를 새로 찾았다. 둘은 같은 뿌리라 한 행으로 묶었다.
6. **§4 12번 신설(DI 경계)** — 구상 Platform 8개 + 경계 테스트 5개만 검사 + `RoutinePlayerBuilder`/`RoutineGuidanceCoordinator`도 구상 타입 보유(★, 알람 경로라 ProfileView보다 위험). 초판은 이 high 항목을 §1 표의 숫자로만 남겼다. 자리를 만들려고 §4를 12행으로 유지하고, 세우지 않은 나머지는 표 아래 한 문단으로 모았다(34메서드 프로토콜, Features의 DTO/Security 직접 사용, HomeWeatherService, 동형 에러 enum, 죽은 `reminderTask`, Noop 오디오 코디네이터 기본 인자 등).
7. **§5에 3개 항목 추가** — 거터 8종 + spacing 토큰의 radius 오용(confirmed, glass 규격 결정의 선행), 터치 타깃·모션(confirmed), `CommonComponentsMap.md` 표 불일치(★). 전부 Liquid Glass 작업 범위를 바꾼다.
8. **§9에 Q13~Q18 추가** — 각각 로드맵 순서나 범위를 실제로 바꾼다: 러너 형태(0층 소요), 시각 baseline 정본 + 937MB(재캡처 횟수 = ①②③ 순서), 문서 커밋 여부, Profile 죽은 UI, preflight 순서, 미사용 자산 삭제.

**고친 것 (근거와 어긋난 서술)**

9. **§8 0층의 "pbxproj `binary` 해제는 CI 도입의 전제(scheme 커밋이 pbxproj를 건드림)"를 삭제.** 어느 파일에도 그런 근거가 없다. shared scheme은 `xcshareddata/`에 파일을 추가하는 작업이라 pbxproj를 건드리지 않는다. "전제"가 아니라 "같이 하면 좋은 병행 과제"로 낮췄다.
10. **§10 공통 전제의 "먼저 커밋해야 한다"를 결정(Q15)으로 전환.** 사실은 "지금 이 맥북에만 있다"까지이고, 팀 리포에 개인 메모를 넣을지는 소유자 결정이다. 초판은 이걸 결정된 것처럼 서술했다.
11. **§1 "Domain 프로토콜 117"** → 117은 리포 전체 프로토콜 수(`protocols_repo_wide`)라 라벨을 고쳤다. **테스트/소스 비 0.84**는 교정 전 53,208줄 기준임을 각주로 달았다.
12. **§1 미추적 문서 행** — `mydocs/`(exclude)와 `VoiceCoachingUXHandoff.md`(단순 미추적)는 원인이 다른데 한 덩어리로 묶여 있었다. 검증자가 후자는 `git check-ignore` 결과 무시 대상이 아님을 확인했다.
13. **§2-8** "layer 트리 2패스 안정화" → "2회 연속 동일할 때까지 최대 8패스".
14. **§3.2 B2 제목** "홈 어디에도 알람 예약 상태가 없다" → 과장. `scheduleText`는 `HomeActiveRoutineSection.swift:125`에서 실제로 렌더된다. "대표 카드에 시각이 없고, 예약 성공 여부 표면이 루틴 탭 한 곳뿐"으로 좁혔다.
15. **§3.2 B6** "도달 불가 분기"를 확인이 아니라 추론으로 표기(`Routine.swift:62`에 nil 기본값이 있어 타입상으론 가능).
16. **§3.3 C2** "카운트다운이 멈춘 채 굳어 있다" → 런루프 타이머는 복귀 시 다시 틱하므로 정지가 아니라 드리프트. 초판 본문은 이미 드리프트로 썼으나 표현을 통일했다.
17. **§6-8** "알람 진입 UI 무방비"에 딸린 "플레이어 경로도 무방비"라는 함의를 제거. 검증에서 `RoutinePlayerFigmaVisualTests.swift:210-266`의 12상태 골든과 `RouterRuntimeContractTests.swift:692-1213`의 상태 전이 검증이 확인돼 "ViewModel 단위 테스트 0"은 refuted다. 남는 진짜 공백 3가지로 대체했다.
18. **§7 표의 번호 체계** — 초판은 우선순위 표 번호(#2 History)와 섹션 번호(§3 = History)를 섞어 썼는데, 이건 검증자가 지적한 계획서 자체의 내부 충돌을 그대로 재생산한 것이다. 표를 파일명 기준으로 바꾸고 충돌 자체를 한 행으로 명시했다.
19. **§9 Q8 전면 개정** — 소유자가 이미 "네이티브 TabView"를 결정했으므로 "전환할 것인가"는 결정된 질문이다. 남은 것은 상태 보존뿐이라 (c) 커스텀 유지 선택지를 제거했다. 또 "매일 아침 초기 상태"는 기록 탭에만 의도적으로 구현돼 있고(`MainTabView.swift:36-40, 102`) 나머지는 if/else의 부작용이라는 사실은 코드로 답이 나오므로 질문이 아니라 전제로 옮겼다.
20. **§9 Q12 축소** — (b) AppRouter 분해 먼저 / (c) `@Observable` 먼저는 §8이 1~3층으로 이미 답한 것이라 제거하고, CI 여부와 러너 형태(Q13)로 나눴다.

**드러낸 모순(초판이 덮고 지나간 것)**

21. **§2-7 강점과 §3.3 C1이 같은 코드다.** `isStepInteractionDisabled` 단일 게이트는 강점이자 감옥이다. 이걸 명시하지 않으면 리팩터링에서 게이트를 통째로 없애 §2-7의 보호(중복 완료·중복 종료 차단)를 잃는다. Q2 (b)안이 그 해법임을 연결했다.
22. **`claimedNonces`가 반대 방향 위험을 동시에 만든다.** app-composition 검증은 "프로세스 내 재진입 전부 no-op"을, concurrency 검증은 "프로세스 재시작 후 재claim 가능"을 지적했다. 초판은 앞의 절반만 실었다. 둘 다 같은 in-memory 집합의 결과이므로 C7과 Q6에 나란히 실었다.
23. **§2-1 강점의 한계** — FlowBuilder 5종 중 라우터에 주입 가능한 것은 3종뿐이라 메인 탭 조립은 계약 테스트 밖이다(★). "라우터 계약이 촘촘하다"를 근거로 탭 조립을 리팩터링하면 안전망이 없다.
24. **§4-7 프레이밍** — "프리미티브 부재"가 아니라 "Data/Platform에 3벌 있는데 Features가 모른다". 신규 `SingleFlight` 작성이 아니라 기존 구현 승격이 정답이라 제안 방향이 바뀐다(초판 표에는 반영돼 있었으나 제목이 반대로 읽혀 제목을 고쳤다).