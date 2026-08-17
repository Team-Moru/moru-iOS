//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
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

  func setHistoryDestination(_ destination: HistoryDestination?) {
    var nextState = mainTabState
    nextState.setHistoryDestination(destination)
    mainTabState = nextState
  }
}

struct AppRouter: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var sessionStore: SessionStore
  @ObservedObject private var accountSessionStore: AccountSessionStore
  @ObservedObject private var geminiDataConsentStore: GeminiDataConsentStore
  @ObservedObject private var coordinator: AppNavigationCoordinator

  @State private var deferredOnboardingTrialRoutineID: UUID?
  @State private var didStartOnboarding = false
  @State private var didCompleteOnboardingTrial = false
  @State private var didCompleteAccountEntry = false
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
    _state = StateObject(wrappedValue: state ?? AppRouterState())
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
          localProfileRepository: dependencies.localProfileRepository
        ),
        enrichHomeRoutinesUseCase: enrichHomeRoutinesUseCase,
        weatherRepository: dependencies.homeWeatherRepository,
        weatherService: dependencies.homeWeatherService,
        sessionIdentityProvider: accountSessionStore,
        routineSettingContentFactory: {
          AnyView(RoutineSettingView(dependencies: dependencies))
        },
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
        didStartOnboarding: didStartOnboarding,
        didCompleteOnboardingTrial: didCompleteOnboardingTrial,
        didCompleteAccountEntry: didCompleteAccountEntry
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
            didCompleteAccountEntry = true
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
      routinePlayerView(for: presentation)
        .id(presentation.id)
        .interactiveDismissDisabled()
    }
    .sheet(isPresented: geminiConsentPresentationBinding) {
      GeminiDataConsentView(consentStore: geminiDataConsentStore)
    }
    .task {
      onboardingStatusRuntimeCoordinator?.start()
      routineSyncRuntimeCoordinator?.setSceneActive(scenePhase == .active)
      dependencies.routineTTSWarmupCoordinator?
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
      if didCompleteOnboardingTrial,
         case .signedIn = newState {
        didCompleteAccountEntry = true
      }
      routineSyncRuntimeCoordinator?.accountSessionDidChange()
      dependencies.routineTTSWarmupCoordinator?.accountSessionDidChange()
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
    didCompleteAccountEntry: Bool
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

    if didCompleteOnboardingTrial {
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
    didStartOnboarding = true
  }

  @MainActor
  private func resetToNewUserFlow() {
    deferredOnboardingTrialRoutineID = nil
    didStartOnboarding = false
    didCompleteOnboardingTrial = false
    didCompleteAccountEntry = false
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
    case .startingScheduledRoutine(let context, _):
      return AnyView(
        AlarmStartingView(routineName: context.routineName)
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
      deferredOnboardingTrialRoutineID = nil
    case .deferredBusy:
      deferredOnboardingTrialRoutineID = routineID
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
  var mainTabView: MainTabView {
    let historySummaryEnricher = dependencies.accountHistoryRemoteService.map {
      AccountHistorySummaryEnricher(
        remoteService: $0,
        signedInMemberProvider: accountSessionStore
      )
    }
    let accountDailyReportLoader =
      dependencies.accountHistoryRemoteService.map {
        LoadAccountHistoryDailyReportUseCase(
          remoteService: $0,
          signedInMemberProvider: accountSessionStore
        )
      }
    let historyBuilder = DefaultHistoryFlowBuilder(
      loadHistoryUseCase: LoadHistoryUseCase(
        routineRepository: dependencies.routineRepository,
        routineRunRepository: dependencies.routineRunRepository
      ),
      summaryEnricher: historySummaryEnricher,
      accountDailyReportLoader: accountDailyReportLoader,
      accountIdentity: accountSessionStore.signedInMemberID
    )
    let profileSettingsUseCase = ProfileSettingsUseCase(
      localProfileRepository: dependencies.localProfileRepository,
      voiceAvailabilityProbe: dependencies.voiceAvailabilityProbe
    )
    let profileAlarmService = dependencies.profileAlarmService
      ?? UnavailableProfileAlarmService()
    let resetUseCase = dependencies.localDataResetRepository.map {
      ResetLocalDataUseCase(
        localDataResetRepository: $0,
        alarmService: profileAlarmService,
        routineTTSAudioCacheCleaner:
          dependencies.routineTTSAudioCache.map {
            RoutineTTSAudioCacheCleaner(cache: $0)
          }
      )
    }
    let profileBuilder = DefaultProfileFlowBuilder(
      profileSettingsUseCase: profileSettingsUseCase,
      voicePreviewPlayer: dependencies.makeVoicePreviewPlayer(),
      alarmService: profileAlarmService,
      accountServerRemoteService: dependencies.accountServerRemoteService,
      accountRoutineGroupRemoteService:
        dependencies.accountRoutineGroupRemoteService,
      serverVoicePreviewPlayer: dependencies.serverVoicePreviewPlayer,
      accountSessionStore: accountSessionStore,
      socialLoginCoordinator: socialLoginCoordinator,
      googleAuthorizationSession: googleAuthorizationSession,
      kakaoAuthorizationSession: kakaoAuthorizationSession,
      accountLifecycleService: accountLifecycleService,
      geminiDataConsentStore: geminiDataConsentStore,
      appCapabilities: appCapabilities,
      resetUseCase: resetUseCase,
      resetAvailability: {
        coordinator.presentation == nil && coordinator.pendingDismissalToken == nil
      },
      onOpenSettings: {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          return
        }

        UIApplication.shared.open(url)
      },
      onResetSucceeded: resetToNewUserFlow,
      onServerVoiceSelectionDidSucceed: { selection in
        dependencies.routineTTSWarmupCoordinator?
          .serverVoiceSelectionDidChange(
            memberID: selection.memberID,
            selectionVersion: selection.selectionVersion
          )
      }
    )
    let mainTabState = state.mainTabState

    return MainTabView(
      home: homeBuilder.make(
        onStartRoutine: handleRegularRoutineLaunch,
        refreshToken: state.homeRefreshToken
      ),
      routineSetting: RoutineSettingView(dependencies: dependencies),
      history: historyBuilder.make(destination: historyDestinationBinding),
      profile: profileBuilder.make(),
      selection: mainTabSelectionBinding,
      historyReloadToken: mainTabState.historyReloadToken
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
      didCompleteOnboardingTrial = true
      if case .signedIn = accountSessionStore.state {
        didCompleteAccountEntry = true
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
    state.refreshHome()
    execute(effect)
    retryDeferredAlarmIngressOrOnboarding()
  }

  @MainActor
  private func retryDeferredOnboardingTrial() {
    guard let routineID = deferredOnboardingTrialRoutineID else {
      return
    }

    switch coordinator.presentOnboardingTrial(routineID: routineID) {
    case .presented, .alreadyPresented:
      deferredOnboardingTrialRoutineID = nil
    case .deferredBusy:
      break
    }
  }

  @MainActor
  private func consumePendingAlarmIngress() async {
    guard sessionStore.phase == .ready,
          dependencies.alarmRuntimeHandler != nil,
          let envelope = AlarmIngressOccurrenceStore.shared
            .claimPendingEnvelope() else {
      return
    }

    await handleAlarmIngress(envelope)
  }

  @MainActor
  private func handleAlarmIngress(_ envelope: AlarmIngressEnvelope) async {
    guard let alarmRuntimeHandler = dependencies.alarmRuntimeHandler else {
      AlarmIngressOccurrenceStore.shared.release(envelope)
      return
    }

    switch await alarmRuntimeHandler.resolve(envelope) {
    case .route(let context):
      await presentResolvedAlarm(context)
    case .ignored:
      AlarmIngressOccurrenceStore.shared.complete(envelope)
    case .temporarilyUnavailable:
      AlarmIngressOccurrenceStore.shared.release(envelope)
    }
  }

  @MainActor
  private func presentResolvedAlarm(_ context: AlarmRingContext) async {
    guard context.ingress.launchTarget == .scheduledRoutine else {
      switch coordinator.presentAlarmRing(context: context) {
      case .presented, .alreadyPresented:
        AlarmIngressOccurrenceStore.shared.complete(context.ingress)
      case .deferredBusy:
        break
      }
      return
    }

    let attempt = coordinator.presentScheduledRoutineStart(context: context)
    switch attempt {
    case .deferredBusy:
      return
    case .alreadyPresented:
      AlarmIngressOccurrenceStore.shared.complete(context.ingress)
      return
    case .presented(let presentationToken):
      do {
        guard let alarmRuntimeHandler = dependencies.alarmRuntimeHandler else {
          throw AlarmRuntimeError.routeNoLongerAvailable
        }

        try await alarmRuntimeHandler.startRoutine(from: context)
        guard coordinator.completeScheduledRoutineStart(
          routineID: context.ingress.routineID,
          startingPresentationToken: presentationToken
        ) else {
          throw AlarmRuntimeError.routeNoLongerAvailable
        }
      } catch {
        coordinator.failScheduledRoutineStart(
          startingPresentationToken: presentationToken
        )
      }
      AlarmIngressOccurrenceStore.shared.complete(context.ingress)
    }
  }

  @MainActor
  private func startScheduledRoutine(
    from context: AlarmRingContext,
    presentationToken: UUID
  ) async throws {
    guard let alarmRuntimeHandler = dependencies.alarmRuntimeHandler else {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }

    try await alarmRuntimeHandler.startRoutine(from: context)
    guard coordinator.startScheduledRoutine(
      routineID: context.ingress.routineID,
      alarmPresentationToken: presentationToken
    ) else {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }
  }

  @MainActor
  private func snooze(
    context: AlarmRingContext,
    minutes: Int,
    presentationToken: UUID
  ) async throws {
    guard let alarmRuntimeHandler = dependencies.alarmRuntimeHandler else {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }

    _ = try await alarmRuntimeHandler.snooze(
      context: context,
      minutes: minutes
    )
    execute(
      coordinator.dismissAlarmRing(
        presentationToken: presentationToken
      )
    )
  }

  @MainActor
  private func retryDeferredAlarmIngressOrOnboarding() {
    guard let context = coordinator.takeDeferredAlarmContext() else {
      retryDeferredOnboardingTrial()
      return
    }

    Task {
      await handleAlarmIngress(context.ingress)
      if coordinator.presentation == nil {
        retryDeferredOnboardingTrial()
      }
    }
  }
}

private struct AlarmStartingView: View {
  let routineName: String

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          AppColor.babyBlue100,
          AppColor.babyBlue150,
          AppColor.babyBlue250,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 16) {
        ProgressView()
          .tint(.white)
          .controlSize(.large)

        Text("\(routineName) 시작 중")
          .font(AppFont.body1NormalBold)
          .foregroundStyle(Color.white)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(routineName) 루틴 시작 중")
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
