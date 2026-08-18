//
//  SpeechInputController.swift
//  Moru
//

import Foundation
import Observation

enum SpeechInputFailure: Equatable {
  case microphonePermissionDenied
  case transcriberUnavailable
  case localeUnavailable
  case modelDownloadFailed
  case audioSession
  case recognition
  case silence
}

@MainActor
enum SpeechInputSessionEvent {
  case transcript(String, isFinal: Bool)
  case audioLevels([Float])
  case interrupted
  case routeChanged
  case failed(SpeechInputFailure)
}

struct SpeechTranscriptUpdate: Equatable {
  let text: String
  let isFinal: Bool
}

struct SpeechSilenceCompletion: Equatable {
  let id: UUID
  let transcript: String
}

@MainActor
protocol SpeechSilenceScheduling: AnyObject {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  )
  func cancel()
}

@MainActor
protocol SpeechInputTimeProviding: AnyObject {
  var now: Date { get }
}

@MainActor
final class SystemSpeechInputTimeProvider: SpeechInputTimeProviding {
  var now: Date {
    Date()
  }
}

@MainActor
final class TaskSpeechSilenceScheduler: SpeechSilenceScheduling {
  private var task: Task<Void, Never>?

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) {
    cancel()

    task = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .seconds(max(delay, 0)))
      } catch {
        return
      }

      guard !Task.isCancelled else {
        return
      }

      self?.task = nil
      action()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}

@MainActor
protocol SpeechInputSession: AnyObject {
  var eventHandler: ((SpeechInputSessionEvent) -> Void)? { get set }

  func start() async throws
  func finish() async throws -> String
  func cancel()
}

@MainActor
@Observable
final class SpeechInputController {
  enum Phase: Equatable {
    case idle
    case listening
    case paused
    case finishing
    case failed(SpeechInputFailure)
  }

  enum SpeechActivityState: Equatable {
    case awaitingRecognizedSpeech
    case recognizedSpeech
    case sustainedVoiceActivity
  }

  private enum Metric {
    static let waveformUpdateInterval: TimeInterval = 0.05
    static let audibleLevelThreshold: Float = 0.12
    static let sustainedVoiceActivityDuration: TimeInterval = 0.4
    static let sustainedVoiceQuietDuration: TimeInterval = 0.15
    static let maximumVoiceActivityFrameGap: TimeInterval = 0.2
    /// Energy alone cannot identify a person with certainty. Keep a
    /// continuously noisy microphone from postponing automatic completion
    /// indefinitely while still allowing a spoken phrase to finish.
    static let maximumSustainedVoiceActivityDuration: TimeInterval = 8
  }

  private let makeSession: @MainActor () -> any SpeechInputSession
  private let timeProvider: any SpeechInputTimeProviding
  private let postSpeechSilenceTimeout: TimeInterval
  private let noSpeechTimeout: TimeInterval
  private let silenceScheduler: any SpeechSilenceScheduling
  private var session: (any SpeechInputSession)?
  private var activeAttemptID: UUID?
  private var levelProcessor = SpeechAudioLevelProcessor()
  private var committedSegments: [String] = []
  private var currentFinalTranscript = ""
  private var currentVolatileTranscript = ""
  private var lastWaveformUpdate = Date.distantPast
  private var silenceDeadlineID: UUID?
  private var audibleActivityStartedAt: Date?
  private var lastAudibleActivityAt: Date?
  private var quietActivityStartedAt: Date?
  private var isSustainedVoiceActivity = false

  private(set) var phase: Phase = .idle
  private(set) var isPreparing = false
  private(set) var waveformLevels = Array(repeating: CGFloat.zero, count: 20)
  private(set) var displayTranscript = ""
  private(set) var latestFinalTranscript = ""
  private(set) var latestTranscriptUpdate: SpeechTranscriptUpdate?
  private(set) var latestSilenceCompletion: SpeechSilenceCompletion?
  private(set) var speechActivityState: SpeechActivityState = .awaitingRecognizedSpeech

  init(
    silenceTimeout: TimeInterval = 3,
    noSpeechTimeout: TimeInterval = 30,
    silenceScheduler: any SpeechSilenceScheduling = TaskSpeechSilenceScheduler(),
    timeProvider: any SpeechInputTimeProviding =
      SystemSpeechInputTimeProvider(),
    makeSession: @escaping @MainActor () -> any SpeechInputSession = {
      AppleSpeechRecognitionSession()
    }
  ) {
    self.postSpeechSilenceTimeout = silenceTimeout
    self.noSpeechTimeout = noSpeechTimeout
    self.silenceScheduler = silenceScheduler
    self.timeProvider = timeProvider
    self.makeSession = makeSession
  }

  var statusText: String {
    if isPreparing {
      return "음성 인식 준비 중…"
    }

    switch phase {
    case .idle:
      return ""
    case .listening:
      return "음성 인식 중"
    case .paused:
      return "음성 인식 일시정지"
    case .finishing:
      return "음성 인식 마무리 중…"
    case .failed(let failure):
      return message(for: failure)
    }
  }

  var shouldShowControls: Bool {
    isPreparing || phase == .listening || phase == .paused || phase == .finishing
  }

  var isPaused: Bool {
    phase == .paused
  }

  var isFinishing: Bool {
    phase == .finishing
  }

  func start() async {
    guard phase == .idle, !isPreparing else {
      return
    }

    let attemptID = UUID()
    activeAttemptID = attemptID
    isPreparing = true
    latestSilenceCompletion = nil
    cancelSilenceDeadline()
    resetCurrentSegment()
    resetVoiceActivity()

    let newSession = makeSession()
    newSession.eventHandler = { [weak self] event in
      self?.handle(event, for: attemptID)
    }
    session = newSession

    do {
      try await newSession.start()
      guard activeAttemptID == attemptID else {
        return
      }

      isPreparing = false
      phase = .listening
      scheduleNoSpeechDeadline(for: attemptID)
    } catch {
      guard activeAttemptID == attemptID else {
        return
      }

      newSession.eventHandler = nil
      newSession.cancel()
      cancelSilenceDeadline()
      isPreparing = false
      session = nil
      activeAttemptID = nil
      resetVoiceActivity()
      phase = .failed(failure(from: error))
    }
  }

  func pause() async {
    guard
      phase == .listening,
      let session,
      let attemptID = activeAttemptID
    else {
      return
    }

    cancelSilenceDeadline()
    phase = .finishing

    do {
      let transcript = try await session.finish()
      guard activeAttemptID == attemptID else {
        return
      }

      appendCommittedSegment(transcript)
      session.eventHandler = nil
      self.session = nil
      phase = .paused
    } catch {
      guard activeAttemptID == attemptID else {
        return
      }

      session.eventHandler = nil
      session.cancel()
      self.session = nil
      activeAttemptID = nil
      phase = .failed(failure(from: error))
    }
  }

  func resume() async {
    guard phase == .paused else {
      return
    }

    phase = .idle
    await start()
  }

  func finish() async -> String? {
    switch phase {
    case .paused:
      let transcript = joinedTranscript()
      resetAfterFinish()
      return transcript.isEmpty ? nil : transcript

    case .listening:
      break

    case .idle, .finishing, .failed:
      return nil
    }

    guard let session, let attemptID = activeAttemptID else {
      return nil
    }

    cancelSilenceDeadline()
    phase = .finishing

    do {
      let transcript = try await session.finish()
      guard activeAttemptID == attemptID else {
        return nil
      }

      appendCommittedSegment(transcript)
      session.eventHandler = nil
      self.session = nil
      let finalTranscript = joinedTranscript()
      resetAfterFinish()
      return finalTranscript.isEmpty ? nil : finalTranscript
    } catch {
      guard activeAttemptID == attemptID else {
        return nil
      }

      session.eventHandler = nil
      session.cancel()
      self.session = nil
      activeAttemptID = nil
      phase = .failed(failure(from: error))
      return nil
    }
  }

  func finishImmediately(using transcript: String) -> String? {
    guard phase == .listening else {
      return nil
    }

    let completedSegment = cleaned(transcript)
    guard !completedSegment.isEmpty else {
      return nil
    }

    activeAttemptID = nil
    cancelSilenceDeadline()
    phase = .finishing

    session?.cancel()
    session = nil

    let finalTranscript = (committedSegments + [completedSegment])
      .map(cleaned)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    resetAfterFinish()
    return finalTranscript.isEmpty ? nil : finalTranscript
  }

  func cancel() {
    activeAttemptID = nil
    cancelSilenceDeadline()
    session?.eventHandler = nil
    session?.cancel()
    session = nil
    committedSegments = []
    latestSilenceCompletion = nil
    resetCurrentSegment()
    levelProcessor.reset()
    waveformLevels = levelProcessor.levels
    lastWaveformUpdate = .distantPast
    resetVoiceActivity()
    isPreparing = false
    phase = .idle
  }

  func retry() async {
    cancel()
    await start()
  }

  private func handle(_ event: SpeechInputSessionEvent, for attemptID: UUID) {
    guard activeAttemptID == attemptID else {
      return
    }

    switch event {
    case .transcript(let transcript, let isFinal):
      let previousTranscript = joinedTranscript()
      let cleanedTranscript = cleaned(transcript)
      if isFinal {
        currentFinalTranscript = cleanedTranscript
        latestFinalTranscript = currentFinalTranscript
        currentVolatileTranscript = ""
      } else {
        currentVolatileTranscript = cleanedTranscript
      }
      latestTranscriptUpdate = SpeechTranscriptUpdate(
        text: cleanedTranscript,
        isFinal: isFinal
      )
      updateDisplayTranscript()
      let currentTranscript = joinedTranscript()
      if isRecognizedSpeechActivity(
        from: previousTranscript,
        to: currentTranscript
      ) {
        if isSustainedVoiceActivity {
          scheduleSustainedVoiceSafetyDeadline(for: attemptID)
        } else {
          speechActivityState = .recognizedSpeech
          schedulePostSpeechSilenceDeadline(for: attemptID)
        }
      }

    case .audioLevels(let levels):
      let currentDate = timeProvider.now
      guard currentDate.timeIntervalSince(lastWaveformUpdate)
        >= Metric.waveformUpdateInterval else {
        return
      }

      lastWaveformUpdate = currentDate
      _ = levelProcessor.append(normalizedLevels: levels)
      waveformLevels = levelProcessor.levels
      updateVoiceActivity(
        with: levels,
        at: currentDate,
        for: attemptID
      )

    case .interrupted, .routeChanged:
      Task { [weak self] in
        await self?.pause()
      }

    case .failed(let failure):
      guard phase != .finishing else {
        return
      }

      let failedSession = session
      session = nil
      activeAttemptID = nil
      cancelSilenceDeadline()
      failedSession?.eventHandler = nil
      failedSession?.cancel()
      resetVoiceActivity()
      phase = .failed(failure)
    }
  }

  private func scheduleNoSpeechDeadline(for attemptID: UUID) {
    scheduleDeadline(after: noSpeechTimeout, for: attemptID) { [weak self] in
      self?.finishForSilenceDeadline()
    }
  }

  private func schedulePostSpeechSilenceDeadline(for attemptID: UUID) {
    scheduleDeadline(
      after: postSpeechSilenceTimeout,
      for: attemptID
    ) { [weak self] in
      self?.finishForSilenceDeadline()
    }
  }

  private func scheduleSustainedVoiceSafetyDeadline(for attemptID: UUID) {
    scheduleDeadline(
      after: Metric.maximumSustainedVoiceActivityDuration,
      for: attemptID
    ) { [weak self] in
      guard let self else {
        return
      }

      // A microphone level cannot distinguish every persistent ambient sound
      // from a voice. Finish this one bounded activity window, then begin the
      // ordinary three-second quiet period instead of rearming forever.
      self.endSustainedVoiceActivity()
      self.schedulePostSpeechSilenceDeadline(for: attemptID)
    }
  }

  private func scheduleDeadline(
    after delay: TimeInterval,
    for attemptID: UUID,
    action: @escaping @MainActor () -> Void
  ) {
    let deadlineID = UUID()
    silenceDeadlineID = deadlineID

    silenceScheduler.schedule(after: delay) { [weak self] in
      guard let self,
            self.activeAttemptID == attemptID,
            self.silenceDeadlineID == deadlineID,
            self.phase == .listening else {
        return
      }

      self.silenceDeadlineID = nil
      action()
    }
  }

  private func finishForSilenceDeadline() {
    let transcript = joinedTranscript()
    let silentSession = session
    session = nil
    activeAttemptID = nil
    silentSession?.eventHandler = nil
    silentSession?.cancel()

    if speechActivityState == .awaitingRecognizedSpeech
      || transcript.isEmpty {
      resetVoiceActivity()
      phase = .failed(.silence)
    } else {
      resetAfterFinish()
      latestSilenceCompletion = SpeechSilenceCompletion(
        id: UUID(),
        transcript: transcript
      )
    }
  }

  private func cancelSilenceDeadline() {
    silenceDeadlineID = nil
    silenceScheduler.cancel()
  }

  private func isRecognizedSpeechActivity(
    from previousTranscript: String,
    to currentTranscript: String
  ) -> Bool {
    !currentTranscript.isEmpty && currentTranscript != previousTranscript
  }

  private func updateVoiceActivity(
    with levels: [Float],
    at date: Date,
    for attemptID: UUID
  ) {
    guard (levels.max() ?? .zero) >= Metric.audibleLevelThreshold else {
      registerQuietAudio(at: date, for: attemptID)
      return
    }

    let isContinuousAudioActivity: Bool
    if let lastAudibleActivityAt {
      isContinuousAudioActivity = date.timeIntervalSince(lastAudibleActivityAt)
        <= Metric.maximumVoiceActivityFrameGap
    } else {
      isContinuousAudioActivity = false
    }
    lastAudibleActivityAt = date
    quietActivityStartedAt = nil

    guard isContinuousAudioActivity else {
      if isSustainedVoiceActivity {
        endSustainedVoiceActivity()
      }
      audibleActivityStartedAt = date
      lastAudibleActivityAt = date
      return
    }

    if isSustainedVoiceActivity {
      return
    }

    guard let audibleActivityStartedAt else {
      self.audibleActivityStartedAt = date
      return
    }

    guard date.timeIntervalSince(audibleActivityStartedAt)
      >= Metric.sustainedVoiceActivityDuration else {
      return
    }

    isSustainedVoiceActivity = true
    speechActivityState = .sustainedVoiceActivity

    // Without a recognized transcript there is nothing valid to complete.
    // Keep the original no-speech deadline, so sustained ambient sound never
    // suppresses the existing reminder and automatic-skip policy.
    guard !joinedTranscript().isEmpty else {
      return
    }

    scheduleSustainedVoiceSafetyDeadline(for: attemptID)
  }

  private func registerQuietAudio(at date: Date, for attemptID: UUID) {
    lastAudibleActivityAt = nil

    guard isSustainedVoiceActivity else {
      audibleActivityStartedAt = nil
      quietActivityStartedAt = nil
      return
    }

    guard let quietActivityStartedAt else {
      self.quietActivityStartedAt = date
      return
    }

    guard date.timeIntervalSince(quietActivityStartedAt)
      >= Metric.sustainedVoiceQuietDuration else {
      return
    }

    endSustainedVoiceActivity()
    guard !joinedTranscript().isEmpty else {
      return
    }

    schedulePostSpeechSilenceDeadline(for: attemptID)
  }

  private func endSustainedVoiceActivity() {
    isSustainedVoiceActivity = false
    audibleActivityStartedAt = nil
    lastAudibleActivityAt = nil
    quietActivityStartedAt = nil
    speechActivityState = joinedTranscript().isEmpty
      ? .awaitingRecognizedSpeech
      : .recognizedSpeech
  }

  private func resetVoiceActivity() {
    audibleActivityStartedAt = nil
    lastAudibleActivityAt = nil
    quietActivityStartedAt = nil
    isSustainedVoiceActivity = false
    speechActivityState = .awaitingRecognizedSpeech
  }

  private func appendCommittedSegment(_ transcript: String) {
    let preferredTranscript = cleaned(transcript).isEmpty
      ? currentFinalTranscript
      : cleaned(transcript)
    let segment = cleaned(preferredTranscript)

    if !segment.isEmpty {
      committedSegments.append(segment)
    }

    resetCurrentSegment()
    updateDisplayTranscript()
  }

  private func resetCurrentSegment() {
    currentFinalTranscript = ""
    currentVolatileTranscript = ""
    latestFinalTranscript = ""
    latestTranscriptUpdate = nil
    updateDisplayTranscript()
  }

  private func updateDisplayTranscript() {
    let currentTranscript = currentVolatileTranscript.isEmpty
      ? currentFinalTranscript
      : currentVolatileTranscript
    displayTranscript = (committedSegments + [currentTranscript])
      .map(cleaned)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private func joinedTranscript() -> String {
    (committedSegments + [currentFinalTranscript, currentVolatileTranscript])
      .map(cleaned)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private func resetAfterFinish() {
    cancelSilenceDeadline()
    activeAttemptID = nil
    committedSegments = []
    resetCurrentSegment()
    levelProcessor.reset()
    waveformLevels = levelProcessor.levels
    lastWaveformUpdate = .distantPast
    resetVoiceActivity()
    phase = .idle
  }

  private func cleaned(_ transcript: String) -> String {
    transcript
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }

  private func failure(from error: Error) -> SpeechInputFailure {
    guard let error = error as? AppleSpeechRecognitionSessionError else {
      return .recognition
    }

    switch error {
    case .microphonePermissionDenied:
      return .microphonePermissionDenied
    case .transcriberUnavailable:
      return .transcriberUnavailable
    case .localeUnavailable:
      return .localeUnavailable
    case .modelDownloadFailed:
      return .modelDownloadFailed
    case .audioSession:
      return .audioSession
    case .recognition:
      return .recognition
    }
  }

  private func message(for failure: SpeechInputFailure) -> String {
    switch failure {
    case .microphonePermissionDenied:
      return "마이크 권한이 필요해요. 설정에서 허용해 주세요."
    case .transcriberUnavailable:
      return "이 기기에서는 음성 인식 기능을 사용할 수 없어요."
    case .localeUnavailable:
      return "이 기기에서는 한국어 음성 인식을 사용할 수 없어요."
    case .modelDownloadFailed:
      return "음성 인식 준비에 실패했어요. 네트워크를 확인해 주세요."
    case .audioSession:
      return "마이크를 시작할 수 없어요. 다시 시도해 주세요."
    case .recognition:
      return "음성 인식에 실패했어요. 다시 시도해 주세요."
    case .silence:
      return "음성이 들리지 않았어요. 다시 말해 주세요."
    }
  }
}
