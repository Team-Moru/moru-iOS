//
//  SpeechInputControllerTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class SpeechInputControllerTests: XCTestCase {
  func testStartAndFinishExposeFinalTranscript() async {
    let session = SpeechInputSessionSpy(finishTranscript: "완료했어요")
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.transcript("완료했어요", isFinal: true))
    let transcript = await controller.finish()

    XCTAssertEqual(session.startCallCount, 1)
    XCTAssertEqual(session.finishCallCount, 1)
    XCTAssertEqual(transcript, "완료했어요")
    XCTAssertEqual(controller.phase, .idle)
  }

  func testPauseAndResumeJoinTranscriptSegmentsWithoutDuplicates() async {
    let firstSession = SpeechInputSessionSpy(finishTranscript: "첫 문장")
    let secondSession = SpeechInputSessionSpy(finishTranscript: "두 번째 문장")
    let factory = SpeechInputSessionFactory(sessions: [firstSession, secondSession])
    let controller = SpeechInputController { factory.makeSession() }

    await controller.start()
    await controller.pause()

    XCTAssertEqual(controller.phase, .paused)
    XCTAssertEqual(controller.displayTranscript, "첫 문장")

    await controller.resume()
    let transcript = await controller.finish()

    XCTAssertEqual(transcript, "첫 문장 두 번째 문장")
    XCTAssertEqual(firstSession.finishCallCount, 1)
    XCTAssertEqual(secondSession.finishCallCount, 1)
  }

  func testRecognitionFailureMovesToFailedWithoutSavingVolatileTranscript() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.transcript("완료", isFinal: false))
    session.send(.failed(.recognition))
    let transcript = await controller.finish()

    XCTAssertEqual(controller.phase, .failed(.recognition))
    XCTAssertNil(transcript)
  }

  func testCancelIsIdempotentAndStopsTheActiveSessionOnce() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    controller.cancel()
    controller.cancel()

    XCTAssertEqual(session.cancelCallCount, 1)
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertTrue(controller.waveformLevels.allSatisfy { $0 == 0 })
  }

  func testAudioLevelsEventUpdatesTwentyWaveformBars() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.audioLevels(Array(repeating: 1, count: 20)))

    XCTAssertEqual(controller.waveformLevels.count, 20)
    XCTAssertGreaterThan(controller.waveformLevels.last ?? 0, 0)
    controller.cancel()
  }

  func testAudioLevelsEventPreservesPerBarWaveformShape() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }
    let levels = (0..<20).map { Float($0) / 19 }

    await controller.start()
    session.send(.audioLevels(levels))

    XCTAssertLessThan(controller.waveformLevels.first ?? 1, 0.01)
    XCTAssertGreaterThan(controller.waveformLevels.last ?? 0, 0.4)
    XCTAssertLessThan(
      controller.waveformLevels[5],
      controller.waveformLevels[15]
    )
    controller.cancel()
  }

  func testFinalTranscriptIsExposedForAutomaticCompletion() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.transcript("완료했어요", isFinal: true))

    XCTAssertEqual(controller.latestFinalTranscript, "완료했어요")
    controller.cancel()
  }

  func testStaleSessionFailureDoesNotStopNewListeningAttempt() async {
    let firstSession = SpeechInputSessionSpy()
    let secondSession = SpeechInputSessionSpy()
    let factory = SpeechInputSessionFactory(sessions: [firstSession, secondSession])
    let controller = SpeechInputController { factory.makeSession() }

    await controller.start()
    controller.cancel()
    await controller.start()
    firstSession.send(.failed(.recognition))

    XCTAssertEqual(controller.phase, .listening)
    controller.cancel()
  }

  func testStartMapsTranscriberUnavailableToDeviceFailure() async {
    let session = SpeechInputSessionSpy(
      startError: AppleSpeechRecognitionSessionError.transcriberUnavailable
    )
    let controller = SpeechInputController { session }

    await controller.start()

    XCTAssertEqual(controller.phase, .failed(.transcriberUnavailable))
    XCTAssertEqual(
      controller.statusText,
      "이 기기에서는 음성 인식 기능을 사용할 수 없어요."
    )
  }

  func testStartMapsModelPreparationFailureWithoutLocaleUnavailable() async {
    let session = SpeechInputSessionSpy(
      startError: AppleSpeechRecognitionSessionError.modelDownloadFailed
    )
    let controller = SpeechInputController { session }

    await controller.start()

    XCTAssertEqual(controller.phase, .failed(.modelDownloadFailed))
    XCTAssertEqual(
      controller.statusText,
      "음성 인식 준비에 실패했어요. 네트워크를 확인해 주세요."
    )
  }

  func testStartMapsUnsupportedLocaleToLocaleUnavailable() async {
    let session = SpeechInputSessionSpy(
      startError: AppleSpeechRecognitionSessionError.localeUnavailable
    )
    let controller = SpeechInputController { session }

    await controller.start()

    XCTAssertEqual(controller.phase, .failed(.localeUnavailable))
  }

  func testStartMapsUnavailableAudioInputToRetryableFailure() async {
    let session = SpeechInputSessionSpy(
      startError: AppleSpeechRecognitionSessionError.audioSession
    )
    let controller = SpeechInputController { session }

    await controller.start()

    XCTAssertEqual(controller.phase, .failed(.audioSession))
    XCTAssertEqual(
      controller.statusText,
      "마이크를 시작할 수 없어요. 다시 시도해 주세요."
    )
  }
}

@MainActor
private final class SpeechInputSessionFactory {
  private var sessions: [SpeechInputSessionSpy]

  init(sessions: [SpeechInputSessionSpy]) {
    self.sessions = sessions
  }

  func makeSession() -> SpeechInputSessionSpy {
    sessions.removeFirst()
  }
}

@MainActor
private final class SpeechInputSessionSpy: SpeechInputSession {
  var eventHandler: ((SpeechInputSessionEvent) -> Void)?
  var startCallCount = 0
  var finishCallCount = 0
  var cancelCallCount = 0
  var finishTranscript: String
  var startError: Error?

  init(
    finishTranscript: String = "",
    startError: Error? = nil
  ) {
    self.finishTranscript = finishTranscript
    self.startError = startError
  }

  func start() async throws {
    startCallCount += 1
    if let startError {
      throw startError
    }
  }

  func finish() async throws -> String {
    finishCallCount += 1
    return finishTranscript
  }

  func cancel() {
    cancelCallCount += 1
  }

  func send(_ event: SpeechInputSessionEvent) {
    eventHandler?(event)
  }
}
