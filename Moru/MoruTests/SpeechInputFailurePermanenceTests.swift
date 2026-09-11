//
//  SpeechInputFailurePermanenceTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class SpeechInputFailurePermanenceTests: XCTestCase {
  func testPermissionDeviceAndLocaleFailuresArePermanent() {
    XCTAssertTrue(SpeechInputFailure.microphonePermissionDenied.isPermanent)
    XCTAssertTrue(SpeechInputFailure.transcriberUnavailable.isPermanent)
    XCTAssertTrue(SpeechInputFailure.localeUnavailable.isPermanent)
  }

  func testNetworkAudioRecognitionAndSilenceFailuresStayRetryable() {
    XCTAssertFalse(SpeechInputFailure.modelDownloadFailed.isPermanent)
    XCTAssertFalse(SpeechInputFailure.audioSession.isPermanent)
    XCTAssertFalse(SpeechInputFailure.recognition.isPermanent)
    XCTAssertFalse(SpeechInputFailure.silence.isPermanent)
  }

  func testManualCompletionSharesTheSpokenCompletionPhrase() {
    XCTAssertEqual(RoutinePlayerCopy.manualCompletionTitle, "완료했어요")
  }
}
