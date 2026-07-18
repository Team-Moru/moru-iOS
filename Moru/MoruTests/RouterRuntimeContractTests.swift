//
//  RouterRuntimeContractTests.swift
//  MoruTests
//
//  Created by Codex on 7/13/26.
//

import Foundation
import SwiftUI
import UIKit
import XCTest
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
  func testInvalidTimerDurationsAreIneligibleBeforeThePlayerCanCreateResults() {
    let invalidDurations: [Int?] = [nil, 0, -1]

    for duration in invalidDurations {
      let timerStep = RoutineStep(
        type: .timer,
        title: "타이머",
        order: 0,
        estimatedSeconds: duration
      )
      let routine = makeExecutableRoutine(steps: [timerStep])
      let repository = ResolvingRoutineRepository()
      repository.routine = routine
      let resolver = ResolveRoutineExecutionUseCase(routineRepository: repository)
      let request = ResolveRoutineExecutionRequest(routineID: routine.id, launch: .trial)
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

      XCTAssertEqual(
        resolver.execute(request),
        .ineligible(.invalidTimerDuration),
        "Duration \(String(describing: duration)) must be ineligible."
      )

      viewModel.resolveRoutine()
      viewModel.completeCurrentStep()
      viewModel.skipCurrentStep()

      guard case .terminalFailure(
        .ineligible(.invalidTimerDuration)
      ) = viewModel.screenState else {
        XCTFail("Invalid timer durations must be rejected before running.")
        continue
      }

      XCTAssertTrue(viewModel.stepResults.isEmpty)
      XCTAssertEqual(finalizer.finalizeCallCount, 0)
      XCTAssertEqual(
        eventRecorder.events,
        [.terminalFailureDisplayed(.ineligible(.invalidTimerDuration))]
      )
    }
  }

  @MainActor
  func testPositiveTimerDurationRemainsEligibleAndCreatesItsResult() {
    let timerStep = RoutineStep(
      type: .timer,
      title: "타이머",
      order: 0,
      estimatedSeconds: 30
    )
    let routine = makeExecutableRoutine(steps: [timerStep])
    let repository = ResolvingRoutineRepository()
    repository.routine = routine
    let resolver = ResolveRoutineExecutionUseCase(routineRepository: repository)
    let request = ResolveRoutineExecutionRequest(routineID: routine.id, launch: .trial)
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: resolver,
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    XCTAssertEqual(resolver.execute(request), .available(routine))

    viewModel.resolveRoutine()

    guard case .running(let runningStep) = viewModel.screenState else {
      XCTFail("A positive timer duration should enter the running state.")
      return
    }

    XCTAssertEqual(runningStep.id, timerStep.id)

    viewModel.completeCurrentStep()

    XCTAssertEqual(viewModel.stepResults.count, 1)
    XCTAssertEqual(viewModel.stepResults.first?.durationSeconds, 30)
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
  }
  @MainActor
  func testInstalledHomeLaunchHandlerPresentsExactRoutineAndRefreshesAfterDismissal() {
    let homeBuilder = CapturingHomeFlowBuilder()
    let routinePlayerBuilder = CapturingRoutinePlayerBuilder()
    let reloadRecorder = RouterReloadRecorder()
    let state = AppRouterState()
    let (router, coordinator, _) = makeRouter(
      homeBuilder: homeBuilder,
      routinePlayerBuilder: routinePlayerBuilder,
      state: state,
      requestSessionReload: reloadRecorder.request,
      retrySessionReload: reloadRecorder.retry
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

    guard case .regularRoutine(let activeRoutineID, let token) = coordinator.presentation else {
      XCTFail("The installed Home handler should present the requested regular routine.")
      return
    }

    XCTAssertEqual(activeRoutineID, routineID)
    XCTAssertEqual(
      launchRoutine(RoutineLaunchRequest(routineID: routineID)),
      .alreadyRunning
    )
    XCTAssertEqual(
      launchRoutine(RoutineLaunchRequest(routineID: competingRoutineID)),
      .busy
    )

    _ = router.routinePlayerView(
      for: .regularRoutine(routineID: activeRoutineID, token: token)
    )

    XCTAssertEqual(
      routinePlayerBuilder.regularRequests,
      [RegularRoutineExecutionRequest(routineID: routineID, source: .manual)]
    )
    XCTAssertEqual(routinePlayerBuilder.regularPresentationTokens, [token])

    let unrelatedToken = UUID()
    let persistedRunID = UUID()
    routinePlayerBuilder.sendRegularEvent(
      .exitRequested(.summaryRecord(persistedRunID: persistedRunID)),
      presentationToken: unrelatedToken
    )

    XCTAssertEqual(
      coordinator.presentation,
      .regularRoutine(routineID: routineID, token: token)
    )

    routinePlayerBuilder.sendRegularEvent(
      .exitRequested(.summaryRecord(persistedRunID: persistedRunID)),
      presentationToken: token
    )

    XCTAssertNil(coordinator.presentation)
    XCTAssertEqual(coordinator.pendingDismissalToken, token)

    router.completePendingDismissal()

    XCTAssertNil(coordinator.pendingDismissalToken)
    XCTAssertEqual(coordinator.navigationState, .idle)
    XCTAssertEqual(state.homeRefreshToken, 1)

    _ = router.mainTabView

    XCTAssertEqual(homeBuilder.refreshTokens, [0, 1])
    XCTAssertTrue(reloadRecorder.requestedSources.isEmpty)
  }

  @MainActor
  func testNonterminalAndCorruptResetJournalBlockRegularLaunch() throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "RouterResetLaunchGuard-\(UUID().uuidString)",
      isDirectory: true
    )
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    let journalURL = directoryURL.appendingPathComponent("journal.json", isDirectory: false)
    let journalStore = LocalResetJournalStore(fileURL: journalURL)
    _ = try journalStore.begin(operationID: UUID(), at: Date())
    let homeBuilder = CapturingHomeFlowBuilder()
    let (router, coordinator, _) = makeRouter(
      homeBuilder: homeBuilder,
      routinePlayerBuilder: CapturingRoutinePlayerBuilder(),
      state: AppRouterState(),
      localResetJournalStore: journalStore
    )

    _ = router.mainTabView
    let launchRoutine = try XCTUnwrap(homeBuilder.onStartRoutine)
    let request = RoutineLaunchRequest(routineID: UUID())

    XCTAssertEqual(launchRoutine(request), .busy)
    XCTAssertNil(coordinator.presentation)

    try Data("corrupt".utf8).write(to: journalURL, options: .atomic)

    XCTAssertEqual(launchRoutine(request), .busy)
    XCTAssertNil(coordinator.presentation)
  }
  @MainActor
  func testResetRemainsBusyUntilTheMatchingReloadAcknowledges() async throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "RouterRuntimeContractTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    let journalStore = LocalResetJournalStore(
      fileURL: directoryURL.appendingPathComponent("journal.json", isDirectory: false)
    )
    let reloadRecorder = RouterAsyncReloadRecorder()
    let state = AppRouterState()
    let (router, _, _) = makeRouter(
      homeBuilder: CapturingHomeFlowBuilder(),
      routinePlayerBuilder: CapturingRoutinePlayerBuilder(),
      state: state,
      awaitSessionReload: reloadRecorder.awaitReload,
      localResetRepository: RouterResetDataRepository(),
      localResetJournalStore: journalStore
    )
    state.selectMainTab(.record)
    let performer = router.makeProfileLocalResetPerformer()
    let reset = Task { @MainActor () -> Result<Void, Error> in
      do {
        try await performer.reset()
        return .success(())
      } catch {
        return .failure(error)
      }
    }

    await waitUntil("Reset should request an exact-source reload after navigation clears.") {
      !reloadRecorder.sources.isEmpty
    }
    guard case .reset(let operationID) = try XCTUnwrap(reloadRecorder.sources.first) else {
      return XCTFail("Reset should await a reset reload source.")
    }
    XCTAssertTrue(state.isLocalResetInProgress)
    XCTAssertEqual(state.mainTabState, MainTabState())

    XCTAssertTrue(reloadRecorder.succeedNext())
    _ = try await reset.value.get()
    XCTAssertEqual(try journalStore.load()?.operationID, operationID)
    await waitUntil("Reset should finish after its matching reload acknowledgement.") {
      !state.isLocalResetInProgress
    }
  }

  @MainActor
  func testRepeatedAlarmRepairRetriesUseOneAdmissionUntilReloadCompletes() async {
    let reloadRecorder = RouterAsyncReloadRecorder()
    let state = AppRouterState()
    let (router, _, _) = makeRouter(
      homeBuilder: CapturingHomeFlowBuilder(),
      routinePlayerBuilder: CapturingRoutinePlayerBuilder(),
      state: state,
      awaitSessionReload: reloadRecorder.awaitReload
    )

    router.retryAlarmRepair()
    router.retryAlarmRepair()

    await waitUntil("Only the first repair retry should reach its reload acknowledgement.") {
      reloadRecorder.sources.count == 1
    }
    XCTAssertTrue(state.isAlarmRepairRetryInProgress)
    guard case .some(.routineMutation) = reloadRecorder.sources.first else {
      return XCTFail("Repair retry should await its exact routine-mutation reload.")
    }

    XCTAssertTrue(reloadRecorder.succeedNext())
    await waitUntil("Repair admission should finish after the reload outcome.") {
      !state.isAlarmRepairRetryInProgress
    }
    XCTAssertEqual(reloadRecorder.sources.count, 1)
  }

  @MainActor
  private func makeRouter(
    homeBuilder: CapturingHomeFlowBuilder,
    routinePlayerBuilder: CapturingRoutinePlayerBuilder,
    state: AppRouterState,
    requestSessionReload: @escaping @MainActor (SessionReloadSource) -> Void = { _ in },
    awaitSessionReload: @escaping @MainActor (SessionReloadSource) async throws -> Void = { _ in },
    retrySessionReload: @escaping @MainActor () -> Void = {},
    localResetRepository: (any LocalResetDataRepository)? = nil,
    localResetJournalStore: (any LocalResetJournalStoring)? = nil
  ) -> (AppRouter, AppNavigationCoordinator, SessionStore) {
    let routineRepository = ResolvingRoutineRepository()
    let routineRunRepository = RouterRuntimeRoutineRunRepository()
    let localProfileRepository = RouterRuntimeLocalProfileRepository()
    let dependencies = DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: routineRunRepository,
      localProfileRepository: localProfileRepository,
      localSettingsRepository: MockLocalProfileRepository(),
      onboardingRepository: RouterRuntimeOnboardingRepository(),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      homeWeatherRepository: nil,
      historyEvidenceRepository: MockHistoryEvidenceRepository(),
      voiceAvailabilityProbe: UnavailableVoiceAvailabilityProbe(),
      alarmScheduleMutator: DebugLocalCommitAlarmScheduleMutator(),
      localResetRepository: localResetRepository,
      localResetJournalStore: localResetJournalStore
    )
    let coordinator = AppNavigationCoordinator()
    let sessionStore = SessionStore()

    return (
      AppRouter(
        dependencies: dependencies,
        sessionStore: sessionStore,
        coordinator: coordinator,
        onboardingBuilder: EmptyOnboardingFlowBuilder(),
        routinePlayerBuilder: routinePlayerBuilder,
        requestSessionReload: requestSessionReload,
        awaitSessionReload: awaitSessionReload,
        retrySessionReload: retrySessionReload,
        homeBuilder: homeBuilder,
        state: state
      ),
      coordinator,
      sessionStore
    )
  }

  @MainActor
  private func waitUntil(
    _ message: String,
    _ predicate: @escaping @MainActor () async -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))

    while clock.now < deadline {
      if await predicate() {
        return
      }
      await Task.yield()
    }

    XCTFail(message)
  }


  @MainActor
  func testRegularLaunchBoundaryMapsStartedAndAlreadyRunning() {
    let coordinator = AppNavigationCoordinator()
    let routineID = UUID()

    let firstResult = AppRouter.regularRoutineLaunchResult(
      from: coordinator.presentRegularRoutine(routineID: routineID)
    )

    XCTAssertEqual(firstResult, .started)

    guard case .regularRoutine(let activeRoutineID, let token) = coordinator.presentation else {
      XCTFail("A regular launch should present the requested routine.")
      return
    }

    XCTAssertEqual(activeRoutineID, routineID)
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

    XCTAssertEqual(
      coordinator.presentation,
      .regularRoutine(routineID: nextRoutineID, token: nextToken)
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

    XCTAssertEqual(
      coordinator.presentationDidDismiss(),
      .reloadSession(.trialDismissal(token))
    )
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
    XCTAssertEqual(coordinator.navigationState, .idle)
  }

  @MainActor
  func testRouterForwardsMatchingTrialDismissalSourceOnce() {
    let homeBuilder = CapturingHomeFlowBuilder()
    let routinePlayerBuilder = CapturingRoutinePlayerBuilder()
    let reloadRecorder = RouterReloadRecorder()
    let routineID = UUID()
    let (router, coordinator, _) = makeRouter(
      homeBuilder: homeBuilder,
      routinePlayerBuilder: routinePlayerBuilder,
      state: AppRouterState(),
      requestSessionReload: reloadRecorder.request,
      retrySessionReload: reloadRecorder.retry
    )

    guard case .presented(let token) = coordinator.presentOnboardingTrial(
      routineID: routineID
    ) else {
      XCTFail("The trial presentation should be accepted.")
      return
    }

    _ = router.routinePlayerView(for: .onboardingTrial(routineID: routineID, token: token))
    routinePlayerBuilder.sendTrialEvent(
      .exitRequested(.summaryHome),
      presentationToken: UUID()
    )
    router.completePendingDismissal()
    XCTAssertTrue(reloadRecorder.requestedSources.isEmpty)

    routinePlayerBuilder.sendTrialEvent(.exitRequested(.summaryHome), presentationToken: token)
    XCTAssertTrue(reloadRecorder.requestedSources.isEmpty)

    router.completePendingDismissal()
    XCTAssertEqual(reloadRecorder.requestedSources, [.trialDismissal(token)])

    router.completePendingDismissal()
    XCTAssertEqual(reloadRecorder.requestedSources, [.trialDismissal(token)])
  }
  @MainActor
  func testTrialSummaryRecordExitIsIgnoredByReducer() {
    let routineID = UUID()
    let persistedRunID = UUID()
    let token = UUID()
    let presentation = AppPresentation.onboardingTrial(routineID: routineID, token: token)
    let state = AppNavigationState.presented(presentation)

    let transition = AppNavigationReducer.reduce(
      state: state,
      action: .handle(
        event: .exitRequested(.summaryRecord(persistedRunID: persistedRunID)),
        presentationToken: token
      )
    )

    XCTAssertEqual(transition.state, state)
    XCTAssertEqual(transition.effect, .none)
  }

  @MainActor
  func testRegularSummaryRecordRoutesExactRunOnlyAfterMatchingDismissalAcknowledgements() {
    let routineID = UUID()
    let persistedRunID = UUID()
    let token = UUID()
    let wrongToken = UUID()
    let presentation = AppPresentation.regularRoutine(routineID: routineID, token: token)
    let presentedState = AppNavigationState.presented(presentation)
    let action = AppNavigationAction.handle(
      event: .exitRequested(.summaryRecord(persistedRunID: persistedRunID)),
      presentationToken: token
    )

    let wrongEventToken = AppNavigationReducer.reduce(
      state: presentedState,
      action: .handle(
        event: .exitRequested(.summaryRecord(persistedRunID: persistedRunID)),
        presentationToken: wrongToken
      )
    )

    XCTAssertEqual(wrongEventToken.state, presentedState)
    XCTAssertEqual(wrongEventToken.effect, .none)

    let armed = AppNavigationReducer.reduce(state: presentedState, action: action)
    let armedState = AppNavigationState.dismissalArmed(
      presentation: presentation,
      afterDismiss: .showRunDetail(persistedRunID),
      isPresentationCleared: false
    )

    XCTAssertEqual(armed.state, armedState)
    XCTAssertEqual(armed.effect, .dismiss(token: token))

    let prematureDismissal = AppNavigationReducer.reduce(
      state: armed.state,
      action: .presentationDidDismiss(token: token)
    )
    let wrongClear = AppNavigationReducer.reduce(
      state: armed.state,
      action: .clearPresentationForDismissal(token: wrongToken)
    )

    XCTAssertEqual(prematureDismissal.state, armedState)
    XCTAssertEqual(prematureDismissal.effect, .none)
    XCTAssertEqual(wrongClear.state, armedState)
    XCTAssertEqual(wrongClear.effect, .none)

    let cleared = AppNavigationReducer.reduce(
      state: armed.state,
      action: .clearPresentationForDismissal(token: token)
    )
    let clearedState = AppNavigationState.dismissalArmed(
      presentation: presentation,
      afterDismiss: .showRunDetail(persistedRunID),
      isPresentationCleared: true
    )
    let wrongDismissal = AppNavigationReducer.reduce(
      state: cleared.state,
      action: .presentationDidDismiss(token: wrongToken)
    )

    XCTAssertEqual(cleared.state, clearedState)
    XCTAssertEqual(cleared.effect, .none)
    XCTAssertEqual(wrongDismissal.state, clearedState)
    XCTAssertEqual(wrongDismissal.effect, .none)

    let dismissed = AppNavigationReducer.reduce(
      state: cleared.state,
      action: .presentationDidDismiss(token: token)
    )
    let lateDismissal = AppNavigationReducer.reduce(
      state: dismissed.state,
      action: .presentationDidDismiss(token: token)
    )

    XCTAssertEqual(dismissed.state, .idle)
    XCTAssertEqual(dismissed.effect, .showRunDetail(persistedRunID))
    XCTAssertEqual(lateDismissal.state, .idle)
    XCTAssertEqual(lateDismissal.effect, .none)
  }

  @MainActor
  func testRegularSummaryHomeRoutesOnlyAfterMatchingDismissalAcknowledgements() {
    let routineID = UUID()
    let token = UUID()
    let presentation = AppPresentation.regularRoutine(routineID: routineID, token: token)
    let presentedState = AppNavigationState.presented(presentation)

    let armed = AppNavigationReducer.reduce(
      state: presentedState,
      action: .handle(
        event: .exitRequested(.summaryHome),
        presentationToken: token
      )
    )
    let prematureDismissal = AppNavigationReducer.reduce(
      state: armed.state,
      action: .presentationDidDismiss(token: token)
    )
    let cleared = AppNavigationReducer.reduce(
      state: armed.state,
      action: .clearPresentationForDismissal(token: token)
    )
    let dismissed = AppNavigationReducer.reduce(
      state: cleared.state,
      action: .presentationDidDismiss(token: token)
    )

    XCTAssertEqual(armed.effect, .dismiss(token: token))
    XCTAssertEqual(prematureDismissal.effect, .none)
    XCTAssertEqual(cleared.effect, .none)
    XCTAssertEqual(dismissed.state, .idle)
    XCTAssertEqual(dismissed.effect, .showHome)
  }

  @MainActor
  func testMainTabStateShowsExactRunDetailAndClearsConsumedOrManualDestination() {
    var state = MainTabState()
    let persistedRunID = UUID()
    let unrelatedRunID = UUID()

    state.showRunDetail(persistedRunID)

    XCTAssertEqual(state.selection, .record)
    XCTAssertEqual(state.historyDestination, .runDetail(persistedRunID))
    XCTAssertNotEqual(state.historyDestination, .runDetail(unrelatedRunID))
    XCTAssertEqual(state.historyReloadToken, 1)

    state.setHistoryDestination(nil)

    XCTAssertNil(state.historyDestination)

    state.showRunDetail(persistedRunID)
    state.select(.my)

    XCTAssertEqual(state.selection, .my)
    XCTAssertNil(state.historyDestination)
    XCTAssertEqual(state.historyReloadToken, 2)
  }

  @MainActor
  func testRegularSummaryActionsUseTheExactSavedRunAndEmitOnlyOnce() {
    let routine = makeExecutableRoutine()
    var operationOrder: [String] = []
    let saver = RoutineRunSaverSpy {
      operationOrder.append("save")
    }
    let finalizer = DefaultRegularRoutineFinalizer(saveRoutineRunUseCase: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder { event in
      if case .exitRequested = event {
        operationOrder.append("exit")
      }
    }
    let presentationToken = UUID()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(routineID: routine.id, source: .manual),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: presentationToken
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .summary(.regular(let result)) = viewModel.screenState else {
      XCTFail("A saved regular completion should show a persisted result.")
      return
    }

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(saver.savedRuns.map(\.id), [result.persistedRunID])
    XCTAssertFalse(viewModel.isSummaryActionDisabled)

    viewModel.requestSummaryRecord()
    viewModel.requestSummaryRecord()
    viewModel.requestSummaryHome()

    XCTAssertTrue(viewModel.isSummaryActionDisabled)
    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(operationOrder, ["save", "exit"])
    XCTAssertEqual(
      eventRecorder.events,
      [
        .completionDisplayed(result.summary),
        .exitRequested(.summaryRecord(persistedRunID: result.persistedRunID))
      ]
    )
    XCTAssertEqual(
      eventRecorder.presentationTokens,
      [presentationToken, presentationToken]
    )
  }

  @MainActor
  func testRegularSummaryHomeEmitsOneHomeExitWithThePresentationToken() {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy()
    let finalizer = DefaultRegularRoutineFinalizer(saveRoutineRunUseCase: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let presentationToken = UUID()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(routineID: routine.id, source: .manual),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: presentationToken
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .summary(.regular(let result)) = viewModel.screenState else {
      XCTFail("A completed regular routine should show a persisted result.")
      return
    }

    viewModel.requestSummaryHome()
    viewModel.requestSummaryRecord()
    viewModel.requestSummaryHome()

    XCTAssertTrue(viewModel.isSummaryActionDisabled)
    XCTAssertEqual(saver.savedRuns.map(\.id), [result.persistedRunID])
    XCTAssertEqual(
      eventRecorder.events,
      [
        .completionDisplayed(result.summary),
        .exitRequested(.summaryHome)
      ]
    )
    XCTAssertEqual(
      eventRecorder.presentationTokens,
      [presentationToken, presentationToken]
    )
  }
  @MainActor
  func testRoutineFinishedViewTrialConfigurationShowsOnlyDisabledHomePrimary() {
    let view = RoutineFinishedView(
      routineName: "테스트 루틴",
      completionRate: 100,
      completedStepCount: 1,
      skippedStepCount: 0,
      actionConfiguration: .trialHomeOnly,
      onAction: { _ in },
      isActionDisabled: true
    )

    XCTAssertTrue(view.isActionDisabled)
    XCTAssertEqual(
      view.actionConfiguration.actions,
      [
        RoutineCompletionActionConfiguration.Action(
          destination: .home,
          title: "홈으로",
          accessibilityIdentifier: "routineCompletion.primary",
          accessibilityHint: "홈 화면으로 돌아갑니다.",
          style: .primary
        )
      ]
    )
  }

  @MainActor
  func testRoutineFinishedViewRegularConfigurationShowsRecordPrimaryAndHomeSecondary() {
    let view = RoutineFinishedView(
      routineName: "테스트 루틴",
      completionRate: 100,
      completedStepCount: 1,
      skippedStepCount: 0,
      actionConfiguration: .regularRecordAndHome,
      onAction: { _ in },
      isActionDisabled: false
    )

    XCTAssertFalse(view.isActionDisabled)
    XCTAssertEqual(
      view.actionConfiguration.actions,
      [
        RoutineCompletionActionConfiguration.Action(
          destination: .record,
          title: "오늘의 기록 확인",
          accessibilityIdentifier: "routineCompletion.primary",
          accessibilityHint: "방금 완료한 루틴의 기록을 확인합니다.",
          style: .primary
        ),
        RoutineCompletionActionConfiguration.Action(
          destination: .home,
          title: "홈으로",
          accessibilityIdentifier: "routineCompletion.home",
          accessibilityHint: "홈 화면으로 돌아갑니다.",
          style: .secondary
        )
      ]
    )
  }

  @MainActor
  func testRegularCompletionWithoutPersistedRunIDDismissesOnceAfterTerminalContinuation() {
    let routine = makeExecutableRoutine()
    let routinePlayerBuilder = CapturingRoutinePlayerBuilder()
    let state = AppRouterState()
    let (router, coordinator, _) = makeRouter(
      homeBuilder: CapturingHomeFlowBuilder(),
      routinePlayerBuilder: routinePlayerBuilder,
      state: state
    )

    guard case .presented(let presentationToken) = coordinator.presentRegularRoutine(
      routineID: routine.id
    ) else {
      XCTFail("The regular presentation should be accepted.")
      return
    }

    _ = router.routinePlayerView(
      for: .regularRoutine(routineID: routine.id, token: presentationToken)
    )

    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(routineID: routine.id, source: .manual),
      resolver: resolver,
      finalizer: MissingPersistedRunIDRegularFinalizer(),
      presentationToken: presentationToken
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .terminalFailure(.missingPersistedRunID) = viewModel.screenState else {
      XCTFail("A regular completion without a persisted run ID must be terminal.")
      return
    }

    viewModel.continueAfterTerminalFailure()
    viewModel.continueAfterTerminalFailure()

    XCTAssertEqual(
      eventRecorder.events,
      [
        .terminalFailureDisplayed(.missingPersistedRunID),
        .exitRequested(.terminalUnavailable)
      ]
    )
    XCTAssertEqual(
      eventRecorder.presentationTokens,
      [presentationToken, presentationToken]
    )
    guard eventRecorder.events.count == 2 else {
      XCTFail("The terminal continuation must emit exactly two events.")
      return
    }

    routinePlayerBuilder.sendRegularEvent(
      eventRecorder.events[0],
      presentationToken: presentationToken
    )
    XCTAssertEqual(
      coordinator.presentation,
      .regularRoutine(routineID: routine.id, token: presentationToken)
    )
    XCTAssertNil(coordinator.pendingDismissalToken)

    routinePlayerBuilder.sendRegularEvent(
      eventRecorder.events[1],
      presentationToken: presentationToken
    )
    XCTAssertNil(coordinator.presentation)
    XCTAssertEqual(coordinator.pendingDismissalToken, presentationToken)

    router.completePendingDismissal()

    XCTAssertEqual(coordinator.navigationState, .idle)
    XCTAssertNil(coordinator.pendingDismissalToken)
    XCTAssertEqual(state.homeRefreshToken, 1)
  }

  @MainActor
  func testRouterAppearanceDoesNotRequestOrRetrySessionReload() throws {
    let reloadRecorder = RouterReloadRecorder()
    let (router, _, _) = makeRouter(
      homeBuilder: CapturingHomeFlowBuilder(),
      routinePlayerBuilder: CapturingRoutinePlayerBuilder(),
      state: AppRouterState(),
      requestSessionReload: reloadRecorder.request,
      retrySessionReload: reloadRecorder.retry
    )

    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let hostingController = UIHostingController(rootView: router)
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    hostingController.view.layoutIfNeeded()

    XCTAssertTrue(reloadRecorder.requestedSources.isEmpty)
    XCTAssertEqual(reloadRecorder.retryCount, 0)
  }

  @MainActor
  func testRouterFailureRetryDelegatesToTheLaunchCoordinator() {
    let reloadRecorder = RouterReloadRecorder()
    let (router, _, sessionStore) = makeRouter(
      homeBuilder: CapturingHomeFlowBuilder(),
      routinePlayerBuilder: CapturingRoutinePlayerBuilder(),
      state: AppRouterState(),
      requestSessionReload: reloadRecorder.request,
      retrySessionReload: reloadRecorder.retry
    )

    sessionStore.apply(failure: .session)
    router.retrySessionReload()

    XCTAssertEqual(reloadRecorder.retryCount, 1)
    XCTAssertTrue(reloadRecorder.requestedSources.isEmpty)
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

    successfulViewModel.primaryButtonDidTap()
    successfulViewModel.primaryButtonDidTap()
    while successfulViewModel.isSaving {
      await Task.yield()
    }

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

    failingViewModel.primaryButtonDidTap()
    while failingViewModel.isSaving {
      await Task.yield()
    }

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
  func testConsecutiveSameKindStepsPreserveTheirStableIDs() {
    let firstStep = RoutineStep(type: .confirm, title: "첫 번째", order: 0)
    let secondStep = RoutineStep(type: .confirm, title: "두 번째", order: 1)
    let routine = makeExecutableRoutine(steps: [firstStep, secondStep])
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: resolver,
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()

    guard case .running(let currentStep) = viewModel.screenState else {
      XCTFail("The first step should be running.")
      return
    }

    XCTAssertEqual(currentStep.id, firstStep.id)

    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .running(let nextStep) = viewModel.screenState else {
      XCTFail("The second step should be running.")
      return
    }

    XCTAssertEqual(nextStep.id, secondStep.id)
  }

  @MainActor
  func testTrialNaturalCompletionShowsOnlyHomeAndEmitsItOnce() {
    let routine = makeExecutableRoutine()
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let finalizer = TrialRoutineFinalizerSpy()
    let eventRecorder = RoutinePlayerEventRecorder()
    let presentationToken = UUID()
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: presentationToken
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .summary(.trial(let summary)) = viewModel.screenState else {
      XCTFail("A completed trial should show a trial summary.")
      return
    }

    XCTAssertNil(summary.persistedRunID)
    XCTAssertFalse(summary.endedEarly)
    XCTAssertEqual(finalizer.finalizeCallCount, 1)
    XCTAssertEqual(finalizer.finalizedRoutineIDs, [routine.id])
    XCTAssertEqual(finalizer.finalizedResultCounts, [1])

    viewModel.requestSummaryRecord()
    viewModel.requestSummaryHome()
    viewModel.requestSummaryHome()

    XCTAssertEqual(
      eventRecorder.events,
      [
        .completionDisplayed(summary),
        .exitRequested(.summaryHome)
      ]
    )
    XCTAssertEqual(eventRecorder.presentationTokens, [presentationToken, presentationToken])
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
    let finalizer = DefaultRegularRoutineFinalizer(saveRoutineRunUseCase: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let presentationToken = UUID()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: presentationToken
    ) { token, event in
      eventRecorder.record(presentationToken: token, event: event)
    }

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep()
    viewModel.finishStepCompletedScreen()

    guard case .summary(.regular(let result)) = viewModel.screenState else {
      XCTFail("A completed regular routine should show a persisted result.")
      return
    }

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(saver.requests.first?.endedEarly, false)
    XCTAssertEqual(result.persistedRunID, saver.savedRuns.first?.id)
    XCTAssertFalse(result.summary.endedEarly)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(result.summary)])

    viewModel.finishStepCompletedScreen()
    viewModel.retrySavingRun()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(result.summary)])
    XCTAssertEqual(eventRecorder.presentationTokens, [presentationToken])
  }

  @MainActor
  func testRegularNaturalCompletionRetryUsesSameRequestAndEmitsOneCompletionEvent() {
    let routine = makeExecutableRoutine()
    let saver = RoutineRunSaverSpy(failuresRemaining: 1)
    let finalizer = DefaultRegularRoutineFinalizer(saveRoutineRunUseCase: saver)
    let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
    let eventRecorder = RoutinePlayerEventRecorder()
    let presentationToken = UUID()
    let viewModel = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: routine.id,
        source: .manual
      ),
      resolver: resolver,
      finalizer: finalizer,
      presentationToken: presentationToken
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

    guard case .summary(.regular(let result)) = viewModel.screenState else {
      XCTFail("A successful retry should show a persisted result.")
      return
    }

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(saver.requests[0], saver.requests[1])
    XCTAssertEqual(result.persistedRunID, saver.savedRuns.first?.id)
    XCTAssertFalse(result.summary.endedEarly)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(result.summary)])

    viewModel.retrySavingRun()

    XCTAssertEqual(saver.requests.count, 2)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(result.summary)])
    XCTAssertEqual(eventRecorder.presentationTokens, [presentationToken])
  }

  @MainActor
  func testRegularEndAndCloseSaveBeforeEmittingTheirExit() {
    for exit in [RoutinePlayerExit.endedEarly, .userDismissed] {
      let routine = makeExecutableRoutine()
      var operationOrder: [String] = []
      let saver = RoutineRunSaverSpy {
        operationOrder.append("save")
      }
      let finalizer = DefaultRegularRoutineFinalizer(saveRoutineRunUseCase: saver)
      let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
      let eventRecorder = RoutinePlayerEventRecorder { event in
        if case .exitRequested = event {
          operationOrder.append("exit")
        }
      }
      let presentationToken = UUID()
      let viewModel = RoutinePlayerViewModel(
        request: RegularRoutineExecutionRequest(
          routineID: routine.id,
          source: .manual
        ),
        resolver: resolver,
        finalizer: finalizer,
        presentationToken: presentationToken
      ) { token, event in
        eventRecorder.record(presentationToken: token, event: event)
      }

      viewModel.resolveRoutine()
      requestEarlyExit(exit, from: viewModel)
      viewModel.confirmActiveDialog()

      XCTAssertEqual(saver.requests.count, 1)
      XCTAssertEqual(saver.requests.first?.endedEarly, true)
      XCTAssertEqual(saver.savedRuns.count, 1)
      XCTAssertEqual(operationOrder, ["save", "exit"])
      XCTAssertEqual(eventRecorder.events, [.exitRequested(exit)])
      XCTAssertEqual(eventRecorder.presentationTokens, [presentationToken])
    }
  }

  @MainActor
  func testRegularEarlyExitRetriesTheSameRequestAndEmitsEachExitOnce() {
    for exit in [RoutinePlayerExit.endedEarly, .userDismissed] {
      let routine = makeExecutableRoutine()
      var operationOrder: [String] = []
      let saver = RoutineRunSaverSpy(failuresRemaining: 1) {
        operationOrder.append("save")
      }
      let finalizer = DefaultRegularRoutineFinalizer(saveRoutineRunUseCase: saver)
      let resolver = RoutineExecutionResolverSpy(resolution: .available(routine))
      let eventRecorder = RoutinePlayerEventRecorder { event in
        if case .exitRequested = event {
          operationOrder.append("exit")
        }
      }
      let presentationToken = UUID()
      let viewModel = RoutinePlayerViewModel(
        request: RegularRoutineExecutionRequest(
          routineID: routine.id,
          source: .manual
        ),
        resolver: resolver,
        finalizer: finalizer,
        presentationToken: presentationToken
      ) { token, event in
        eventRecorder.record(presentationToken: token, event: event)
      }

      viewModel.resolveRoutine()
      requestEarlyExit(exit, from: viewModel)
      viewModel.confirmActiveDialog()

      XCTAssertEqual(saver.requests.count, 1)
      XCTAssertTrue(saver.savedRuns.isEmpty)
      XCTAssertNotNil(viewModel.errorMessage)
      XCTAssertTrue(eventRecorder.events.isEmpty)
      XCTAssertTrue(viewModel.isStepInteractionDisabled)

      viewModel.retrySavingRun()

      XCTAssertEqual(saver.requests.count, 2)
      XCTAssertEqual(saver.requests[0], saver.requests[1])
      XCTAssertEqual(saver.savedRuns.count, 1)
      XCTAssertNil(viewModel.errorMessage)
      XCTAssertEqual(operationOrder, ["save", "save", "exit"])
      XCTAssertEqual(eventRecorder.events, [.exitRequested(exit)])

      viewModel.retrySavingRun()
      viewModel.confirmActiveDialog()

      XCTAssertEqual(saver.requests.count, 2)
      XCTAssertEqual(eventRecorder.events, [.exitRequested(exit)])
      XCTAssertEqual(eventRecorder.presentationTokens, [presentationToken])
    }
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

    case .summaryHome, .summaryRecord, .terminalUnavailable:
      XCTFail("Only early exit reasons are valid for this helper.")
    }
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

  func execute(_ request: CompleteOnboardingRequest) throws -> CompleteOnboardingResult {
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
private final class MissingPersistedRunIDRegularFinalizer: RegularRoutineFinalizing {
  func finalize(_ request: SaveRoutineRunRequest) throws -> RegularRoutineCompletionResult {
    throw RegularRoutineFinalizationError.missingPersistedRunID
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
private final class RouterAsyncReloadRecorder {
  private var continuations: [CheckedContinuation<Void, Error>] = []
  private(set) var sources: [SessionReloadSource] = []

  func awaitReload(_ source: SessionReloadSource) async throws {
    sources.append(source)
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func succeedNext() -> Bool {
    guard !continuations.isEmpty else {
      return false
    }

    continuations.removeFirst().resume()
    return true
  }
}

@MainActor
private final class RouterResetDataRepository: LocalResetDataRepository {
  func inventoryScheduleIDs() throws -> [UUID] {
    []
  }

  func deleteAll() throws {}
}
@MainActor
private final class RouterReloadRecorder {
  private(set) var requestedSources: [SessionReloadSource] = []
  private(set) var retryCount = 0

  func request(_ source: SessionReloadSource) {
    requestedSources.append(source)
  }

  func retry() {
    retryCount += 1
  }
}

@MainActor
private final class CapturingHomeFlowBuilder: HomeFlowBuilding {
  private(set) var refreshTokens: [Int] = []
  private(set) var onStartRoutine: RoutineLaunchHandler?

  func make(
    onStartRoutine: @escaping RoutineLaunchHandler,
    refreshToken: Int
  ) -> AnyView {
    self.onStartRoutine = onStartRoutine
    refreshTokens.append(refreshToken)
    return AnyView(EmptyView())
  }
}

@MainActor
private final class CapturingRoutinePlayerBuilder: RoutinePlayerBuilding {
  private(set) var trialRequests: [TrialRoutineExecutionRequest] = []
  private(set) var trialPresentationTokens: [UUID] = []
  private var trialOnEvent: RoutinePlayerEventHandler?
  private(set) var regularRequests: [RegularRoutineExecutionRequest] = []
  private(set) var regularPresentationTokens: [UUID] = []
  private var regularOnEvent: RoutinePlayerEventHandler?

  func makeTrial(
    request: TrialRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView {
    trialRequests.append(request)
    trialPresentationTokens.append(presentationToken)
    trialOnEvent = onEvent
    return AnyView(EmptyView())
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
  func sendTrialEvent(
    _ event: RoutinePlayerEvent,
    presentationToken: UUID
  ) {
    trialOnEvent?(presentationToken, event)
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
