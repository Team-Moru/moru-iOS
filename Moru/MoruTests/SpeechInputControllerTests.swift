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

  func testRecognitionFailureCancelsSilenceDeadlineWithoutSavingVolatileTranscript() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) { session }

    await controller.start()
    session.send(.transcript("완료", isFinal: false))
    session.send(.failed(.recognition))
    scheduler.fireMostRecentlyCancelledAction()
    let transcript = await controller.finish()

    XCTAssertEqual(controller.phase, .failed(.recognition))
    XCTAssertNil(transcript)
    XCTAssertEqual(session.cancelCallCount, 1)
    XCTAssertNil(controller.latestSilenceCompletion)
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

  func testVolatileTranscriptUpdateIsExposedForAutomaticCompletion() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.transcript("정리했어", isFinal: false))

    XCTAssertEqual(
      controller.latestTranscriptUpdate,
      SpeechTranscriptUpdate(text: "정리했어", isFinal: false)
    )
    controller.cancel()
  }

  func testFinishImmediatelyPreservesCandidateAndIgnoresLateResults() async {
    let session = SpeechInputSessionSpy()
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.transcript("정리했어", isFinal: false))
    let transcript = controller.finishImmediately(using: "정리했어")
    session.send(.transcript("늦은 결과", isFinal: true))

    XCTAssertEqual(transcript, "정리했어")
    XCTAssertEqual(session.cancelCallCount, 1)
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertNil(controller.latestTranscriptUpdate)
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

  func testInterruptionFinishesCurrentSegmentAndMovesToPaused() async {
    let session = SpeechInputSessionSpy(finishTranscript: "물을 마셨어요")
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.interrupted)
    await drainTasks()
    session.send(.transcript("늦은 결과", isFinal: true))

    XCTAssertEqual(session.finishCallCount, 1)
    XCTAssertEqual(controller.displayTranscript, "물을 마셨어요")
    XCTAssertEqual(controller.phase, .paused)
  }

  func testRouteChangeFinishesCurrentSegmentAndKeepsItPaused() async {
    let session = SpeechInputSessionSpy(finishTranscript: "차분하게 시작할게요")
    let controller = SpeechInputController { session }

    await controller.start()
    session.send(.routeChanged)
    await drainTasks()

    XCTAssertEqual(session.finishCallCount, 1)
    XCTAssertEqual(controller.displayTranscript, "차분하게 시작할게요")
    XCTAssertEqual(controller.phase, .paused)
  }

  func testRecognizedSpeechStartsThreeSecondSilenceForAutomaticCompletion() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(
      silenceScheduler: scheduler
    ) {
      session
    }

    await controller.start()
    XCTAssertEqual(scheduler.scheduledDelay, 30)
    XCTAssertEqual(
      controller.speechActivityState,
      .awaitingRecognizedSpeech
    )

    session.send(.transcript("정리했어", isFinal: true))
    XCTAssertEqual(scheduler.scheduledDelay, 3)
    XCTAssertEqual(controller.speechActivityState, .recognizedSpeech)
    XCTAssertEqual(controller.phase, .listening)
    XCTAssertNil(controller.latestSilenceCompletion)
    scheduler.fire()

    XCTAssertEqual(
      controller.latestSilenceCompletion?.transcript,
      "정리했어"
    )
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertEqual(session.cancelCallCount, 1)
  }

  func testThirtySecondNoSpeechTimeoutRemainsRetryableFailure() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(
      silenceScheduler: scheduler
    ) {
      session
    }

    await controller.start()
    XCTAssertEqual(scheduler.scheduledDelay, 30)
    scheduler.fire()

    XCTAssertEqual(controller.phase, .failed(.silence))
    XCTAssertNil(controller.latestSilenceCompletion)
  }

  func testAmbientNoiseDoesNotDelayInitialNoSpeechTimeout() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      session
    }

    await controller.start()
    session.send(.audioLevels(Array(repeating: 1, count: 20)))

    XCTAssertEqual(scheduler.scheduleCallCount, 1)
    XCTAssertEqual(scheduler.scheduledDelay, 30)
    XCTAssertEqual(
      controller.speechActivityState,
      .awaitingRecognizedSpeech
    )
    controller.cancel()
  }

  func testChangedRecognizedSpeechRestartsPostSpeechSilenceDeadline() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      session
    }

    await controller.start()
    session.send(.transcript("오늘", isFinal: false))
    session.send(.transcript("오늘의 다짐", isFinal: false))

    XCTAssertEqual(scheduler.scheduleCallCount, 3)
    XCTAssertEqual(scheduler.scheduledDelay, 3)
    scheduler.fire()

    XCTAssertEqual(
      controller.latestSilenceCompletion?.transcript,
      "오늘의 다짐"
    )
    XCTAssertEqual(controller.phase, .idle)
  }

  func testResumeWaitsForNewRecognizedSpeechBeforePostSpeechDeadline() async {
    let firstSession = SpeechInputSessionSpy(finishTranscript: "첫 문장")
    let secondSession = SpeechInputSessionSpy()
    let factory = SpeechInputSessionFactory(
      sessions: [firstSession, secondSession]
    )
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      factory.makeSession()
    }

    await controller.start()
    await controller.pause()
    await controller.resume()

    XCTAssertEqual(controller.phase, .listening)
    XCTAssertEqual(scheduler.scheduledDelay, 30)
    XCTAssertEqual(
      controller.speechActivityState,
      .awaitingRecognizedSpeech
    )
    scheduler.fire()

    XCTAssertEqual(controller.phase, .failed(.silence))
    XCTAssertNil(controller.latestSilenceCompletion)
  }

  func testAmbientNoiseAndDuplicatePartialResultsDoNotDelayPostSpeechCompletion() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      session
    }

    await controller.start()
    session.send(.transcript("오늘의 다짐", isFinal: false))
    session.send(.audioLevels(Array(repeating: 1, count: 20)))
    session.send(.transcript("오늘의 다짐", isFinal: false))
    session.send(.transcript("오늘의 다짐", isFinal: true))

    XCTAssertEqual(scheduler.scheduleCallCount, 2)
    XCTAssertEqual(scheduler.scheduledDelay, 3)
    scheduler.fire()

    XCTAssertEqual(
      controller.latestSilenceCompletion?.transcript,
      "오늘의 다짐"
    )
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertEqual(session.cancelCallCount, 1)
  }

  func testSustainedVoiceActivityWaitsForVoiceEndThenCompletesAfterThreeSeconds()
    async
  {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let clock = ManualSpeechClock()
    let controller = SpeechInputController(
      silenceScheduler: scheduler,
      timeProvider: clock
    ) {
      session
    }

    await controller.start()
    session.send(.transcript("오늘의 다짐", isFinal: false))
    sendSustainedAudio(from: session, using: clock)

    XCTAssertEqual(
      controller.speechActivityState,
      .sustainedVoiceActivity
    )
    XCTAssertEqual(scheduler.scheduledDelay, 8)
    let scheduleCountWhileSpeaking = scheduler.scheduleCallCount

    sendSustainedAudio(from: session, using: clock, frameCount: 24)
    XCTAssertEqual(scheduler.scheduleCallCount, scheduleCountWhileSpeaking)

    sendQuietAudio(from: session, using: clock)
    XCTAssertEqual(controller.speechActivityState, .recognizedSpeech)
    XCTAssertEqual(scheduler.scheduledDelay, 3)

    scheduler.fire()
    XCTAssertEqual(
      controller.latestSilenceCompletion?.transcript,
      "오늘의 다짐"
    )
    XCTAssertEqual(controller.phase, .idle)
  }

  func testContinuousAmbientSoundCannotInfinitelyExtendPostSpeechDeadline()
    async
  {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let clock = ManualSpeechClock()
    let controller = SpeechInputController(
      silenceScheduler: scheduler,
      timeProvider: clock
    ) {
      session
    }

    await controller.start()
    session.send(.transcript("응답", isFinal: false))
    sendSustainedAudio(from: session, using: clock)
    let scheduleCountAfterVoiceEpisode = scheduler.scheduleCallCount

    // A constant loud background has no new episode boundary, so it cannot
    // repeatedly re-arm the deadline.
    sendSustainedAudio(from: session, using: clock, frameCount: 160)
    XCTAssertEqual(
      scheduler.scheduleCallCount,
      scheduleCountAfterVoiceEpisode
    )
    XCTAssertEqual(scheduler.scheduledDelay, 8)

    scheduler.fire()
    XCTAssertEqual(scheduler.scheduledDelay, 3)
    scheduler.fire()

    XCTAssertEqual(
      controller.latestSilenceCompletion?.transcript,
      "응답"
    )
    XCTAssertEqual(controller.phase, .idle)
  }

  func testSustainedAmbientSoundWithoutTranscriptKeepsNoSpeechPolicy() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let clock = ManualSpeechClock()
    let controller = SpeechInputController(
      silenceScheduler: scheduler,
      timeProvider: clock
    ) {
      session
    }

    await controller.start()
    sendSustainedAudio(from: session, using: clock)

    XCTAssertEqual(
      controller.speechActivityState,
      .sustainedVoiceActivity
    )
    XCTAssertEqual(scheduler.scheduleCallCount, 1)
    XCTAssertEqual(scheduler.scheduledDelay, 30)

    scheduler.fire()
    XCTAssertEqual(controller.phase, .failed(.silence))
    XCTAssertNil(controller.latestSilenceCompletion)
  }

  func testSeparatedAmbientNoiseBurstsDoNotBecomeSustainedVoiceActivity()
    async
  {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let clock = ManualSpeechClock()
    let controller = SpeechInputController(
      silenceScheduler: scheduler,
      timeProvider: clock
    ) {
      session
    }

    await controller.start()
    session.send(.audioLevels(Array(repeating: 0.8, count: 20)))
    clock.advance(by: 1)
    session.send(.audioLevels(Array(repeating: 0.8, count: 20)))

    XCTAssertEqual(
      controller.speechActivityState,
      .awaitingRecognizedSpeech
    )
    XCTAssertEqual(scheduler.scheduleCallCount, 1)
    XCTAssertEqual(scheduler.scheduledDelay, 30)
  }

  func testCancelledDeadlineCannotCompleteRestartedListeningAttempt() async {
    let firstSession = SpeechInputSessionSpy()
    let secondSession = SpeechInputSessionSpy()
    let factory = SpeechInputSessionFactory(
      sessions: [firstSession, secondSession]
    )
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      factory.makeSession()
    }

    await controller.start()
    firstSession.send(.transcript("첫 번째 입력", isFinal: false))
    controller.cancel()
    await controller.start()
    scheduler.fireMostRecentlyCancelledAction()

    XCTAssertEqual(controller.phase, .listening)
    XCTAssertNil(controller.latestSilenceCompletion)
    XCTAssertEqual(secondSession.cancelCallCount, 0)
    controller.cancel()
  }

  func testCancelForSkipOrScreenExitInvalidatesScheduledSilenceDeadline() async {
    let session = SpeechInputSessionSpy()
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      session
    }

    await controller.start()
    session.send(.transcript("건너뛰기 전 입력", isFinal: false))
    controller.cancel()
    scheduler.fireMostRecentlyCancelledAction()

    XCTAssertEqual(controller.phase, .idle)
    XCTAssertEqual(session.cancelCallCount, 1)
    XCTAssertNil(controller.latestSilenceCompletion)
  }

  func testNoInputSequenceRemindsThenSkipsAndResetsAfterSpeech() {
    var sequence = SpeechNoInputSequence()

    XCTAssertEqual(sequence.actionForTimeout(), .playReminder)
    XCTAssertEqual(sequence.actionForTimeout(), .automaticSkip)

    sequence.speechWasDetected()

    XCTAssertEqual(sequence.actionForTimeout(), .playReminder)
  }

  func testTwoNoSpeechAttemptsDriveReminderThenAutomaticSkip() async {
    let firstSession = SpeechInputSessionSpy()
    let secondSession = SpeechInputSessionSpy()
    let factory = SpeechInputSessionFactory(
      sessions: [firstSession, secondSession]
    )
    let scheduler = ManualSpeechSilenceScheduler()
    let controller = SpeechInputController(silenceScheduler: scheduler) {
      factory.makeSession()
    }
    var sequence = SpeechNoInputSequence()

    await controller.start()
    scheduler.fire()

    XCTAssertEqual(controller.phase, .failed(.silence))
    XCTAssertEqual(sequence.actionForTimeout(), .playReminder)

    await controller.retry()
    XCTAssertEqual(scheduler.scheduledDelay, 30)
    scheduler.fire()

    XCTAssertEqual(controller.phase, .failed(.silence))
    XCTAssertEqual(sequence.actionForTimeout(), .automaticSkip)
    XCTAssertEqual(firstSession.cancelCallCount, 1)
    XCTAssertEqual(secondSession.cancelCallCount, 1)
  }

  func testMicrophonePermissionDenialRemainsSettingsFailure() async {
    let session = SpeechInputSessionSpy(
      startError: AppleSpeechRecognitionSessionError.microphonePermissionDenied
    )
    let controller = SpeechInputController { session }

    await controller.start()

    XCTAssertEqual(controller.phase, .failed(.microphonePermissionDenied))
    XCTAssertEqual(session.cancelCallCount, 1)
    XCTAssertEqual(
      controller.statusText,
      "마이크 권한이 필요해요. 설정에서 허용해 주세요."
    )
  }

  func testCancelWhileStartIsPreparingDoesNotResurrectListeningState() async {
    let session = SuspendedStartSpeechInputSessionSpy()
    let controller = SpeechInputController { session }
    let startTask = Task {
      await controller.start()
    }

    await session.waitUntilStartWasCalled()
    controller.cancel()
    session.completeStart()
    await startTask.value

    XCTAssertEqual(session.cancelCallCount, 1)
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertFalse(controller.isPreparing)
  }

  private func drainTasks() async {
    for _ in 0..<10 {
      await Task.yield()
    }
  }

  private func sendSustainedAudio(
    from session: SpeechInputSessionSpy,
    using clock: ManualSpeechClock,
    frameCount: Int = 10
  ) {
    for _ in 0..<frameCount {
      session.send(.audioLevels(Array(repeating: 0.8, count: 20)))
      clock.advance(by: 0.05)
    }
  }

  private func sendQuietAudio(
    from session: SpeechInputSessionSpy,
    using clock: ManualSpeechClock,
    frameCount: Int = 5
  ) {
    for _ in 0..<frameCount {
      session.send(.audioLevels(Array(repeating: 0.01, count: 20)))
      clock.advance(by: 0.05)
    }
  }
}

@MainActor
private final class ManualSpeechSilenceScheduler: SpeechSilenceScheduling {
  private var action: (@MainActor () -> Void)?
  private var cancelledActions: [@MainActor () -> Void] = []
  private(set) var scheduledDelay: TimeInterval?
  private(set) var scheduleCallCount = 0

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) {
    cancel()
    scheduledDelay = delay
    scheduleCallCount += 1
    self.action = action
  }

  func cancel() {
    if let action {
      cancelledActions.append(action)
    }
    action = nil
    scheduledDelay = nil
  }

  func fire() {
    let pendingAction = action
    action = nil
    scheduledDelay = nil
    pendingAction?()
  }

  func fireMostRecentlyCancelledAction() {
    cancelledActions.popLast()?()
  }
}

@MainActor
private final class ManualSpeechClock: SpeechInputTimeProviding {
  private(set) var currentDate = Date(timeIntervalSinceReferenceDate: 0)
  var now: Date { currentDate }

  func advance(by interval: TimeInterval) {
    currentDate = currentDate.addingTimeInterval(interval)
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

@MainActor
private final class SuspendedStartSpeechInputSessionSpy: SpeechInputSession {
  var eventHandler: ((SpeechInputSessionEvent) -> Void)?
  private(set) var cancelCallCount = 0
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func start() async throws {
    let waiters = startWaiters
    startWaiters = []
    waiters.forEach { $0.resume() }

    await withCheckedContinuation { continuation in
      startContinuation = continuation
    }
  }

  func finish() async throws -> String {
    ""
  }

  func cancel() {
    cancelCallCount += 1
  }

  func waitUntilStartWasCalled() async {
    if startContinuation != nil {
      return
    }

    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func completeStart() {
    startContinuation?.resume()
    startContinuation = nil
  }
}
