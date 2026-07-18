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

  func testAudioLevelEventUpdatesTwentyWaveformBars() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.audioLevel(1))

    XCTAssertEqual(controller.waveformLevels.count, 20)
    XCTAssertGreaterThan(controller.waveformLevels.last ?? 0, 0)
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

  init(finishTranscript: String = "") {
    self.finishTranscript = finishTranscript
  }

  func start() async throws {
    startCallCount += 1
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
