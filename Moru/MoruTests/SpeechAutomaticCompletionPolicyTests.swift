//
//  SpeechAutomaticCompletionPolicyTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class SpeechAutomaticCompletionPolicyTests: XCTestCase {
  func testFinalCompletionFinishesImmediately() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "정리했어", isFinal: true),
      intent: .stepCompletion,
      match: .weak
    )

    XCTAssertEqual(disposition, .immediately)
  }

  func testVolatileExplicitCompletionUsesShortDelay() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "완료했어", isFinal: false),
      intent: .stepCompletion,
      match: .explicit
    )

    XCTAssertEqual(disposition, .afterDelay(.milliseconds(400)))
  }

  func testVolatileWeakCompletionUsesStabilityDelay() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "정리했어", isFinal: false),
      intent: .stepCompletion,
      match: .weak
    )

    XCTAssertEqual(disposition, .afterDelay(.milliseconds(600)))
  }

  func testNoCompletionSignalDoesNotScheduleAutomaticFinish() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "아직 안 했어", isFinal: false),
      intent: .stepCompletion,
      match: .none
    )

    XCTAssertEqual(disposition, .none)
  }

  func testFinalDictatedInputFinishesWithoutCompletionKeyword() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(
        text: "차분하게 하루를 시작할게요",
        isFinal: true
      ),
      intent: .dictatedInput,
      match: .none
    )

    XCTAssertEqual(disposition, .immediately)
  }

  func testVolatileDictatedInputWaitsForFinalResult() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(
        text: "차분하게 하루를",
        isFinal: false
      ),
      intent: .dictatedInput,
      match: .none
    )

    XCTAssertEqual(disposition, .none)
  }

  func testEmptyFinalDictatedInputDoesNotFinish() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "  ", isFinal: true),
      intent: .dictatedInput,
      match: .none
    )

    XCTAssertEqual(disposition, .none)
  }
}
