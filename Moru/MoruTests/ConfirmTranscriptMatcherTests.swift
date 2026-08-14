//
//  ConfirmTranscriptMatcherTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class ConfirmTranscriptMatcherTests: XCTestCase {
  func testPositiveFinalTranscriptsConfirmRoutineStep() {
    let transcripts = [
      "완료했어요",
      "완료했습니다",
      "끝",
      "다 했어",
      "끝냈어요",
      "마쳤어",
      "됐어",
      "다음",
      "네",
      "넵",
      "예",
      "응",
      "그래",
      "맞아",
      "좋아",
      "오케이"
    ]

    XCTAssertTrue(transcripts.allSatisfy(ConfirmTranscriptMatcher.isConfirmed))
  }

  func testNegativeExpressionWinsOverPositiveWord() {
    let transcripts = [
      "아직 완료 안 했어",
      "완료하지 않았어",
      "못 했어",
      "덜 했어"
    ]

    XCTAssertTrue(
      transcripts.allSatisfy { !ConfirmTranscriptMatcher.isConfirmed($0) }
    )
  }

  func testNegativeTranscriptKeepsNegativeFeedbackAfterManualFinish() {
    XCTAssertEqual(
      ConfirmStepFeedback.completionFailure(for: "아직 안 했어"),
      ConfirmStepFeedback.negativeResponse
    )
  }

  func testUnrecognizedTranscriptUsesGenericCompletionFeedback() {
    XCTAssertEqual(
      ConfirmStepFeedback.completionFailure(for: "잘 안 들려요"),
      ConfirmStepFeedback.unrecognizedCompletion
    )
  }

  func testEmptyAndAmbiguousTranscriptsDoNotConfirmRoutineStep() {
    XCTAssertFalse(ConfirmTranscriptMatcher.isConfirmed(""))
    XCTAssertFalse(ConfirmTranscriptMatcher.isConfirmed("오늘 날씨가 좋아"))
    XCTAssertFalse(ConfirmTranscriptMatcher.isConfirmed("네, 아직이에요"))
  }

  func testExplicitCompletionCommandDoesNotTreatFreeformInputAsFinished() {
    XCTAssertTrue(ConfirmTranscriptMatcher.isExplicitCompletionCommand("완료했어"))
    XCTAssertTrue(ConfirmTranscriptMatcher.isExplicitCompletionCommand("다 했어"))
    XCTAssertTrue(ConfirmTranscriptMatcher.isExplicitCompletionCommand("다음."))
    XCTAssertFalse(ConfirmTranscriptMatcher.isExplicitCompletionCommand("물을 마시고 완료할 거야"))
    XCTAssertFalse(ConfirmTranscriptMatcher.isExplicitCompletionCommand("아직 완료 안 했어"))
  }
}
