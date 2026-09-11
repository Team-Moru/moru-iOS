//
//  RouterRuntimeContractTests.swift
//  MoruTests
//
//  Created by Codex on 7/13/26.
//

import Foundation
import XCTest
import SwiftUI
@testable import Moru

final class RouterRuntimeContractTests: XCTestCase {
  @MainActor
  func testResolverReportsMissingUnavailableEmptyAndScheduledEligibility() {
    let routineID = UUID()
    let repository = ResolvingRoutineRepository()
    let useCase = ResolveRoutineExecutionUseCase(routineRepository: repository)
    let scheduledRequest = ResolveRoutineExecutionRequest(
      routineID: routineID,
      launch: .scheduled
    )

    XCTAssertEqual(useCase.execute(scheduledRequest), .notFound)

    repository.shouldThrowWhenResolving = true
    XCTAssertEqual(
      useCase.execute(scheduledRequest),
      .temporarilyUnavailable(.repositoryUnavailable)
    )

    repository.shouldThrowWhenResolving = false
    repository.routine = makeExecutableRoutine(id: routineID, steps: [])
    XCTAssertEqual(
      useCase.execute(scheduledRequest),
      .ineligible(.noExecutableSteps)
    )

    let inactiveRoutine = makeExecutableRoutine(id: routineID, isActive: false)
    repository.routine = inactiveRoutine
    XCTAssertEqual(useCase.execute(scheduledRequest), .ineligible(.inactive))
    XCTAssertEqual(
      useCase.execute(
        ResolveRoutineExecutionRequest(routineID: routineID, launch: .manual)
      ),
      .available(inactiveRoutine)
    )

    let disabledAlarmRoutine = makeExecutableRoutine(
      id: routineID,
      alarmEnabled: false
    )
    repository.routine = disabledAlarmRoutine
    XCTAssertEqual(useCase.execute(scheduledRequest), .ineligible(.alarmDisabled))
    XCTAssertEqual(
      useCase.execute(
        ResolveRoutineExecutionRequest(routineID: routineID, launch: .manual)
      ),
      .available(disabledAlarmRoutine)
    )
  }

  @MainActor
  func testResolverLimitsOnlyTrialExecutionToTwoSteps() {
    let routineID = UUID()
    let steps = (0..<4).map { index in
      RoutineStep(
        type: .confirm,
        title: "루틴 \(index + 1)",
        order: index
      )
    }
    let routine = makeExecutableRoutine(id: routineID, steps: steps)
    let repository = ResolvingRoutineRepository()
    repository.routine = routine
    let useCase = ResolveRoutineExecutionUseCase(routineRepository: repository)

    let trialResolution = useCase.execute(
      ResolveRoutineExecutionRequest(routineID: routineID, launch: .trial)
    )
    let trialRoutine: Routine
    if case .available(let resolvedRoutine) = trialResolution {
      trialRoutine = resolvedRoutine
    } else {
      XCTFail("The trial routine should be available.")
      return
    }

    XCTAssertEqual(
      trialRoutine.steps.map(\.id),
      Array(steps.prefix(OnboardingTrialRoutineStepLimit.maximum)).map(\.id)
    )
    XCTAssertEqual(trialRoutine.steps.map(\.order), [0, 1])
    XCTAssertEqual(
      useCase.execute(
        ResolveRoutineExecutionRequest(routineID: routineID, launch: .manual)
      ),
      .available(routine)
    )
    XCTAssertEqual(
      useCase.execute(
        ResolveRoutineExecutionRequest(routineID: routineID, launch: .scheduled)
      ),
      .available(routine)
    )
    XCTAssertEqual(repository.routine, routine)
  }

  @MainActor
  func testResolverKeepsSingleStepTrialAvailable() {
    let routineID = UUID()
    let routine = makeExecutableRoutine(id: routineID)
    let repository = ResolvingRoutineRepository()
    repository.routine = routine
    let useCase = ResolveRoutineExecutionUseCase(routineRepository: repository)

    XCTAssertEqual(
      useCase.execute(
        ResolveRoutineExecutionRequest(routineID: routineID, launch: .trial)
      ),
      .available(routine)
    )
  }

  @MainActor
  func testCoordinatorDistinguishesPresentedAlreadyPresentedAndDeferredBusy() {
    let coordinator = AppNavigationCoordinator()
    let routineID = UUID()

    guard case .presented(let token) = coordinator.presentOnboardingTrial(
      routineID: routineID
    ) else {
      XCTFail("The first trial presentation should be accepted.")
      return
    }

    XCTAssertEqual(coordinator.presentation?.id, token)
    XCTAssertEqual(
      coordinator.presentOnboardingTrial(routineID: routineID),
      .alreadyPresented(token)
    )
    XCTAssertEqual(
      coordinator.presentOnboardingTrial(routineID: UUID()),
      .deferredBusy
    )
  }

  @MainActor
  func testRoutineLaunchRequestPreservesTheExactRoutineID() {
    let routineID = UUID()
    let request = RoutineLaunchRequest(routineID: routineID)

    XCTAssertEqual(request.routineID, routineID)
  }

  @MainActor
  func testRoutineEditRequestSwitchesToTheRoutineTabAndClearsOnNextNavigation() {
    var state = MainTabState()
    let routineID = UUID()

    XCTAssertNil(state.routineEditRequest)

    state.showRoutineEditor(routineID)

    XCTAssertEqual(state.selection, .routine)
    XCTAssertEqual(state.routineEditRequest, routineID)
    XCTAssertNil(state.historyDestination)

    // 사용자가 탭을 직접 고르면 편집 요청은 사라져 다시 열리지 않는다.
    state.select(.routine)

    XCTAssertNil(state.routineEditRequest)

    state.showRoutineEditor(routineID)
    state.showHome()

    XCTAssertEqual(state.selection, .home)
    XCTAssertNil(state.routineEditRequest)

    state.showRoutineEditor(routineID)
    state.showRunDetail(UUID())

    XCTAssertEqual(state.selection, .record)
    XCTAssertNil(state.routineEditRequest)
  }

  @MainActor
  func testHomeSettingsEntryReachesTheRoutineTabInsteadOfASheet() {
    let builder = CapturingHomeFlowBuilder()
    let state = AppRouterState()
    // 라우터가 홈 빌더에 넘기는 배선과 같은 형태다.
    let openRoutineSettings: (UUID?) -> Void = { routineID in
      guard let routineID else {
        state.selectMainTab(.routine)
        return
      }

      state.showRoutineEditor(routineID)
    }
    _ = builder.make(
      onStartRoutine: { _ in .started },
      onOpenRoutineSettings: openRoutineSettings,
      refreshToken: 0
    )

    let routineID = UUID()
    builder.onOpenRoutineSettings?(routineID)

    XCTAssertEqual(state.mainTabState.selection, .routine)
    XCTAssertEqual(state.mainTabState.routineEditRequest, routineID)

    builder.onOpenRoutineSettings?(nil)

    XCTAssertEqual(state.mainTabState.selection, .routine)
    XCTAssertNil(state.mainTabState.routineEditRequest)
  }

  @MainActor
  func testMainTabStateMakesHistoryReachableAndReloadsItForEachSelection() {
    var state = MainTabState()

    XCTAssertEqual(MainTabState.availableTabs, [.home, .routine, .record, .my])
    XCTAssertEqual(state.selection, .home)
    XCTAssertEqual(state.historyReloadToken, 0)
    state.select(.my)

    XCTAssertEqual(state.selection, .my)
    XCTAssertEqual(state.historyReloadToken, 0)

    state.select(.routine)

    XCTAssertEqual(state.selection, .routine)
    XCTAssertEqual(state.historyReloadToken, 0)

    state.select(.record)

    XCTAssertEqual(state.selection, .record)
    XCTAssertEqual(state.historyReloadToken, 1)

    state.select(.record)

    XCTAssertEqual(state.selection, .record)
    XCTAssertEqual(state.historyReloadToken, 2)

    let runID = UUID()
    state.showRunDetail(runID)

    XCTAssertEqual(state.selection, .record)
    XCTAssertEqual(state.historyReloadToken, 3)
    XCTAssertEqual(state.historyDestination, .runDetail(runID))

    state.setHistoryDestination(nil)
    state.showHome()

    XCTAssertEqual(state.selection, .home)
    XCTAssertNil(state.historyDestination)
  }

  @MainActor
  func testCoordinatorRoutesRegularSummaryActionsAfterDismissal() {
    let coordinator = AppNavigationCoordinator()
    let runID = UUID()

    guard case .presented(let recordToken) = coordinator.presentRegularRoutine(
      routineID: UUID()
    ) else {
      XCTFail("The regular routine should be presented.")
      return
    }

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.summaryRecord(persistedRunID: runID)),
        presentationToken: recordToken
      ),
      .dismiss(token: recordToken)
    )
    coordinator.presentationBindingDidChange(to: nil)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .showRunDetail(runID))

    guard case .presented(let homeToken) = coordinator.presentRegularRoutine(
      routineID: UUID()
    ) else {
      XCTFail("A second regular routine should be presented.")
      return
    }

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.summaryCTA),
        presentationToken: homeToken
      ),
      .dismiss(token: homeToken)
    )
    coordinator.presentationBindingDidChange(to: nil)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .showHome)
  }
  @MainActor
  func testInstalledHomeLaunchHandlerPresentsExactRoutineAndRefreshesAfterDismissal() {
    let homeBuilder = CapturingHomeFlowBuilder()
    let routinePlayerBuilder = CapturingRoutinePlayerBuilder()
    let state = AppRouterState()
    let (router, coordinator) = makeRouter(
      homeBuilder: homeBuilder,
      routinePlayerBuilder: routinePlayerBuilder,
      state: state
    )
    let routineID = UUID()
    let competingRoutineID = UUID()

    _ = router.mainTabView

    XCTAssertEqual(homeBuilder.refreshTokens, [0])

    guard let launchRoutine = homeBuilder.onStartRoutine else {
      XCTFail("The Home builder should receive the AppRouter launch handler.")
      return
    }

    XCTAssertEqual(
      launchRoutine(RoutineLaunchRequest(routineID: routineID)),
      .started
    )

    guard case .regularRoutine(
      let activeRoutineID,
      let source,
      let token
    ) = coordinator.presentation else {
      XCTFail("The installed Home handler should present the requested regular routine.")
      return
    }

    XCTAssertEqual(activeRoutineID, routineID)
    XCTAssertEqual(source, .manual)
    XCTAssertEqual(
      launchRoutine(RoutineLaunchRequest(routineID: routineID)),
      .alreadyRunning
    )
    XCTAssertEqual(
      launchRoutine(RoutineLaunchRequest(routineID: competingRoutineID)),
      .busy
    )

    _ = router.routinePlayerView(
      for: .regularRoutine(
        routineID: activeRoutineID,
        source: .manual,
        token: token
      )
    )

    XCTAssertEqual(
      routinePlayerBuilder.regularRequests,
      [RegularRoutineExecutionRequest(routineID: routineID, source: .manual)]
    )
    XCTAssertEqual(routinePlayerBuilder.regularPresentationTokens, [token])
    state.selectMainTab(.my)

    let unrelatedToken = UUID()
    XCTAssertNotEqual(unrelatedToken, token)
    routinePlayerBuilder.sendRegularEvent(
      .exitRequested(.summaryCTA),
      presentationToken: unrelatedToken
    )

    XCTAssertEqual(
      coordinator.presentation,
      .regularRoutine(
        routineID: routineID,
        source: .manual,
        token: token
      )
    )

    routinePlayerBuilder.sendRegularEvent(
      .exitRequested(.summaryCTA),
      presentationToken: token
    )

    XCTAssertNil(coordinator.presentation)
    XCTAssertEqual(coordinator.pendingDismissalToken, token)

    router.completePendingDismissal()

    XCTAssertNil(coordinator.pendingDismissalToken)
    XCTAssertEqual(coordinator.navigationState, .idle)
    XCTAssertEqual(state.homeRefreshToken, 1)
    XCTAssertEqual(state.mainTabState.selection, .home)

    _ = router.mainTabView

    XCTAssertEqual(homeBuilder.refreshTokens, [0, 1])
  }

  @MainActor
  func testRouterOpensThePersistedRunAfterRegularSummaryDismissal() {
    let homeBuilder = CapturingHomeFlowBuilder()
    let routinePlayerBuilder = CapturingRoutinePlayerBuilder()
    let state = AppRouterState()
    let (router, coordinator) = makeRouter(
      homeBuilder: homeBuilder,
      routinePlayerBuilder: routinePlayerBuilder,
      state: state
    )
    let routineID = UUID()
    let runID = UUID()

    guard case .presented(let token) = coordinator.presentRegularRoutine(
      routineID: routineID
    ) else {
      XCTFail("The regular routine should be presented.")
      return
    }

    _ = router.routinePlayerView(
      for: .regularRoutine(
        routineID: routineID,
        source: .manual,
        token: token
      )
    )
    routinePlayerBuilder.sendRegularEvent(
      .exitRequested(.summaryRecord(persistedRunID: runID)),
      presentationToken: token
    )

    XCTAssertNil(coordinator.presentation)
    router.completePendingDismissal()

    XCTAssertEqual(state.mainTabState.selection, .record)
    XCTAssertEqual(state.mainTabState.historyDestination, .runDetail(runID))
    XCTAssertEqual(state.mainTabState.historyReloadToken, 1)
  }

  @MainActor
  private func makeRouter(
    homeBuilder: CapturingHomeFlowBuilder,
    routinePlayerBuilder: CapturingRoutinePlayerBuilder,
    state: AppRouterState
  ) -> (AppRouter, AppNavigationCoordinator) {
    let routineRepository = ResolvingRoutineRepository()
    let routineRunRepository = RouterRuntimeRoutineRunRepository()
    let localProfileRepository = RouterRuntimeLocalProfileRepository()
    let dependencies = DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: routineRunRepository,
      localProfileRepository: localProfileRepository,
      onboardingRepository: RouterRuntimeOnboardingRepository(),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
    let coordinator = AppNavigationCoordinator()
    let sessionStore = SessionStore(
      localProfileRepository: localProfileRepository
    )
    let accountSessionStore = AccountSessionStore(
      credentialStore: KeychainCredentialStore(
        service: "com.teammoru.MoruTests.router-runtime"
      ),
      accessTokenProvider: MemoryAccessTokenProvider()
    )

    return (
      AppRouter(
        dependencies: dependencies,
        sessionStore: sessionStore,
        accountSessionStore: accountSessionStore,
        socialLoginCoordinator: UnavailableSocialLoginCoordinator(),
        coordinator: coordinator,
        onboardingBuilder: EmptyOnboardingFlowBuilder(),
        routinePlayerBuilder: routinePlayerBuilder,
        homeBuilder: homeBuilder,
        state: state
      ),
      coordinator
    )
  }


  @MainActor
  func testRegularLaunchBoundaryMapsStartedAndAlreadyRunning() {
    let coordinator = AppNavigationCoordinator()
    let routineID = UUID()

    let firstResult = AppRouter.regularRoutineLaunchResult(
      from: coordinator.presentRegularRoutine(routineID: routineID)
    )

    XCTAssertEqual(firstResult, .started)

    guard case .regularRoutine(
      let activeRoutineID,
      let source,
      let token
    ) = coordinator.presentation else {
      XCTFail("A regular launch should present the requested routine.")
      return
    }

    XCTAssertEqual(activeRoutineID, routineID)
    XCTAssertEqual(source, .manual)
    XCTAssertEqual(
      AppRouter.regularRoutineLaunchResult(
        from: coordinator.presentRegularRoutine(routineID: routineID)
      ),
      .alreadyRunning
    )
    XCTAssertEqual(coordinator.presentation?.id, token)
  }

  @MainActor
  func testRegularLaunchBoundaryMapsDifferentRoutineToBusy() {
    let coordinator = AppNavigationCoordinator()

    XCTAssertEqual(
      AppRouter.regularRoutineLaunchResult(
        from: coordinator.presentRegularRoutine(routineID: UUID())
      ),
      .started
    )
    XCTAssertEqual(
      AppRouter.regularRoutineLaunchResult(
        from: coordinator.presentRegularRoutine(routineID: UUID())
      ),
      .busy
    )
  }

  @MainActor
  func testRouterPreservesScheduledSourceForAlarmLaunchedRoutine() {
    let homeBuilder = CapturingHomeFlowBuilder()
    let routinePlayerBuilder = CapturingRoutinePlayerBuilder()
    let state = AppRouterState()
    let (router, _) = makeRouter(
      homeBuilder: homeBuilder,
      routinePlayerBuilder: routinePlayerBuilder,
      state: state
    )
    let routineID = UUID()
    let token = UUID()

    _ = router.routinePlayerView(
      for: .regularRoutine(
        routineID: routineID,
        source: .scheduled,
        token: token
      )
    )

    XCTAssertEqual(
      routinePlayerBuilder.regularRequests,
      [
        RegularRoutineExecutionRequest(
          routineID: routineID,
          source: .scheduled
        ),
      ]
    )
    XCTAssertEqual(routinePlayerBuilder.regularPresentationTokens, [token])
  }

  @MainActor
  func testRegularDismissalAcknowledgmentReturnsToIdleAndAdmitsNewRegularRoutine() {
    let coordinator = AppNavigationCoordinator()
    let firstRoutineID = UUID()
    let nextRoutineID = UUID()

    guard case .presented(let token) = coordinator.presentRegularRoutine(
      routineID: firstRoutineID
    ) else {
      XCTFail("A regular launch should be accepted.")
      return
    }

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.userDismissed),
        presentationToken: token
      ),
      .dismiss(token: token)
    )
    coordinator.presentationBindingDidChange(to: nil)

    XCTAssertEqual(coordinator.pendingDismissalToken, token)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
    XCTAssertNil(coordinator.pendingDismissalToken)
    XCTAssertEqual(coordinator.navigationState, .idle)

    guard case .presented(let nextToken) = coordinator.presentRegularRoutine(
      routineID: nextRoutineID
    ) else {
      XCTFail("A regular launch should be admitted after dismissal acknowledgment.")
      return
    }

    XCTAssertNotEqual(nextToken, token)
    XCTAssertEqual(
      coordinator.presentation,
      .regularRoutine(
        routineID: nextRoutineID,
        source: .manual,
        token: nextToken
      )
    )
  }

  @MainActor
  func testCoordinatorKeepsArmedDismissalBusyUntilMatchingDismissalCompletes() {
    let coordinator = AppNavigationCoordinator()
    let routineID = UUID()

    guard case .presented(let token) = coordinator.presentOnboardingTrial(
      routineID: routineID
    ) else {
      XCTFail("The trial presentation should be accepted.")
      return
    }

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.endedEarly),
        presentationToken: token
      ),
      .dismiss(token: token)
    )
    XCTAssertEqual(
      coordinator.presentOnboardingTrial(routineID: routineID),
      .alreadyPresented(token)
    )
    XCTAssertEqual(
      coordinator.presentOnboardingTrial(routineID: UUID()),
      .deferredBusy
    )

    coordinator.presentationBindingDidChange(to: nil)

    XCTAssertNil(coordinator.presentation)
    XCTAssertEqual(
      coordinator.presentOnboardingTrial(routineID: UUID()),
      .deferredBusy
    )
  }

  @MainActor
  func testCoordinatorClearsAndAcknowledgesOnlyAnArmedDismissal() {
    let coordinator = AppNavigationCoordinator()
    let routineID = UUID()

    guard case .presented(let token) = coordinator.presentOnboardingTrial(
      routineID: routineID
    ) else {
      XCTFail("The trial presentation should be accepted.")
      return
    }

    let expectedState = AppNavigationState.presented(
      .onboardingTrial(routineID: routineID, token: token)
    )

    coordinator.presentationBindingDidChange(to: nil)

    XCTAssertEqual(coordinator.navigationState, expectedState)

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.userDismissed),
        presentationToken: token
      ),
      .dismiss(token: token)
    )
    XCTAssertEqual(coordinator.pendingDismissalToken, token)

    coordinator.presentationBindingDidChange(to: nil)

    XCTAssertEqual(coordinator.presentationDidDismiss(), .enterAccountEntry)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
    XCTAssertEqual(coordinator.navigationState, .idle)
  }

  @MainActor
  func testCoordinatorEntersAccountEntryOnceAfterTrialDismissal() {
    let coordinator = AppNavigationCoordinator()

    guard case .presented(let token) = coordinator.presentOnboardingTrial(routineID: UUID()) else {
      XCTFail("The trial presentation should be accepted.")
      return
    }

    XCTAssertEqual(
      coordinator.handle(
        event: .exitRequested(.summaryCTA),
        presentationToken: token
      ),
      .dismiss(token: token)
    )
    coordinator.presentationBindingDidChange(to: nil)

    XCTAssertEqual(coordinator.presentationDidDismiss(), .enterAccountEntry)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
  }

  @MainActor
  func testCoordinatorBeginsInitialSessionLoadOnlyOnce() {
    let coordinator = AppNavigationCoordinator()

    XCTAssertTrue(coordinator.beginInitialSessionLoadIfNeeded())
    XCTAssertFalse(coordinator.beginInitialSessionLoadIfNeeded())
  }

  @MainActor
  func testOnboardingEmitsExactSavedRoutineIDOnceAndFailureEmitsNone() async {
    let savedRoutine = makeExecutableRoutine()
    let successfulUseCase = OnboardingCompletionUseCaseSpy(
      outcome: .success(
        CompleteOnboardingResult(
          profile: LocalProfile(),
          routine: savedRoutine
        )
      )
    )
    var emittedRoutineIDs: [UUID] = []
    let successfulViewModel = OnboardingViewModel(
      step: .completion,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: successfulUseCase
    ) { routineID in
      emittedRoutineIDs.append(routineID)
    }

    await successfulViewModel.completeButtonDidTap()
    await successfulViewModel.completeButtonDidTap()

    XCTAssertEqual(successfulUseCase.executeCallCount, 1)
    XCTAssertEqual(emittedRoutineIDs, [savedRoutine.id])

    let failingUseCase = OnboardingCompletionUseCaseSpy(outcome: .failure(.onboardingFailed))
    var failedEmissionRoutineIDs: [UUID] = []
    let failingViewModel = OnboardingViewModel(
      step: .completion,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: failingUseCase
    ) { routineID in
      failedEmissionRoutineIDs.append(routineID)
    }

    await failingViewModel.completeButtonDidTap()

    XCTAssertEqual(failingUseCase.executeCallCount, 1)
    XCTAssertTrue(failedEmissionRoutineIDs.isEmpty)
    XCTAssertNotNil(failingViewModel.errorMessage)
  }

  @MainActor
  func testCompletionSummaryRejectsCompletionBeforeStart() {
    let routine = makeExecutableRoutine()
    let startedAt = Date()
    let completedAt = startedAt.addingTimeInterval(-1)

    let result = makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: [],
      endedEarly: false
    )

    XCTAssertEqual(result, .failure(.completedBeforeStarted))
  }

  @MainActor
  func testEmptyRoutineTransitionsToNoExecutableStepsTerminalBeforeRunning() {
    let routine = makeExecutableRoutine(steps: [])
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let finalizer = TrialRoutineFinalizerSpy()
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()

    guard case .terminalFailure(.ineligible(.noExecutableSteps)) = viewModel.screenState else {
      XCTFail("An empty routine should never enter the running state.")
      return
    }

    XCTAssertEqual(finalizer.finalizeCallCount, 0)
    XCTAssertEqual(
      eventRecorder.events,
      [.terminalFailureDisplayed(.ineligible(.noExecutableSteps))]
    )
  }

  @MainActor
  func testPlayerPresentsOnlyOneDialogAndPreservesTheFirstExitIntent() {
    let routine = makeExecutableRoutine()
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let finalizer = TrialRoutineFinalizerSpy()
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.requestSkipStep()
    viewModel.requestEndRoutine()
    viewModel.requestCloseRoutine()

    XCTAssertEqual(viewModel.dialogState, .skipStep)

    viewModel.cancelActiveDialog()
    viewModel.requestEndRoutine()
    viewModel.requestCloseRoutine()

    XCTAssertEqual(viewModel.dialogState, .exit(.endedEarly))

    viewModel.confirmActiveDialog()

    XCTAssertEqual(eventRecorder.events, [.exitRequested(.endedEarly)])
  }

  @MainActor
  func testTimerCompletionDuringDialogAppliesOnceWhenDialogIsCancelled() {
    let step = RoutineStep(
      type: .timer,
      title: "타이머",
      order: 0,
      estimatedSeconds: 1
    )
    let routine = makeExecutableRoutine(steps: [step])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: RoutineExecutionResolverSpy(resolution: .available(routine)),
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    viewModel.requestSkipStep()
    viewModel.completeCurrentStep()
    viewModel.completeCurrentStep()

    XCTAssertTrue(viewModel.stepResults.isEmpty)
    guard case .running = viewModel.screenState else {
      XCTFail("The timer completion must stay pending while the dialog is visible.")
      return
    }

    viewModel.cancelActiveDialog()
    viewModel.cancelActiveDialog()

    XCTAssertEqual(viewModel.stepResults.count, 1)
    XCTAssertTrue(viewModel.stepResults[0].isCompleted)
    guard case .stepCompleted(let completedStep) = viewModel.screenState else {
      XCTFail("Cancelling the dialog must apply the pending timer completion.")
      return
    }
    XCTAssertEqual(completedStep.id, step.id)
  }

  @MainActor
  func testConfirmCompletionDuringDialogPreservesTranscriptOnCancel() {
    let routine = makeExecutableRoutine()
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: RoutineExecutionResolverSpy(resolution: .available(routine)),
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    viewModel.requestCloseRoutine()
    viewModel.completeCurrentStep(transcript: "완료했어요")
    viewModel.cancelActiveDialog()

    XCTAssertEqual(viewModel.stepResults.count, 1)
    XCTAssertEqual(viewModel.stepResults[0].transcript, "완료했어요")
    XCTAssertTrue(viewModel.stepResults[0].isCompleted)
  }

  @MainActor
  func testSpeechCompletionDuringSkipDialogIsDiscardedWhenSkipIsConfirmed() {
    let step = RoutineStep(
      type: .input,
      title: "다짐",
      order: 0
    )
    let routine = makeExecutableRoutine(steps: [step])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: RoutineExecutionResolverSpy(resolution: .available(routine)),
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    viewModel.requestSkipStep()
    viewModel.completeCurrentStep(
      inputText: "차분하게 시작할게요",
      transcript: "차분하게 시작할게요"
    )
    viewModel.confirmActiveDialog()

    XCTAssertEqual(viewModel.stepResults.count, 1)
    XCTAssertTrue(viewModel.stepResults[0].skipped)
    XCTAssertNil(viewModel.stepResults[0].transcript)
  }

  @MainActor
  func testSpeechCompletionDuringExitDialogIsDiscardedWhenExitIsConfirmed() {
    let routine = makeExecutableRoutine()
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: RoutineExecutionResolverSpy(resolution: .available(routine)),
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.requestEndRoutine()
    viewModel.completeCurrentStep(transcript: "완료했어요")
    viewModel.confirmActiveDialog()

    XCTAssertTrue(viewModel.stepResults.isEmpty)
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.endedEarly)])
  }

  @MainActor
  func testTrialNaturalCompletionDoesNotPersistARoutineRun() {
    let routine = makeExecutableRoutine()
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let finalizer = TrialRoutineFinalizerSpy()
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("A completed trial should show a summary.")
      return
    }

    XCTAssertNil(summary.persistedRunID)
    XCTAssertNil(summary.streak)
    XCTAssertFalse(summary.endedEarly)
    XCTAssertEqual(finalizer.finalizeCallCount, 1)
    XCTAssertEqual(finalizer.finalizedRoutineIDs, [routine.id])
    XCTAssertEqual(finalizer.finalizedResultCounts, [1])
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])
  }

  @MainActor
  func testTrialEndAndCloseDoNotFinalizeOrPersistARoutineRun() {
    for exit in [RoutinePlayerExit.endedEarly, .userDismissed] {
      let routine = makeExecutableRoutine()
      let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
      let finalizer = TrialRoutineFinalizerSpy()
      let eventRecorder = RoutinePlayerEventRecorder()
      let viewModel = RoutinePlayerViewModel(
        request: TrialRoutineExecutionRequest(routineID: routine.id),
        resolver: resolver,
        finalizer: finalizer,
        presentationToken: UUID()
      ) { token, event in
        eventRecorder.record(presentationToken: token, event: event)
      }

      viewModel.resolveRoutine()
      requestEarlyExit(exit, from: viewModel)
      viewModel.confirmActiveDialog()

      XCTAssertEqual(finalizer.finalizeCallCount, 0)
      XCTAssertTrue(finalizer.finalizedRoutineIDs.isEmpty)
      XCTAssertEqual(eventRecorder.events, [.exitRequested(exit)])
    }
  }

  @MainActor
  func testRegularNaturalCompletionSavesRunAndEmitsOneCompletionEvent() {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy()
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("A completed regular routine should show a summary.")
      return
    }

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(saver.requests.first?.endedEarly, false)
    XCTAssertEqual(summary.persistedRunID, saver.savedRuns.first?.id)
    XCTAssertFalse(summary.endedEarly)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])

    guard let persistedRunID = summary.persistedRunID else {
      XCTFail("A regular completion must retain its saved run ID.")
      return
    }

    viewModel.requestSummaryRecord()

    viewModel.finishStepCompletedScreen()
    viewModel.retrySavingRun()
    viewModel.requestSummaryRecord()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(
      eventRecorder.events,
      [
        .completionDisplayed(summary),
        .exitRequested(.summaryRecord(persistedRunID: persistedRunID)),
      ]
    )
  }

  @MainActor
  func testRegularNaturalCompletionRetryUsesSameRequestAndEmitsOneCompletionEvent() {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy(failuresRemaining: 1)
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertTrue(saver.savedRuns.isEmpty)
    XCTAssertNotNil(viewModel.errorMessage)
    XCTAssertTrue(eventRecorder.events.isEmpty)

    viewModel.retrySavingRun()

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("A successful retry should show a summary.")
      return
    }

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(saver.requests[0], saver.requests[1])
    XCTAssertEqual(summary.persistedRunID, saver.savedRuns.first?.id)
    XCTAssertFalse(summary.endedEarly)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])

    viewModel.retrySavingRun()

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])
  }

  @MainActor
  func testRegularEndSavesCurrentResultsAndDisplaysSummary() {
    let routine = makeExecutableRoutine(steps: [
      RoutineStep(type: .confirm, title: "완료", order: 0),
      RoutineStep(type: .timer, title: "건너뜀", order: 1),
      RoutineStep(type: .input, title: "미실행", order: 2),
    ])
    let saver = RoutineRunSaverSpy()
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()
    viewModel.skipCurrentStep()
    viewModel.requestEndRoutine()
    viewModel.confirmActiveDialog()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(saver.requests.first?.endedEarly, true)
    XCTAssertEqual(saver.requests.first?.results.count, 2)
    XCTAssertTrue(saver.requests.first?.results[0].isCompleted == true)
    XCTAssertTrue(saver.requests.first?.results[1].skipped == true)

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("Ending a routine should display its saved summary.")
      return
    }

    XCTAssertTrue(summary.endedEarly)
    XCTAssertEqual(summary.completedStepCount, 1)
    XCTAssertEqual(summary.skippedStepCount, 1)
    XCTAssertEqual(summary.completionRate, 1.0 / 3.0, accuracy: 0.001)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])
  }

  @MainActor
  func testRegularCloseSavesBeforeEmittingExit() {
    let routine = makeExecutableRoutine()
    var operationOrder: [String] = []
    let saver = RoutineRunSaverSpy {
      operationOrder.append("save")
    }
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder { event in
      if case .exitRequested = event {
        operationOrder.append("exit")
      }
    }
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.requestCloseRoutine()
    viewModel.confirmActiveDialog()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(saver.requests.first?.endedEarly, true)
    XCTAssertEqual(saver.savedRuns.count, 1)
    XCTAssertEqual(operationOrder, ["save", "exit"])
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.userDismissed)])
  }

  @MainActor
  func testRegularEndRetryUsesSameRequestAndDisplaysSummaryOnce() {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy(failuresRemaining: 1)
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.requestEndRoutine()
    viewModel.confirmActiveDialog()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertNotNil(viewModel.errorMessage)
    XCTAssertTrue(eventRecorder.events.isEmpty)

    viewModel.retrySavingRun()

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("A successful retry should display the early summary.")
      return
    }

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(saver.requests[0], saver.requests[1])
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])

    viewModel.retrySavingRun()
    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])
  }

  @MainActor
  func testRegularCloseRetryUsesSameRequestAndEmitsExitOnce() {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy(failuresRemaining: 1)
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.requestCloseRoutine()
    viewModel.confirmActiveDialog()
    viewModel.retrySavingRun()

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(saver.requests[0], saver.requests[1])
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.userDismissed)])

    viewModel.retrySavingRun()
    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.userDismissed)])
  }

  @MainActor
  private func requestEarlyExit(
    _ exit: RoutinePlayerExit,
    from viewModel: RoutinePlayerViewModel
  ) {
    switch exit {
    case .endedEarly:
      viewModel.requestEndRoutine()

    case .userDismissed:
      viewModel.requestCloseRoutine()

    case .summaryCTA, .summaryRecord, .terminalUnavailable, .discardedUnsavedRun:
      XCTFail("Only early exit reasons are valid for this helper.")
    }
  }

  // MARK: - 완료 요약 정합성

  @MainActor
  func testSummaryListsEveryPlannedStepAndKeepsUnreachedOnesOutOfTheSavedRecord() {
    let routine = makeExecutableRoutine(
      steps: [
        RoutineStep(type: .confirm, title: "첫째", order: 0),
        RoutineStep(type: .timer, title: "둘째", order: 1),
        RoutineStep(type: .input, title: "셋째", order: 2),
      ]
    )
    let saver = RoutineRunSaverSpy()
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { _, _ in }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep(transcript: "완료했어요")
    viewModel.finishStepCompletedScreen()
    viewModel.requestSkipStep()
    viewModel.confirmActiveDialog()
    viewModel.requestEndRoutine()
    viewModel.confirmActiveDialog()

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("Ending early should display the summary.")
      return
    }

    // 저장되는 결과는 완료·건너뜀 2건뿐이다.
    XCTAssertEqual(saver.requests.first?.results.count, 2)
    XCTAssertEqual(summary.totalStepCount, 3)
    XCTAssertEqual(summary.completedStepCount, 1)
    XCTAssertEqual(summary.skippedStepCount, 1)

    // 요약은 계획된 3단계를 순서대로 보여 주고 셋째는 미완료다.
    let displayed = viewModel.summaryStepResults
    XCTAssertEqual(displayed.map(\.stepTitle), ["첫째", "둘째", "셋째"])
    XCTAssertTrue(displayed[0].isCompleted)
    XCTAssertTrue(displayed[1].skipped)
    XCTAssertFalse(displayed[2].isCompleted)
    XCTAssertFalse(displayed[2].skipped)
    XCTAssertEqual(
      displayed.map(RoutineFinishedView.statusSymbolName(for:)),
      ["checkmark", "xmark", "minus"]
    )
    XCTAssertEqual(
      displayed.map(RoutineFinishedView.statusLabel(for:)),
      ["완료", "건너뜀", "미완료"]
    )
  }

  // MARK: - 저장 실패 시 종료 의도

  @MainActor
  private func makeRegularViewModelWithFailingSave(
    failuresRemaining: Int = 1
  ) -> (RoutinePlayerViewModel, RoutineRunSaverSpy, RoutinePlayerEventRecorder) {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy(failuresRemaining: failuresRemaining)
    let finalizer = SavingRegularRoutineFinalizer(saver: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: UUID()
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    return (viewModel, saver, eventRecorder)
  }

  @MainActor
  func testNaturalCompletionSaveFailureStillLetsTheUserLeaveWithoutARecord() {
    let (viewModel, saver, eventRecorder) = makeRegularViewModelWithFailingSave()

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    XCTAssertNotNil(viewModel.errorMessage)
    XCTAssertTrue(viewModel.hasUnsavedRun)
    XCTAssertTrue(viewModel.isStepInteractionDisabled)

    // 자연 완료 저장 실패는 화면이 .stepCompleted에 머물지만 종료 의도는 통과해야 한다.
    viewModel.requestCloseRoutine()
    XCTAssertEqual(viewModel.dialogState, .discardUnsavedRun)

    viewModel.confirmActiveDialog()

    XCTAssertNil(viewModel.dialogState)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertFalse(viewModel.hasUnsavedRun)
    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertTrue(saver.savedRuns.isEmpty)
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.discardedUnsavedRun)])

    // 나간 뒤의 재시도·재종료는 아무것도 하지 않는다.
    viewModel.retrySavingRun()
    viewModel.requestEndRoutine()
    viewModel.confirmActiveDialog()
    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.discardedUnsavedRun)])
  }

  @MainActor
  func testDiscardDialogCancelKeepsTheSameRequestRetryable() {
    let (viewModel, saver, eventRecorder) = makeRegularViewModelWithFailingSave()

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    viewModel.requestDiscardUnsavedRun()
    XCTAssertEqual(viewModel.dialogState, .discardUnsavedRun)

    viewModel.cancelActiveDialog()
    XCTAssertNil(viewModel.dialogState)
    XCTAssertTrue(viewModel.hasUnsavedRun)
    XCTAssertTrue(eventRecorder.events.isEmpty)

    viewModel.retrySavingRun()

    guard case .summary(let summary) = viewModel.screenState else {
      XCTFail("A successful retry after cancelling the discard dialog should show a summary.")
      return
    }

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(saver.requests[0], saver.requests[1])
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])
  }

  @MainActor
  func testCloseSaveFailureRoutesTopBarEndIntoTheDiscardDialog() {
    let (viewModel, saver, eventRecorder) = makeRegularViewModelWithFailingSave()

    viewModel.resolveRoutine()
    viewModel.requestCloseRoutine()
    viewModel.confirmActiveDialog()

    XCTAssertNotNil(viewModel.errorMessage)
    XCTAssertEqual(saver.requests.count, 1)

    // 저장 대기 중에는 종료 버튼도 종료 다이얼로그가 아니라 기록 없이 나가기를 묻는다.
    viewModel.requestEndRoutine()
    XCTAssertEqual(viewModel.dialogState, .discardUnsavedRun)

    // 다이얼로그가 떠 있는 동안 도착한 단계 완료는 저장 대기 중이라 무시된다.
    viewModel.completeCurrentStep()
    XCTAssertTrue(viewModel.stepResults.isEmpty)

    viewModel.confirmActiveDialog()
    XCTAssertEqual(eventRecorder.events, [.exitRequested(.discardedUnsavedRun)])
    XCTAssertEqual(saver.requests.count, 1)
  }

  @MainActor
  func testDiscardRequestIsIgnoredWithoutAnUnsavedRun() {
    let (viewModel, saver, eventRecorder) = makeRegularViewModelWithFailingSave(
      failuresRemaining: 0
    )

    viewModel.resolveRoutine()
    viewModel.requestDiscardUnsavedRun()
    XCTAssertNil(viewModel.dialogState)

    // 저장 대기가 없으면 종료는 기존 종료 다이얼로그 그대로다.
    viewModel.requestEndRoutine()
    XCTAssertEqual(viewModel.dialogState, .exit(.endedEarly))
    viewModel.confirmActiveDialog()

    guard case .summary = viewModel.screenState else {
      XCTFail("An early end without a save failure should show the summary.")
      return
    }
    XCTAssertEqual(saver.savedRuns.count, 1)
    XCTAssertEqual(eventRecorder.events.count, 1)
  }
}

@MainActor
private func makeExecutableRoutine(
  id: UUID = UUID(),
  isActive: Bool = true,
  alarmEnabled: Bool = true,
  steps: [RoutineStep]? = nil
) -> Routine {
  Routine(
    id: id,
    name: "테스트 루틴",
    steps: steps ?? [
      RoutineStep(
        type: .confirm,
        title: "확인",
        order: 0
      )
    ],
    alarmSchedule: AlarmSchedule(
      hour: 7,
      minute: 0,
      weekdays: [.monday],
      isEnabled: alarmEnabled
    ),
    isActive: isActive
  )
}

private enum RouterRuntimeContractTestError: Error {
  case repositoryUnavailable
  case onboardingFailed
  case saveFailed
}

@MainActor
private final class ResolvingRoutineRepository: RoutineRepository {
  var routine: Routine?
  var shouldThrowWhenResolving = false

  func fetchRoutines() throws -> [Routine] {
    routine.map { [$0] } ?? []
  }

  func fetchActiveRoutines() throws -> [Routine] {
    try fetchRoutines().filter(\.isActive)
  }

  func routine(id: UUID) throws -> Routine? {
    guard !shouldThrowWhenResolving else {
      throw RouterRuntimeContractTestError.repositoryUnavailable
    }

    guard routine?.id == id else {
      return nil
    }

    return routine
  }

  func saveRoutine(_ routine: Routine) throws {
    self.routine = routine
  }

  func saveRoutines(_ routines: [Routine]) throws {
    for routine in routines {
      try saveRoutine(routine)
    }
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routine(id: id) else {
      return
    }

    routine.isActive = isActive
    try saveRoutine(routine)
  }

  func deleteRoutine(id: UUID) throws {
    guard routine?.id == id else {
      return
    }

    routine = nil
  }
}

@MainActor
private final class OnboardingCompletionUseCaseSpy: CompleteOnboardingUseCaseProtocol {
  private let outcome: Result<CompleteOnboardingResult, RouterRuntimeContractTestError>

  private(set) var executeCallCount = 0

  init(outcome: Result<CompleteOnboardingResult, RouterRuntimeContractTestError>) {
    self.outcome = outcome
  }

  func execute(
    _ request: CompleteOnboardingRequest
  ) async throws -> CompleteOnboardingResult {
    executeCallCount += 1
    return try outcome.get()
  }
}

@MainActor
private final class RoutineExecutionResolverSpy: ResolveRoutineExecutionUseCaseProtocol {
  private let resolution: RoutineExecutionResolution

  private(set) var requests: [ResolveRoutineExecutionRequest] = []

  init(resolution: RoutineExecutionResolution) {
    self.resolution = resolution
  }

  func execute(
    _ request: ResolveRoutineExecutionRequest
  ) -> RoutineExecutionResolution {
    requests.append(request)
    return resolution
  }
}

@MainActor
private final class TrialRoutineFinalizerSpy: TrialRoutineFinalizing {
  private(set) var finalizeCallCount = 0
  private(set) var finalizedRoutineIDs: [UUID] = []
  private(set) var finalizedResultCounts: [Int] = []

  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
    finalizeCallCount += 1
    finalizedRoutineIDs.append(routine.id)
    finalizedResultCounts.append(results.count)

    return makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      endedEarly: false
    )
  }
}

@MainActor
private final class RoutineRunSaverSpy: SaveRoutineRunUseCaseProtocol {
  private var failuresRemaining: Int
  private let onExecute: @MainActor () -> Void

  private(set) var requests: [SaveRoutineRunRequest] = []
  private(set) var savedRuns: [RoutineRun] = []

  init(
    failuresRemaining: Int = 0,
    onExecute: @escaping @MainActor () -> Void = {}
  ) {
    self.failuresRemaining = failuresRemaining
    self.onExecute = onExecute
  }

  @discardableResult
  func execute(_ request: SaveRoutineRunRequest) throws -> RoutineRun {
    onExecute()
    requests.append(request)

    guard failuresRemaining == 0 else {
      failuresRemaining -= 1
      throw RouterRuntimeContractTestError.saveFailed
    }

    let run = RoutineRun(
      id: request.runID,
      routine: request.routine,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    )
    savedRuns.append(run)
    return run
  }
}

@MainActor
private final class SavingRegularRoutineFinalizer: RegularRoutineFinalizing {
  private let saver: RoutineRunSaverSpy

  init(saver: RoutineRunSaverSpy) {
    self.saver = saver
  }

  func finalize(_ request: SaveRoutineRunRequest) throws -> RoutineCompletionSummary {
    let run = try saver.execute(request)

    return try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: run.id,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    ).get()
  }
}

@MainActor
private final class RoutinePlayerEventRecorder {
  private let onRecord: @MainActor (RoutinePlayerEvent) -> Void

  private(set) var events: [RoutinePlayerEvent] = []
  private(set) var presentationTokens: [UUID] = []

  init(onRecord: @escaping @MainActor (RoutinePlayerEvent) -> Void = { _ in }) {
    self.onRecord = onRecord
  }

  func record(presentationToken: UUID, event: RoutinePlayerEvent) {
    presentationTokens.append(presentationToken)
    events.append(event)
    onRecord(event)
  }
}

@MainActor
private final class CapturingHomeFlowBuilder: HomeFlowBuilding {
  private(set) var refreshTokens: [Int] = []
  private(set) var onStartRoutine: RoutineLaunchHandler?
  private(set) var onOpenRoutineSettings: ((UUID?) -> Void)?

  func make(
    onStartRoutine: @escaping RoutineLaunchHandler,
    onOpenRoutineSettings: @escaping (UUID?) -> Void,
    refreshToken: Int
  ) -> AnyView {
    self.onStartRoutine = onStartRoutine
    self.onOpenRoutineSettings = onOpenRoutineSettings
    refreshTokens.append(refreshToken)
    return AnyView(EmptyView())
  }
}

@MainActor
private final class CapturingRoutinePlayerBuilder: RoutinePlayerBuilding {
  private(set) var regularRequests: [RegularRoutineExecutionRequest] = []
  private(set) var regularPresentationTokens: [UUID] = []
  private var regularOnEvent: RoutinePlayerEventHandler?

  func makeTrial(
    request: TrialRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView {
    AnyView(EmptyView())
  }

  func makeRegular(
    request: RegularRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView {
    regularRequests.append(request)
    regularPresentationTokens.append(presentationToken)
    regularOnEvent = onEvent
    return AnyView(EmptyView())
  }

  func sendRegularEvent(
    _ event: RoutinePlayerEvent,
    presentationToken: UUID
  ) {
    regularOnEvent?(presentationToken, event)
  }
}

@MainActor
private final class EmptyOnboardingFlowBuilder: OnboardingFlowBuilding {
  func make(onCompleted: @escaping OnboardingCompletionHandler) -> AnyView {
    AnyView(EmptyView())
  }
}

@MainActor
private final class RouterRuntimeRoutineRunRepository: RoutineRunRepository {
  func fetchRuns() throws -> [RoutineRun] {
    []
  }

  func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
    []
  }

  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    []
  }

  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun] {
    []
  }

  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun] {
    []
  }

  func latestRun(for routineID: UUID) throws -> RoutineRun? {
    nil
  }

  func run(id: UUID) throws -> RoutineRun? {
    nil
  }

  func saveRun(_ run: RoutineRun) throws {}

  func deleteAllRuns() throws {}
}

@MainActor
private final class RouterRuntimeLocalProfileRepository: LocalProfileRepository {
  private var profile: LocalProfile?

  func fetchProfile() throws -> LocalProfile? {
    profile
  }

  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile {
      return profile
    }

    let profile = LocalProfile()
    self.profile = profile
    return profile
  }

  func saveProfile(_ profile: LocalProfile) throws {
    self.profile = profile
  }

  func deleteProfile() throws {
    profile = nil
  }
}

@MainActor
private final class RouterRuntimeOnboardingRepository: OnboardingRepository {
  func fetchProfile() throws -> LocalProfile? {
    nil
  }

  func saveCompletion(profile: LocalProfile, routine: Routine) throws {}
}
