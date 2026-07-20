//
//  RoutinePlayerTranscriptContractTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class RoutinePlayerTranscriptContractTests: XCTestCase {
  func testConfirmAndInputCompletionStoreTranscriptWithoutInputText() {
    let confirmStep = RoutineStep(type: .confirm, title: "물 마시기", order: 0)
    let inputStep = RoutineStep(type: .input, title: "오늘의 다짐", order: 1)
    let routine = Routine(name: "음성 루틴", steps: [confirmStep, inputStep])
    let viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: RoutineExecutionResolverSpy(routine: routine),
      finalizer: TrialRoutineFinalizerSpy(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    viewModel.resolveRoutine()
    viewModel.completeCurrentStep(transcript: "완료했어요")

    XCTAssertEqual(viewModel.stepResults.first?.transcript, "완료했어요")
    XCTAssertNil(viewModel.stepResults.first?.inputText)

    viewModel.finishStepCompletedScreen()
    viewModel.completeCurrentStep(transcript: "차분하게 하루를 시작할게요")

    XCTAssertEqual(
      viewModel.stepResults.last?.transcript,
      "차분하게 하루를 시작할게요"
    )
    XCTAssertNil(viewModel.stepResults.last?.inputText)
  }
}

@MainActor
private final class RoutineExecutionResolverSpy: ResolveRoutineExecutionUseCaseProtocol {
  private let routine: Routine

  init(routine: Routine) {
    self.routine = routine
  }

  func execute(_ request: ResolveRoutineExecutionRequest) -> RoutineExecutionResolution {
    .available(routine)
  }
}

@MainActor
private final class TrialRoutineFinalizerSpy: TrialRoutineFinalizing {
  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
    makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      endedEarly: false
    )
  }
}
