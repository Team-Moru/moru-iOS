//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import OSLog
import SwiftUI
import UIKit

nonisolated enum AppRootDestination: Equatable, Sendable {
  case splash(showStartCTA: Bool)
  case accountEntry(AccountSessionFailure?)
  case onboarding
  case main
  case sessionFailure(title: String, message: String)
}

@MainActor
final class AppRouterState: ObservableObject {
  @Published private(set) var homeRefreshToken = 0
  @Published private(set) var mainTabState = MainTabState()

  /// 루트 전이 입력. 예전에는 AppRouter의 View-local @State라 프로세스가 죽으면
  /// 전부 리셋됐다. 그중 계정 진입 대기만 저장소에 남긴다.
  @Published private(set) var deferredOnboardingTrialRoutineID: UUID?
  @Published private(set) var didStartOnboarding = false
  @Published private(set) var didCompleteOnboardingTrial = false
  @Published private(set) var didCompleteAccountEntry = false

  private let onboardingProgressStore: (any OnboardingProgressStoring)?

  init(onboardingProgressStore: (any OnboardingProgressStoring)? = nil) {
    self.onboardingProgressStore = onboardingProgressStore
  }

  /// 체험을 마쳤는데 계정 연결을 아직 못 본 상태. 이전 실행에서 남은 값도 포함한다.
  var isAccountEntryPending: Bool {
    if didCompleteOnboardingTrial, !didCompleteAccountEntry {
      return true
    }

    return onboardingProgressStore?.isAccountEntryPending ?? false
  }

  func markOnboardingStarted() {
    didStartOnboarding = true
  }

  func markOnboardingTrialCompleted() {
    didCompleteOnboardingTrial = true
    onboardingProgressStore?.setAccountEntryPending(true)
  }

  func markAccountEntryCompleted() {
    didCompleteAccountEntry = true
    onboardingProgressStore?.setAccountEntryPending(false)
  }

  func setDeferredOnboardingTrialRoutineID(_ routineID: UUID?) {
    deferredOnboardingTrialRoutineID = routineID
  }

  func resetOnboardingFlags() {
    deferredOnboardingTrialRoutineID = nil
    didStartOnboarding = false
    didCompleteOnboardingTrial = false
    didCompleteAccountEntry = false
    onboardingProgressStore?.setAccountEntryPending(false)
  }

  func refreshHome() {
    homeRefreshToken += 1
  }

  func selectMainTab(_ tab: MoruTabItem) {
    var nextState = mainTabState
    nextState.select(tab)
    mainTabState = nextState
  }

  func showHome() {
    var nextState = mainTabState
    nextState.showHome()
    mainTabState = nextState
  }

  func showRunDetail(_ runID: UUID) {
    var nextState = mainTabState
    nextState.showRunDetail(runID)
    mainTabState = nextState
  }

  func showRoutineEditor(_ routineID: UUID) {
    var nextState = mainTabState
    nextState.showRoutineEditor(routineID)
    mainTabState = nextState
  }

  func setHistoryDestination(_ destination: HistoryDestination?) {
    var nextState = mainTabState
    nextState.setHistoryDestination(destination)
    mainTabState = nextState
  }
}

struct AppRouter: View {
  private static let alarmLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Moru",
    category: "AlarmRuntime"
  )

  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var sessionStore: SessionStore
  @ObservedObject private var accountSessionStore: AccountSessionStore
  @ObservedObject private var geminiDataConsentStore: GeminiDataConsentStore
  @ObservedObject private var coordinator: AppNavigationCoordinator

  @State private var alarmStopMonitor = ScheduledAlarmStopMonitor()
  @State private var accountServerViewModel: AccountServerSettingsViewModel
  @StateObject private var state: AppRouterState

  private let dependencies: DependencyContainer
  private let socialLoginCoordinator: any SocialLoginCoordinating
  private let googleAuthorizationSession: any GoogleAuthorizationStarting
  private let kakaoAuthorizationSession: any KakaoAuthorizationStarting
  private let accountLifecycleService: any AccountLifecycleManaging
  private let appCapabilities: AppCapabilities
  private let onboardingBuilder: any OnboardingFlowBuilding
  private let routinePlayerBuilder: any RoutinePlayerBuilding
  private let homeBuilder: any HomeFlowBuilding
  private let historyBuilder: any HistoryFlowBuilding
  private let injectedProfileBuilder: (any ProfileFlowBuilding)?
  // 프로필 빌더의 콜백은 뷰의 @State를 만지므로 body에서 만들고, 무거운 의존은 여기 한 번만 만든다.
  private let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  private let profileAlarmService: any ProfileAlarmServicing
  private let profileResetUseCase: (any ResetLocalDataUseCaseProtocol)?
  private let profileVoicePreviewPlayer: any VoicePreviewPlaying
  private let onboardingStatusRuntimeCoordinator:
    OnboardingStatusRuntimeCoordinator?
  private let routineSyncRuntimeCoordinator: RoutineSyncRuntimeCoordinator?

  @MainActor
  init(
    dependencies: DependencyContainer,
    sessionStore: SessionStore,
    accountSessionStore: AccountSessionStore,
    geminiDataConsentStore: GeminiDataConsentStore = GeminiDataConsentStore(),
    socialLoginCoordinator: any SocialLoginCoordinating,
    googleAuthorizationSession: any GoogleAuthorizationStarting =
      UnavailableGoogleAuthorizationSession(),
    kakaoAuthorizationSession: any KakaoAuthorizationStarting =
      UnavailableKakaoAuthorizationSession(),
    accountLifecycleService: any AccountLifecycleManaging =
      UnavailableAccountLifecycleService(),
    appCapabilities: AppCapabilities = .production,
    coordinator: AppNavigationCoordinator,
    onboardingBuilder: any OnboardingFlowBuilding,
    routinePlayerBuilder: any RoutinePlayerBuilding,
    homeBuilder: (any HomeFlowBuilding)? = nil,
    historyBuilder: (any HistoryFlowBuilding)? = nil,
    profileBuilder: (any ProfileFlowBuilding)? = nil,
    onboardingStatusRuntimeCoordinator:
      OnboardingStatusRuntimeCoordinator? = nil,
    routineSyncRuntimeCoordinator: RoutineSyncRuntimeCoordinator? = nil,
    state: AppRouterState? = nil
  ) {
    _sessionStore = ObservedObject(wrappedValue: sessionStore)
    _accountSessionStore = ObservedObject(wrappedValue: accountSessionStore)
    _geminiDataConsentStore = ObservedObject(
      wrappedValue: geminiDataConsentStore
    )
    _coordinator = ObservedObject(wrappedValue: coordinator)
    self.dependencies = dependencies
    self.socialLoginCoordinator = socialLoginCoordinator
    self.googleAuthorizationSession = googleAuthorizationSession
    self.kakaoAuthorizationSession = kakaoAuthorizationSession
    self.accountLifecycleService = accountLifecycleService
    self.appCapabilities = appCapabilities
    self.onboardingBuilder = onboardingBuilder
    self.routinePlayerBuilder = routinePlayerBuilder
    self.onboardingStatusRuntimeCoordinator =
      onboardingStatusRuntimeCoordinator
    self.routineSyncRuntimeCoordinator = routineSyncRuntimeCoordinator
    _accountServerViewModel = State(
      initialValue: AccountServerSettingsViewModel(
        remoteService: dependencies.accountServerRemoteService,
        preparationStatusCenter:
          dependencies.routineTTSPreparationStatusCenter,
        voiceSelectionStore:
          UserDefaultsRoutineTTSVoiceSelectionVersionStore(),
        onServerVoiceSelectionDidSucceed: { selection in
          dependencies.routineTTSWarmupCoordinator?
            .serverVoiceSelectionDidChange(
              memberID: selection.memberID,
              selectionVersion: selection.selectionVersion,
              selectedTTSID: selection.ttsID
            )
          dependencies.serverVoiceCommonAudioProvider?
            .serverVoiceSelectionDidChange(
              memberID: selection.memberID,
              selectedTTSID: selection.ttsID,
              selectionVersion: selection.selectionVersion
            )
        }
      )
    )
    _state = StateObject(
      wrappedValue: state ?? AppRouterState(
        onboardingProgressStore: UserDefaultsOnboardingProgressStore()
      )
    )
    if let historyBuilder {
      self.historyBuilder = historyBuilder
    } else {
      self.historyBuilder = DefaultHistoryFlowBuilder(
        loadHistoryUseCase: LoadHistoryUseCase(
          routineRepository: dependencies.routineRepository,
          routineRunRepository: dependencies.routineRunRepository
        ),
        summaryEnricher: dependencies.accountHistoryRemoteService.map {
          AccountHistorySummaryEnricher(
            remoteService: $0,
            signedInMemberProvider: accountSessionStore
          )
        },
        accountDailyReportLoader: dependencies.accountHistoryRemoteService.map {
          LoadAccountHistoryDailyReportUseCase(
            remoteService: $0,
            signedInMemberProvider: accountSessionStore
          )
        },
        signedInMemberProvider: accountSessionStore
      )
    }
    self.injectedProfileBuilder = profileBuilder
    self.profileSettingsUseCase = ProfileSettingsUseCase(
      localProfileRepository: dependencies.localProfileRepository,
      voiceAvailabilityProbe: dependencies.voiceAvailabilityProbe
    )
    let profileAlarmService = dependencies.profileAlarmService
      ?? UnavailableProfileAlarmService()
    self.profileAlarmService = profileAlarmService
    self.profileResetUseCase = dependencies.localDataResetRepository.map {
      ResetLocalDataUseCase(
        localDataResetRepository: $0,
        alarmService: profileAlarmService,
        routineTTSAudioCacheCleaner:
          dependencies.routineTTSAudioCache.map {
            RoutineTTSAudioCacheCleaner(cache: $0)
          }
      )
    }
    self.profileVoicePreviewPlayer = dependencies.makeVoicePreviewPlayer()
    if let homeBuilder {
      self.homeBuilder = homeBuilder
    } else {
      let enrichHomeRoutinesUseCase: (any EnrichHomeRoutinesUseCaseProtocol)?
      if let remoteService = dependencies.accountRoutineGroupRemoteService,
         let syncRepository = dependencies.routineSyncRepository {
        enrichHomeRoutinesUseCase = EnrichHomeRoutinesUseCase(
          remoteService: remoteService,
          sessionIdentityProvider: accountSessionStore,
          syncStateReader: DefaultHomeRoutineSyncStateReader(
            repository: syncRepository
          )
        )
      } else {
        enrichHomeRoutinesUseCase = nil
      }
      self.homeBuilder = DefaultHomeFlowBuilder(
        loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
          routineRepository: dependencies.routineRepository,
          routineRunRepository: dependencies.routineRunRepository,
          localProfileRepository: dependencies.localProfileRepository,
          alarmPlatformStateRepository: dependencies.alarmPlatformStateRepository
        ),
        enrichHomeRoutinesUseCase: enrichHomeRoutinesUseCase,
        weatherRepository: dependencies.homeWeatherRepository,
        weatherService: dependencies.homeWeatherService,
        sessionIdentityProvider: accountSessionStore,
        routineCreationContentFactory: {
          AnyView(
            RoutineSettingView(
              dependencies: dependencies,
              entryPoint: .newRoutine
            )
          )
        }
      )
    }
  }

  var body: some View {
    Group {
      switch Self.rootDestination(
        sessionPhase: sessionStore.phase,
        hasLocalProfile: sessionStore.profile != nil,
        accountState: accountSessionStore.state,
        accountFeaturesEnabled: appCapabilities.shouldShowAccountUI,
        didStartOnboarding: state.didStartOnboarding,
        didCompleteOnboardingTrial: state.didCompleteOnboardingTrial,
        didCompleteAccountEntry: state.didCompleteAccountEntry,
        isAccountEntryPending: state.isAccountEntryPending
      ) {
      case .splash(let showStartCTA):
        SplashScreenView(
          onStart: showStartCTA ? handleOnboardingStarted : nil
        )

      case .accountEntry(let restorationFailure):
        AccountEntryView(
          viewModel: AccountEntryViewModel(
            socialLoginCoordinator: socialLoginCoordinator
          ),
          googleAuthorizationSession: googleAuthorizationSession,
          kakaoAuthorizationSession: kakaoAuthorizationSession,
          restorationFailure: restorationFailure,
          onContinueWithoutLogin: {
            state.markAccountEntryCompleted()
          }
        )

      case .onboarding:
        onboardingBuilder.make(
          onCompleted: handleOnboardingCompleted
        )

      case .main:
        mainTabView

      case .sessionFailure(let title, let message):
        SessionFailureView(
          title: title,
          message: message,
          onRetry: { @MainActor in
            if onboardingStatusRuntimeCoordinator?
              .retryRestorationForCurrentSession() != true {
              sessionStore.load()
            }
          }
        )
      }
    }
    .fullScreenCover(
      item: presentationBinding,
      onDismiss: completePendingDismissal
    ) { presentation in
      AlarmStopRetryBannerContainer(
        isVisible: alarmStopMonitor.showsRetryBanner(for: presentation.id),
        isRetrying: alarmStopMonitor.isRetrying,
        onRetry: retryScheduledAlarmStop
      ) {
        routinePlayerView(for: presentation)
          .id(presentation.id)
      }
      .interactiveDismissDisabled()
    }
    .sheet(isPresented: geminiConsentPresentationBinding) {
      GeminiDataConsentView(consentStore: geminiDataConsentStore)
    }
    .task {
      if let transferManager =
          dependencies.routineTTSBackgroundTransferManager {
        RoutineTTSBackgroundLifecycleBridge.shared.configure(
          transferManager: transferManager,
          resumeHandler: {
            await dependencies.routineTTSWarmupCoordinator?
              .resumeBackgroundPrefetchOpportunity()
            await dependencies.serverVoiceCommonAudioProvider?
              .resumeBackgroundPrefetchOpportunity()
          }
        )
      }
      onboardingStatusRuntimeCoordinator?.start()
      routineSyncRuntimeCoordinator?.setSceneActive(scenePhase == .active)
      dependencies.routineTTSWarmupCoordinator?
        .setSceneActive(scenePhase == .active)
      dependencies.serverVoiceCommonAudioProvider?
        .setSceneActive(scenePhase == .active)
      if coordinator.beginInitialSessionLoadIfNeeded(),
         sessionStore.phase == .loading {
        sessionStore.load()
      }
      await consumePendingAlarmIngress()
      await dependencies.alarmScheduleMutator?.reconcile()
    }
    .onChange(of: scenePhase) { _, newPhase in
      routineSyncRuntimeCoordinator?.setSceneActive(newPhase == .active)
      dependencies.routineTTSWarmupCoordinator?
        .setSceneActive(newPhase == .active)
      dependencies.serverVoiceCommonAudioProvider?
        .setSceneActive(newPhase == .active)
      guard newPhase == .active else {
        return
      }

      Task {
        await consumePendingAlarmIngress()
        await dependencies.alarmScheduleMutator?.reconcile()
      }
    }
    .onChange(of: accountSessionStore.state) { _, newState in
      // Establish loading/barrier state before AccountEntry marks the login as
      // complete, otherwise a provisional profile can route to Home first.
      onboardingStatusRuntimeCoordinator?.accountSessionDidChange()
      if state.didCompleteOnboardingTrial,
         case .signedIn = newState {
        state.markAccountEntryCompleted()
      }
      if case .signedIn = newState {
        // Ask right after login instead of waiting for the user to opt into
        // AI routine creation later. A no-op once the user has already
        // decided (`requestGeminiDataConsentIfNeeded` only acts on
        // `.undecided`), so this never re-prompts someone who already chose.
        geminiDataConsentStore.requestGeminiDataConsentIfNeeded()
      }
      routineSyncRuntimeCoordinator?.accountSessionDidChange()
      dependencies.routineTTSWarmupCoordinator?.accountSessionDidChange()
      dependencies.serverVoiceCommonAudioProvider?.accountSessionDidChange()
      if case .restoring = newState {
        return
      }
      Task {
        await consumePendingAlarmIngress()
      }
    }
    .onChange(of: geminiDataConsentStore.status) { _, _ in
      routineSyncRuntimeCoordinator?.geminiDataConsentDidChange()
    }
    .onChange(of: sessionStore.phase) { _, newPhase in
      guard newPhase == .ready else {
        return
      }

      Task {
        await consumePendingAlarmIngress()
        await dependencies.alarmScheduleMutator?.reconcile()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: AlarmIngressOccurrenceStore.didSaveNotification
      )
    ) { _ in
      Task {
        await consumePendingAlarmIngress()
      }
    }
  }

  private var geminiConsentPresentationBinding: Binding<Bool> {
    Binding(
      get: { geminiDataConsentStore.isConsentPresentationRequested },
      set: { isPresented in
        if !isPresented {
          geminiDataConsentStore.dismissConsentChoices()
        }
      }
    )
  }

  nonisolated static func rootDestination(
    sessionPhase: SessionStore.Phase,
    hasLocalProfile: Bool,
    accountState: AccountSessionState,
    accountFeaturesEnabled: Bool,
    didStartOnboarding: Bool,
    didCompleteOnboardingTrial: Bool,
    didCompleteAccountEntry: Bool,
    isAccountEntryPending: Bool = false
  ) -> AppRootDestination {
    switch sessionPhase {
    case .loading:
      return .splash(showStartCTA: false)
    case .failed(let message):
      return .sessionFailure(
        title: "저장소를 열 수 없어요",
        message: message
      )
    case .ready, .onboardingRequired:
      break
    }

    // 체험 직후이거나, 이전 실행에서 체험만 끝내고 죽은 경우를 같은 길로 보낸다.
    // 후자를 빠뜨리면 프로필이 이미 있어 곧장 홈으로 가고 계정 연결 화면을 영영 못 본다.
    if didCompleteOnboardingTrial || isAccountEntryPending {
      guard hasLocalProfile else {
        return .sessionFailure(
          title: "프로필 정보를 확인할 수 없어요",
          message: "앱 상태가 올바르지 않아요. 다시 시도해 주세요."
        )
      }

      guard accountFeaturesEnabled, !didCompleteAccountEntry else {
        return .main
      }

      switch accountState {
      case .restoring:
        return .splash(showStartCTA: false)
      case .signedIn:
        return .main
      case .withdrawalPending:
        return .main
      case .signedOut:
        return .accountEntry(nil)
      case .failure(let failure):
        return .accountEntry(failure)
      }
    }

    if hasLocalProfile {
      return .main
    }

    guard sessionPhase == .onboardingRequired else {
      return .sessionFailure(
        title: "프로필 정보를 확인할 수 없어요",
        message: "앱 상태가 올바르지 않아요. 다시 시도해 주세요."
      )
    }

    if didStartOnboarding {
      return .onboarding
    }

    guard accountFeaturesEnabled,
          case .restoring = accountState else {
      return .splash(showStartCTA: true)
    }

    return .splash(showStartCTA: false)
  }

  @MainActor
  private func handleOnboardingStarted() {
    state.markOnboardingStarted()
  }

  @MainActor
  private func resetToNewUserFlow() {
    Task {
      await dependencies.routineTTSBackgroundTransferManager?
        .discardAllTransfers()
    }
    state.resetOnboardingFlags()
    sessionStore.load()
  }

  private var presentationBinding: Binding<AppPresentation?> {
    Binding(
      get: { coordinator.presentation },
      set: { value in
        coordinator.presentationBindingDidChange(to: value)
      }
    )
  }

  @MainActor
  func routinePlayerView(for presentation: AppPresentation) -> AnyView {
    switch presentation {
    case .onboardingTrial(let routineID, let token):
      return routinePlayerBuilder.makeTrial(
        request: TrialRoutineExecutionRequest(routineID: routineID),
        presentationToken: token,
        onEvent: handleRoutinePlayerEvent
      )
    case .regularRoutine(let routineID, let source, let token):
      return routinePlayerBuilder.makeRegular(
        request: RegularRoutineExecutionRequest(
          routineID: routineID,
          source: source
        ),
        presentationToken: token,
        onEvent: handleRoutinePlayerEvent
      )
    case .alarmRing(let context, let token):
      return AnyView(
        AlarmRingView(
          routineName: context.routineName,
          routineMinutes: context.routineMinutes,
          alarmDate: context.ingress.fireDate,
          onStartRoutine: {
            try await startScheduledRoutine(
              from: context,
              presentationToken: token
            )
          },
          onSnoozeSelected: { minutes in
            try await snooze(
              context: context,
              minutes: minutes,
              presentationToken: token
            )
          }
        )
      )
    }
  }

  @MainActor
  private func handleOnboardingCompleted(routineID: UUID) {
    switch coordinator.presentOnboardingTrial(routineID: routineID) {
    case .presented, .alreadyPresented:
      state.setDeferredOnboardingTrialRoutineID(nil)
    case .deferredBusy:
      state.setDeferredOnboardingTrialRoutineID(routineID)
    }
  }

  @MainActor
  private func handleRegularRoutineLaunch(
    _ request: RoutineLaunchRequest
  ) -> RoutineLaunchResult {
    Self.regularRoutineLaunchResult(
      from: coordinator.presentRegularRoutine(routineID: request.routineID)
    )
  }

  static func regularRoutineLaunchResult(
    from admission: PresentationAttempt
  ) -> RoutineLaunchResult {
    switch admission {
    case .presented:
      .started
    case .alreadyPresented:
      .alreadyRunning
    case .deferredBusy:
      .busy
    }
  }

  @MainActor
  var mainTabView: some View {
    MainTabView(
      home: homeBuilder.make(
        onStartRoutine: handleRegularRoutineLaunch,
        onOpenRoutineSettings: { routineID in
          guard let routineID else {
            state.selectMainTab(.routine)
            return
          }

          state.showRoutineEditor(routineID)
        },
        refreshToken: state.homeRefreshToken
      ),
      // 홈에서 편집 요청이 오면 루트의 정체성을 바꿔 해당 루틴의 편집기를 한 번 연다.
      routineSetting: RoutineSettingView(
        dependencies: dependencies,
        entryPoint: state.mainTabState.routineEditRequest
          .map(RoutineSettingEntryPoint.editRoutine) ?? .list
      )
      .id(state.mainTabState.routineEditRequest),
      history: historyBuilder.make(
        destination: historyDestinationBinding,
        reloadToken: state.mainTabState.historyReloadToken
      ),
      profile: profileBuilder.make(),
      selection: mainTabSelectionBinding
    )
  }

  private var profileBuilder: any ProfileFlowBuilding {
    if let injectedProfileBuilder {
      return injectedProfileBuilder
    }

    return DefaultProfileFlowBuilder(
      profileSettingsUseCase: profileSettingsUseCase,
      voicePreviewPlayer: profileVoicePreviewPlayer,
      alarmService: profileAlarmService,
      accountServerViewModel: accountServerViewModel,
      serverVoicePreviewPlayer: dependencies.serverVoicePreviewPlayer,
      accountSessionStore: accountSessionStore,
      socialLoginCoordinator: socialLoginCoordinator,
      googleAuthorizationSession: googleAuthorizationSession,
      kakaoAuthorizationSession: kakaoAuthorizationSession,
      accountLifecycleService: accountLifecycleService,
      geminiDataConsentStore: geminiDataConsentStore,
      appCapabilities: appCapabilities,
      resetUseCase: profileResetUseCase,
      resetAvailability: {
        coordinator.presentation == nil && coordinator.pendingDismissalToken == nil
      },
      onOpenSettings: {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          return
        }

        UIApplication.shared.open(url)
      },
      onResetSucceeded: resetToNewUserFlow
    )
  }

  private var mainTabSelectionBinding: Binding<MoruTabItem> {
    Binding(
      get: { state.mainTabState.selection },
      set: { tab in
        state.selectMainTab(tab)
      }
    )
  }

  private var historyDestinationBinding: Binding<HistoryDestination?> {
    Binding(
      get: { state.mainTabState.historyDestination },
      set: { destination in
        state.setHistoryDestination(destination)
      }
    )
  }

  @MainActor
  private func handleRoutinePlayerEvent(
    presentationToken: UUID,
    event: RoutinePlayerEvent
  ) {
    execute(coordinator.handle(event: event, presentationToken: presentationToken))
  }

  @MainActor
  private func execute(_ effect: AppNavigationEffect) {
    switch effect {
    case .none:
      break
    case .dismiss(_):
      presentationBinding.wrappedValue = nil
    case .enterAccountEntry:
      state.markOnboardingTrialCompleted()
      if case .signedIn = accountSessionStore.state {
        state.markAccountEntryCompleted()
      }
      sessionStore.load()
    case .showHome:
      state.showHome()
    case .showRunDetail(let runID):
      state.showRunDetail(runID)
    }
  }

  @MainActor
  func completePendingDismissal() {
    guard coordinator.pendingDismissalToken != nil else {
      return
    }

    let effect = coordinator.presentationDidDismiss()
    alarmStopMonitor.clear()
    state.refreshHome()
    execute(effect)
    retryDeferredAlarmIngressOrOnboarding()
  }

  @MainActor
  private func retryDeferredOnboardingTrial() {
    guard let routineID = state.deferredOnboardingTrialRoutineID else {
      return
    }

    switch coordinator.presentOnboardingTrial(routineID: routineID) {
    case .presented, .alreadyPresented:
      state.setDeferredOnboardingTrialRoutineID(nil)
    case .deferredBusy:
      break
    }
  }

  /// 알람 진입·정지는 AlarmIngressDriver가 맡는다. 라우터는 씬·세션 훅에서
  /// 드라이버를 부르고, 알람이 없을 때의 다음 후보(온보딩 체험 복원)만 안다.
  @MainActor
  private var alarmIngressDriver: AlarmIngressDriver {
    AlarmIngressDriver(
      alarmRuntimeHandler: dependencies.alarmRuntimeHandler,
      coordinator: coordinator,
      alarmStopMonitor: alarmStopMonitor
    )
  }

  @MainActor
  private func consumePendingAlarmIngress() async {
    await alarmIngressDriver.consumePendingIngress(
      sessionPhase: sessionStore.phase,
      accountState: accountSessionStore.state
    )
  }

  @MainActor
  private func consumePendingAlarmIngressAfterAccountRestoration() async {
    await alarmIngressDriver
      .consumePendingIngressAfterAccountRestoration(
        sessionPhase: sessionStore.phase
      )
  }

  @MainActor
  private func retryScheduledAlarmStop() {
    alarmIngressDriver.retryStop()
  }

  @MainActor
  private func startScheduledRoutine(
    from context: AlarmRingContext,
    presentationToken: UUID
  ) async throws {
    try await alarmIngressDriver.startScheduledRoutine(
      from: context,
      presentationToken: presentationToken
    )
  }

  @MainActor
  private func snooze(
    context: AlarmRingContext,
    minutes: Int,
    presentationToken: UUID
  ) async throws {
    execute(
      try await alarmIngressDriver.snooze(
        context: context,
        minutes: minutes,
        presentationToken: presentationToken
      )
    )
  }

  @MainActor
  private func retryDeferredAlarmIngressOrOnboarding() {
    let driver = alarmIngressDriver
    Task {
      guard await driver.retryDeferredIngress() else {
        retryDeferredOnboardingTrial()
        return
      }
    }
  }
}

private struct SessionFailureView: View {
  let title: String
  let message: String
  let onRetry: @MainActor () -> Void

  var body: some View {
    VStack(spacing: 16) {
      ContentView(
        title: title,
        message: message
      )
      Button("다시 시도", action: onRetry)
    }
  }
}
