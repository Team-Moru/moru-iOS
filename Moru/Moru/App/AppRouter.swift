//
//  AppRouter.swift
//  Moru
//
//

import Combine
import SwiftUI
import UIKit

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
  @ObservedObject private var sessionStore: SessionStore
  @ObservedObject private var coordinator: AppNavigationCoordinator

  @State private var deferredOnboardingTrialRoutineID: UUID?
  @ObservedObject private var state: AppRouterState

  private let dependencies: DependencyContainer
  private let onboardingBuilder: any OnboardingFlowBuilding
  private let routinePlayerBuilder: any RoutinePlayerBuilding
  private let homeBuilder: any HomeFlowBuilding
  private let requestSessionReload: @MainActor (SessionReloadSource) -> Void
  private let retrySessionReloadAction: @MainActor () -> Void

  @MainActor
  init(
    dependencies: DependencyContainer,
    sessionStore: SessionStore,
    coordinator: AppNavigationCoordinator,
    onboardingBuilder: any OnboardingFlowBuilding,
    routinePlayerBuilder: any RoutinePlayerBuilding,
    requestSessionReload: @escaping @MainActor (SessionReloadSource) -> Void,
    retrySessionReload: @escaping @MainActor () -> Void,
    homeBuilder: any HomeFlowBuilding,
    state: AppRouterState
  ) {
    _sessionStore = ObservedObject(wrappedValue: sessionStore)
    _coordinator = ObservedObject(wrappedValue: coordinator)
    self.dependencies = dependencies
    self.onboardingBuilder = onboardingBuilder
    self.routinePlayerBuilder = routinePlayerBuilder
    self.requestSessionReload = requestSessionReload
    retrySessionReloadAction = retrySessionReload
    _state = ObservedObject(wrappedValue: state)
    self.homeBuilder = homeBuilder
  }

  var body: some View {
    Group {
      switch sessionStore.phase {
      case .loading:
        ProgressView()
      case .onboardingRequired:
        onboardingBuilder.make(onCompleted: handleOnboardingCompleted)
      case .ready:
        if sessionStore.profile != nil {
          mainTabView
        } else {
          SessionFailureView(
            title: "프로필 정보를 확인할 수 없어요",
            message: "앱 상태가 올바르지 않아요. 다시 시도해 주세요.",
            onRetry: retrySessionReload
          )
        }
      case .failed(let message):
        SessionFailureView(
          title: "저장소를 열 수 없어요",
          message: message,
          onRetry: retrySessionReload
        )
      }
    }
    .fullScreenCover(
      item: presentationBinding,
      onDismiss: completePendingDismissal
    ) { presentation in
      routinePlayerView(for: presentation)
        .interactiveDismissDisabled()
    }
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
    case .regularRoutine(let routineID, let token):
      return routinePlayerBuilder.makeRegular(
        request: RegularRoutineExecutionRequest(
          routineID: routineID,
          source: .manual
        ),
        presentationToken: token,
        onEvent: handleRoutinePlayerEvent
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
    let historyBuilder = DefaultHistoryFlowBuilder(
      loadHistoryUseCase: LoadHistoryUseCase(
        routineRunRepository: dependencies.routineRunRepository,
        historyEvidenceRepository: dependencies.historyEvidenceRepository,
        currentResetGeneration: { sessionStore.snapshot?.resetGeneration }
      )
    )
    let profileSettingsUseCase = ProfileSettingsUseCase(
      localProfileRepository: dependencies.localProfileRepository,
      localSettingsRepository: dependencies.localSettingsRepository,
      voiceAvailabilityProbe: dependencies.voiceAvailabilityProbe
    )
    let profileBuilder = DefaultProfileFlowBuilder(
      profileSettingsUseCase: profileSettingsUseCase,
      voicePreviewPlayer: AVSpeechVoicePreviewPlayer(
        availabilityProbe: dependencies.voiceAvailabilityProbe
      ),
      alarmStatusProvider: { profileAlarmStatus },
      resetPerformer: AlarmResetPendingProfileLocalResetPerformer(coordinator: coordinator),
      onOpenSettings: {
        openSystemSettings()
      },
      onRetryAlarmRepair: {
        retrySessionReload()
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

  private var profileAlarmStatus: ProfileAlarmStatus {
    guard let platformStates = sessionStore.snapshot?.platformStates,
          !platformStates.isEmpty else {
      return .unavailable
    }

    if platformStates.contains(where: { $0.state == .repairRequired }) {
      return .repairRequired
    }

    if platformStates.contains(where: { $0.state == .configured }) {
      return .configured
    }

    return .unavailable
  }

  private func openSystemSettings() {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
      return
    }

    UIApplication.shared.open(settingsURL)
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
    case .reloadSession(let source):
      requestSessionReload(source)
    case .showHome:
      state.showHome()
    case .showRunDetail(let runID):
      state.showRunDetail(runID)
    }
  }

  @MainActor
  func retrySessionReload() {
    retrySessionReloadAction()
  }

  @MainActor
  func completePendingDismissal() {
    guard coordinator.pendingDismissalToken != nil else {
      return
    }

    let effect = coordinator.presentationDidDismiss()
    state.refreshHome()
    retryDeferredOnboardingTrial()
    execute(effect)
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
}

private enum ProfileLocalResetUnavailableError: Error {
  case alarmResetRequired
}

@MainActor
private final class AlarmResetPendingProfileLocalResetPerformer: ProfileLocalResetPerforming {
  private let coordinator: AppNavigationCoordinator

  init(coordinator: AppNavigationCoordinator) {
    self.coordinator = coordinator
  }

  func availability() -> LocalResetAvailability {
    if coordinator.presentation != nil || coordinator.pendingDismissalToken != nil {
      return .blockedByActiveRoutine
    }

    return .blockedByAlarmReset
  }

  func reset() async throws {
    throw ProfileLocalResetUnavailableError.alarmResetRequired
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
