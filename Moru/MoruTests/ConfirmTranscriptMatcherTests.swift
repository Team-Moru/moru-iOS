//
//  ConfirmTranscriptMatcherTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class ConfirmTranscriptMatcherTests: XCTestCase {
  func testPositiveFinalTranscriptsConfirmRoutineStep() {
    let transcripts = ["완료했어요", "끝", "다 했어", "됐어", "네", "응"]

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

  func testEmptyAndAmbiguousTranscriptsDoNotConfirmRoutineStep() {
    XCTAssertFalse(ConfirmTranscriptMatcher.isConfirmed(""))
    XCTAssertFalse(ConfirmTranscriptMatcher.isConfirmed("오늘 날씨가 좋아"))
    XCTAssertFalse(ConfirmTranscriptMatcher.isConfirmed("네, 아직이에요"))
  }
}
