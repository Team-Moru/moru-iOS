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
      match: .weak
    )

    XCTAssertEqual(disposition, .immediately)
  }

  func testVolatileExplicitCompletionUsesShortDelay() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "완료했어", isFinal: false),
      match: .explicit
    )

    XCTAssertEqual(disposition, .afterDelay(.milliseconds(400)))
  }

  func testVolatileWeakCompletionUsesStabilityDelay() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "정리했어", isFinal: false),
      match: .weak
    )

    XCTAssertEqual(disposition, .afterDelay(.milliseconds(600)))
  }

  func testNoCompletionSignalDoesNotScheduleAutomaticFinish() {
    let disposition = SpeechAutomaticCompletionPolicy.disposition(
      for: SpeechTranscriptUpdate(text: "아직 안 했어", isFinal: false),
      match: .none
    )

    XCTAssertEqual(disposition, .none)
  }
}
