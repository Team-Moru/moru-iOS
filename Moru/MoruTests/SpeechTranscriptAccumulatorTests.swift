//
//  SpeechTranscriptAccumulatorTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class SpeechTranscriptAccumulatorTests: XCTestCase {
  func testFinalizedSegmentsAreAppendedInsteadOfReplacingEarlierSpeech() {
    var accumulator = SpeechTranscriptAccumulator()

    _ = accumulator.append("물을 ", isFinal: true)
    let transcript = accumulator.append("마셨어요", isFinal: true)

    XCTAssertEqual(transcript, "물을 마셨어요")
    XCTAssertEqual(accumulator.finalizedTranscript, "물을 마셨어요")
  }

  func testVolatileRevisionReplacesOnlyTheCurrentUnfinalizedSegment() {
    var accumulator = SpeechTranscriptAccumulator()

    _ = accumulator.append("오늘은 ", isFinal: true)
    _ = accumulator.append("차분", isFinal: false)
    let transcript = accumulator.append("차분하게 시작할게요", isFinal: false)

    XCTAssertEqual(transcript, "오늘은 차분하게 시작할게요")
    XCTAssertEqual(accumulator.finalizedTranscript, "오늘은 ")
    XCTAssertEqual(accumulator.volatileTranscript, "차분하게 시작할게요")
  }

  func testFinalResultClearsVolatileRevisionWithoutDuplicatingIt() {
    var accumulator = SpeechTranscriptAccumulator()

    _ = accumulator.append("물 마시", isFinal: false)
    let transcript = accumulator.append("물 마셨어요", isFinal: true)

    XCTAssertEqual(transcript, "물 마셨어요")
    XCTAssertTrue(accumulator.volatileTranscript.isEmpty)
  }
}
