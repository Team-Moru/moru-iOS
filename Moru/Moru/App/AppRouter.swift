//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
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
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var sessionStore: SessionStore
  @ObservedObject private var coordinator: AppNavigationCoordinator

  @State private var deferredOnboardingTrialRoutineID: UUID?
  @StateObject private var state: AppRouterState

  private let dependencies: DependencyContainer
  private let onboardingBuilder: any OnboardingFlowBuilding
  private let routinePlayerBuilder: any RoutinePlayerBuilding
  private let homeBuilder: any HomeFlowBuilding

  @MainActor
  init(
    dependencies: DependencyContainer,
    sessionStore: SessionStore,
    coordinator: AppNavigationCoordinator,
    onboardingBuilder: any OnboardingFlowBuilding,
    routinePlayerBuilder: any RoutinePlayerBuilding,
    homeBuilder: (any HomeFlowBuilding)? = nil,
    state: AppRouterState? = nil
  ) {
    _sessionStore = ObservedObject(wrappedValue: sessionStore)
    _coordinator = ObservedObject(wrappedValue: coordinator)
    self.dependencies = dependencies
    self.onboardingBuilder = onboardingBuilder
    self.routinePlayerBuilder = routinePlayerBuilder
    _state = StateObject(wrappedValue: state ?? AppRouterState())
    if let homeBuilder {
      self.homeBuilder = homeBuilder
    } else {
      self.homeBuilder = DefaultHomeFlowBuilder(
        loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
          routineRepository: dependencies.routineRepository,
          routineRunRepository: dependencies.routineRunRepository,
          localProfileRepository: dependencies.localProfileRepository
        ),
        weatherRepository: dependencies.homeWeatherRepository,
        weatherService: dependencies.homeWeatherService,
        routineSettingContentFactory: {
          AnyView(RoutineSettingView(dependencies: dependencies))
        }
      )
    }
  }

  var body: some View {
    Group {
      switch sessionStore.phase {
      case .loading:
        ProgressView()

      case .onboardingRequired:
        onboardingBuilder.make(
          onCompleted: handleOnboardingCompleted
        )

      case .ready:
        if sessionStore.profile != nil {
          mainTabView
        } else {
          SessionFailureView(
            title: "프로필 정보를 확인할 수 없어요",
            message: "앱 상태가 올바르지 않아요. 다시 시도해 주세요.",
            onRetry: { @MainActor in
              sessionStore.load()
            }
          )
        }

      case .failed(let message):
        SessionFailureView(
          title: "저장소를 열 수 없어요",
          message: message,
          onRetry: { @MainActor in
            sessionStore.load()
          }
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
    .task {
      if coordinator.beginInitialSessionLoadIfNeeded() {
        sessionStore.load()
      }
      await dependencies.alarmScheduleMutator?.reconcile()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }

      Task {
        await dependencies.alarmScheduleMutator?.reconcile()
      }
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
        routineRunRepository: dependencies.routineRunRepository
      )
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
        alarmService: profileAlarmService
      )
    }
    let profileBuilder = DefaultProfileFlowBuilder(
      profileSettingsUseCase: profileSettingsUseCase,
      voicePreviewPlayer: AVSpeechVoicePreviewPlayer(
        availabilityProbe: dependencies.voiceAvailabilityProbe
      ),
      alarmService: profileAlarmService,
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
      onResetSucceeded: {
        sessionStore.load()
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
    case .reloadSession:
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
