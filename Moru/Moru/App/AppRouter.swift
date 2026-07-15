//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct AppRouter: View {
  @ObservedObject private var sessionStore: SessionStore
  @ObservedObject private var coordinator: AppNavigationCoordinator

  @State private var deferredOnboardingTrialRoutineID: UUID?
  @State private var homeRefreshToken = 0

  private let dependencies: DependencyContainer
  private let onboardingBuilder: any OnboardingFlowBuilding
  private let routinePlayerBuilder: any RoutinePlayerBuilding

  @MainActor
  init(
    dependencies: DependencyContainer,
    sessionStore: SessionStore,
    coordinator: AppNavigationCoordinator,
    onboardingBuilder: any OnboardingFlowBuilding,
    routinePlayerBuilder: any RoutinePlayerBuilding
  ) {
    _sessionStore = ObservedObject(wrappedValue: sessionStore)
    _coordinator = ObservedObject(wrappedValue: coordinator)
    self.dependencies = dependencies
    self.onboardingBuilder = onboardingBuilder
    self.routinePlayerBuilder = routinePlayerBuilder
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
          HomeView(
            dependencies: dependencies,
            onStartRoutine: handleRegularRoutineStart,
            refreshToken: homeRefreshToken
          )
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
        case .ready:
            #if DEBUG
            AlarmKitDebugView(
                dependencies: dependencies
            )
            #else
            ContentView(
                title: "안녕하세요, \(sessionStore.profile?.displayName ?? "모루 사용자")님",
                message: "로컬 루틴 데이터 기준선이 준비되었습니다."
            )
            #endif
        case .failed(let message):
          ContentView(
            title: "저장소를 열 수 없어요",
            message: message
          )
        }
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
  private func routinePlayerView(for presentation: AppPresentation) -> AnyView {
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
  private func handleRegularRoutineStart(routineID: UUID) {
    _ = coordinator.presentRegularRoutine(routineID: routineID)
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
    }
  }

  @MainActor
  private func completePendingDismissal() {
    let effect = coordinator.presentationDidDismiss()
    homeRefreshToken += 1
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
