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

  func testClassifiesExplicitCompletionCommand() {
    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("완료했어", for: waterStep),
      .explicit
    )
  }

  func testClassifiesWeakCompletedActionPhrases() {
    let transcripts = [
      "잠자리 정리했어",
      "잠자리 정리했어요",
      "잠자리 정리했다",
      "잠자리 정리 마쳤어",
      "잠자리 정리 끝냈다"
    ]

    XCTAssertTrue(
      transcripts.allSatisfy { transcript in
        RoutineStepCompletionMatcher.match(transcript, for: waterStep) == .weak
      }
    )
  }

  func testClassifiesWaterDrinkingCompletionAsContextual() {
    XCTAssertEqual(
      RoutineStepCompletionMatcher.match("물 한잔 마셨어", for: waterStep),
      .contextual
    )
  }

  func testWaterDrinkingCompletionRejectsNegativeResponse() {
    let transcripts = [
      "물 안 마셨어",
      "잠자리 정리 안 마쳤어",
      "아직 안 됐어",
      "못 끝냈어"
    ]

    XCTAssertTrue(
      transcripts.allSatisfy { transcript in
        RoutineStepCompletionMatcher.match(transcript, for: waterStep) == .none
      }
    )
  }

  func testWaterDrinkingCompletionDoesNotApplyToOtherSteps() {
    let otherStep = RoutineStep(type: .input, title: "스트레칭", order: 0)

    XCTAssertFalse(
      RoutineStepCompletionMatcher.isCompleted("물 한잔 마셨어", for: otherStep)
    )
  }
}
