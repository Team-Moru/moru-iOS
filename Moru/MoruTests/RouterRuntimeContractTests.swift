//
//  RouterRuntimeContractTests.swift
//  MoruTests
//
//  Created by Codex on 7/13/26.
//

import Foundation
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

    XCTAssertEqual(coordinator.presentationDidDismiss(), .reloadSession)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
    XCTAssertEqual(coordinator.navigationState, .idle)
  }

  @MainActor
  func testCoordinatorReloadsTrialSessionOnceAfterMatchingDismissal() {
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

    XCTAssertEqual(coordinator.presentationDidDismiss(), .reloadSession)
    XCTAssertEqual(coordinator.presentationDidDismiss(), .none)
  }

  @MainActor
  func testCoordinatorBeginsInitialSessionLoadOnlyOnce() {
    let coordinator = AppNavigationCoordinator()

    XCTAssertTrue(coordinator.beginInitialSessionLoadIfNeeded())
    XCTAssertFalse(coordinator.beginInitialSessionLoadIfNeeded())
  }

  @MainActor
  func testOnboardingEmitsExactSavedRoutineIDOnceAndFailureEmitsNone() {
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

    viewModel.finishStepCompletedScreen()
    viewModel.retrySavingRun()

    XCTAssertEqual(saver.requests.count, 1)
    XCTAssertEqual(eventRecorder.events, [.completionDisplayed(summary)])
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
  func testRegularEndAndCloseSaveBeforeEmittingTheirExit() {
    for exit in [RoutinePlayerExit.endedEarly, .userDismissed] {
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
      requestEarlyExit(exit, from: viewModel)
      viewModel.confirmActiveDialog()

      XCTAssertEqual(saver.requests.count, 1)
      XCTAssertEqual(saver.requests.first?.endedEarly, true)
      XCTAssertEqual(saver.savedRuns.count, 1)
      XCTAssertEqual(operationOrder, ["save", "exit"])
      XCTAssertEqual(eventRecorder.events, [.exitRequested(exit)])
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

    case .summaryCTA, .terminalUnavailable:
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
