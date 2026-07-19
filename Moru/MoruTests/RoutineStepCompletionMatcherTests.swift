//
//  RoutineStepCompletionMatcherTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class RoutineStepCompletionMatcherTests: XCTestCase {
  private let waterStep = RoutineStep(
    type: .input,
    title: "물 한잔 마시기",
    instruction: "물을 마신 뒤 말해주세요.",
    order: 0
  )

  func testWaterDrinkingCompletionAcceptsCompletedAction() {
    let transcripts = ["물 한잔 마셨어", "물을 마셨어요", "물 다 마셨다"]

    XCTAssertTrue(
      transcripts.allSatisfy { transcript in
        RoutineStepCompletionMatcher.isCompleted(transcript, for: waterStep)
      }
    )
  }

  func testWaterDrinkingCompletionRejectsNegativeResponse() {
    XCTAssertFalse(
      RoutineStepCompletionMatcher.isCompleted("물 안 마셨어", for: waterStep)
    )
  }

  func testWaterDrinkingCompletionDoesNotApplyToOtherSteps() {
    let otherStep = RoutineStep(type: .input, title: "스트레칭", order: 0)

    XCTAssertFalse(
      RoutineStepCompletionMatcher.isCompleted("물 한잔 마셨어", for: otherStep)
    )
  }
}
