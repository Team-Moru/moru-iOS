//
//  AppNavigationCoordinator.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import Combine
import Foundation

enum AppPresentation: Identifiable, Equatable {
  case onboardingTrial(routineID: UUID, token: UUID)
  case regularRoutine(
    routineID: UUID,
    source: RegularRoutineExecutionRequest.Source,
    token: UUID
  )
  case alarmRing(context: AlarmRingContext, token: UUID)

  var id: UUID {
    switch self {
    case .onboardingTrial(_, let token),
         .regularRoutine(_, _, let token),
         .alarmRing(_, let token):
      token
    }
  }

}

enum AppPresentationRequest: Equatable {
  case onboardingTrial(routineID: UUID)
  case regularRoutine(
    routineID: UUID,
    source: RegularRoutineExecutionRequest.Source
  )
  case alarmRing(context: AlarmRingContext)

  func matches(_ presentation: AppPresentation) -> Bool {
    switch (self, presentation) {
    case let (.onboardingTrial(requestedRoutineID), .onboardingTrial(activeRoutineID, _)):
      return requestedRoutineID == activeRoutineID
    case let (
      .regularRoutine(requestedRoutineID, _),
      .regularRoutine(activeRoutineID, _, _)
    ):
      return requestedRoutineID == activeRoutineID
    case let (.alarmRing(requestedContext), .alarmRing(activeContext, _)):
      return requestedContext.ingress.alarmID == activeContext.ingress.alarmID
    default:
      return false
    }
  }

  func makePresentation(token: UUID) -> AppPresentation {
    switch self {
    case .onboardingTrial(let routineID):
      return .onboardingTrial(routineID: routineID, token: token)
    case .regularRoutine(let routineID, let source):
      return .regularRoutine(
        routineID: routineID,
        source: source,
        token: token
      )
    case .alarmRing(let context):
      return .alarmRing(context: context, token: token)
    }
  }
}

enum PresentationAttempt: Equatable {
  case presented(UUID)
  case alreadyPresented(UUID)
  case deferredBusy
}

enum AppNavigationEffect: Equatable {
  case none
  case dismiss(token: UUID)
  case reloadSession
  case showHome
  case showRunDetail(UUID)
}

enum AppNavigationState: Equatable {
  case idle
  case presented(AppPresentation)
  case dismissalArmed(
    presentation: AppPresentation,
    afterDismiss: AppNavigationEffect,
    isPresentationCleared: Bool
  )

  var visiblePresentation: AppPresentation? {
    switch self {
    case .idle:
      return nil
    case .presented(let presentation):
      return presentation
    case .dismissalArmed(let presentation, _, let isPresentationCleared):
      return isPresentationCleared ? nil : presentation
    }
  }

  var activePresentation: AppPresentation? {
    switch self {
    case .idle:
      return nil
    case .presented(let presentation):
      return presentation
    case .dismissalArmed(let presentation, _, _):
      return presentation
    }
  }

  var pendingDismissalToken: UUID? {
    guard case .dismissalArmed(let presentation, _, _) = self else {
      return nil
    }

    return presentation.id
  }
}

enum AppNavigationAction: Equatable {
  case handle(event: RoutinePlayerEvent, presentationToken: UUID)
  case dismissAlarmRing(presentationToken: UUID)
  case startScheduledRoutine(
    routineID: UUID,
    alarmPresentationToken: UUID
  )
  case clearPresentationForDismissal(token: UUID)
  case presentationDidDismiss(token: UUID)
}

struct AppNavigationTransition: Equatable {
  let state: AppNavigationState
  let effect: AppNavigationEffect
}

struct AppPresentationAdmission: Equatable {
  let state: AppNavigationState
  let attempt: PresentationAttempt
}

enum AppNavigationReducer {
  static func reduce(
    state: AppNavigationState,
    action: AppNavigationAction
  ) -> AppNavigationTransition {
    switch action {
    case .handle(let event, let presentationToken):
      return handle(event, presentationToken: presentationToken, from: state)
    case .dismissAlarmRing(let presentationToken):
      return dismissAlarmRing(presentationToken: presentationToken, from: state)
    case .startScheduledRoutine(let routineID, let alarmPresentationToken):
      return startScheduledRoutine(
        routineID: routineID,
        alarmPresentationToken: alarmPresentationToken,
        from: state
      )
    case .clearPresentationForDismissal(let token):
      return clearPresentationForDismissal(token, from: state)
    case .presentationDidDismiss(let token):
      return presentationDidDismiss(token, from: state)
    }
  }

  static func admitPresentation(
    _ request: AppPresentationRequest,
    from state: AppNavigationState
  ) -> AppPresentationAdmission {
    guard let activePresentation = state.activePresentation else {
      let presentation = request.makePresentation(token: UUID())

      return AppPresentationAdmission(
        state: .presented(presentation),
        attempt: .presented(presentation.id)
      )
    }

    if request.matches(activePresentation) {
      return AppPresentationAdmission(
        state: state,
        attempt: .alreadyPresented(activePresentation.id)
      )
    }

    return AppPresentationAdmission(state: state, attempt: .deferredBusy)
  }

  private static func handle(
    _ event: RoutinePlayerEvent,
    presentationToken: UUID,
    from state: AppNavigationState
  ) -> AppNavigationTransition {
    guard case .exitRequested(let exit) = event,
          case .presented(let presentation) = state,
          presentation.id == presentationToken else {
      return AppNavigationTransition(state: state, effect: .none)
    }

    let afterDismiss: AppNavigationEffect

    switch (presentation, exit) {
    case (.onboardingTrial, .summaryRecord):
      return AppNavigationTransition(state: state, effect: .none)
    case (.onboardingTrial, _):
      afterDismiss = .reloadSession
    case (.regularRoutine, .summaryCTA):
      afterDismiss = .showHome
    case (.regularRoutine, .summaryRecord(let runID)):
      afterDismiss = .showRunDetail(runID)
    case (.regularRoutine, _):
      afterDismiss = .none
    case (.alarmRing, _):
      return AppNavigationTransition(state: state, effect: .none)
    }

    return AppNavigationTransition(
      state: .dismissalArmed(
        presentation: presentation,
        afterDismiss: afterDismiss,
        isPresentationCleared: false
      ),
      effect: .dismiss(token: presentationToken)
    )
  }

  private static func dismissAlarmRing(
    presentationToken: UUID,
    from state: AppNavigationState
  ) -> AppNavigationTransition {
    guard case .presented(let presentation) = state,
          case .alarmRing = presentation,
          presentation.id == presentationToken else {
      return AppNavigationTransition(state: state, effect: .none)
    }

    return AppNavigationTransition(
      state: .dismissalArmed(
        presentation: presentation,
        afterDismiss: .none,
        isPresentationCleared: false
      ),
      effect: .dismiss(token: presentationToken)
    )
  }

  private static func startScheduledRoutine(
    routineID: UUID,
    alarmPresentationToken: UUID,
    from state: AppNavigationState
  ) -> AppNavigationTransition {
    guard case .presented(let presentation) = state,
          case .alarmRing = presentation,
          presentation.id == alarmPresentationToken else {
      return AppNavigationTransition(state: state, effect: .none)
    }

    return AppNavigationTransition(
      state: .presented(
        .regularRoutine(
          routineID: routineID,
          source: .scheduled,
          token: UUID()
        )
      ),
      effect: .none
    )
  }

  private static func clearPresentationForDismissal(
    _ token: UUID,
    from state: AppNavigationState
  ) -> AppNavigationTransition {
    guard case .dismissalArmed(let presentation, let afterDismiss, false) = state,
          presentation.id == token else {
      return AppNavigationTransition(state: state, effect: .none)
    }

    return AppNavigationTransition(
      state: .dismissalArmed(
        presentation: presentation,
        afterDismiss: afterDismiss,
        isPresentationCleared: true
      ),
      effect: .none
    )
  }

  private static func presentationDidDismiss(
    _ token: UUID,
    from state: AppNavigationState
  ) -> AppNavigationTransition {
    guard case .dismissalArmed(let presentation, let afterDismiss, true) = state,
          presentation.id == token else {
      return AppNavigationTransition(state: state, effect: .none)
    }

    return AppNavigationTransition(state: .idle, effect: afterDismiss)
  }

}

@MainActor
final class AppNavigationCoordinator: ObservableObject {
  @Published private(set) var navigationState: AppNavigationState

  private var hasStartedInitialSessionLoad = false
  private var deferredAlarmRingContext: AlarmRingContext?

  var presentation: AppPresentation? {
    navigationState.visiblePresentation
  }

  var pendingDismissalToken: UUID? {
    navigationState.pendingDismissalToken
  }

  init(navigationState: AppNavigationState = .idle) {
    self.navigationState = navigationState
  }

  func beginInitialSessionLoadIfNeeded() -> Bool {
    guard !hasStartedInitialSessionLoad else {
      return false
    }

    hasStartedInitialSessionLoad = true
    return true
  }

  func presentOnboardingTrial(routineID: UUID) -> PresentationAttempt {
    attemptPresentation(.onboardingTrial(routineID: routineID))
  }

  func presentRegularRoutine(routineID: UUID) -> PresentationAttempt {
    attemptPresentation(
      .regularRoutine(routineID: routineID, source: .manual)
    )
  }

  func presentAlarmRing(context: AlarmRingContext) -> PresentationAttempt {
    let attempt = attemptPresentation(.alarmRing(context: context))

    switch attempt {
    case .presented, .alreadyPresented:
      if deferredAlarmRingContext?.ingress.alarmID == context.ingress.alarmID {
        deferredAlarmRingContext = nil
      }
    case .deferredBusy:
      deferredAlarmRingContext = context
    }
    return attempt
  }

  func takeDeferredAlarmRingContext() -> AlarmRingContext? {
    guard navigationState.activePresentation == nil else {
      return nil
    }

    defer {
      deferredAlarmRingContext = nil
    }
    return deferredAlarmRingContext
  }

  func dismissAlarmRing(presentationToken: UUID) -> AppNavigationEffect {
    apply(.dismissAlarmRing(presentationToken: presentationToken)).effect
  }

  func startScheduledRoutine(
    routineID: UUID,
    alarmPresentationToken: UUID
  ) {
    _ = apply(
      .startScheduledRoutine(
        routineID: routineID,
        alarmPresentationToken: alarmPresentationToken
      )
    )
  }

  func handle(
    event: RoutinePlayerEvent,
    presentationToken: UUID
  ) -> AppNavigationEffect {
    apply(.handle(event: event, presentationToken: presentationToken)).effect
  }

  func presentationBindingDidChange(to presentation: AppPresentation?) {
    guard presentation == nil,
          case .dismissalArmed(let activePresentation, _, false) = navigationState else {
      return
    }

    _ = apply(.clearPresentationForDismissal(token: activePresentation.id))
  }

  func presentationDidDismiss() -> AppNavigationEffect {
    guard case .dismissalArmed(_, _, true) = navigationState,
          let token = pendingDismissalToken else {
      return .none
    }

    return apply(.presentationDidDismiss(token: token)).effect
  }

  private func attemptPresentation(
    _ request: AppPresentationRequest
  ) -> PresentationAttempt {
    let admission = AppNavigationReducer.admitPresentation(
      request,
      from: navigationState
    )
    updateNavigationState(admission.state)
    return admission.attempt
  }

  @discardableResult
  private func apply(_ action: AppNavigationAction) -> AppNavigationTransition {
    let transition = AppNavigationReducer.reduce(
      state: navigationState,
      action: action
    )
    updateNavigationState(transition.state)
    return transition
  }

  private func updateNavigationState(_ state: AppNavigationState) {
    navigationState = state
  }
}
