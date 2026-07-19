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

  private enum Metric {
    static let waveformUpdateInterval: TimeInterval = 0.05
    static let silenceTimeout: TimeInterval = 8
    static let audibleLevelThreshold: Float = 0.12
  }

  private let makeSession: @MainActor () -> any SpeechInputSession
  private var session: (any SpeechInputSession)?
  private var activeAttemptID: UUID?
  private var levelProcessor = SpeechAudioLevelProcessor()
  private var committedSegments: [String] = []
  private var currentFinalTranscript = ""
  private var currentVolatileTranscript = ""
  private var lastWaveformUpdate = Date.distantPast
  private var lastAudibleAt = Date()
  private var lastTranscriptAt = Date()
  private var silenceTask: Task<Void, Never>?

  private(set) var phase: Phase = .idle
  private(set) var isPreparing = false
  private(set) var waveformLevels = Array(repeating: CGFloat.zero, count: 20)
  private(set) var displayTranscript = ""
  private(set) var latestFinalTranscript = ""

  init(
    makeSession: @escaping @MainActor () -> any SpeechInputSession = {
      AppleSpeechRecognitionSession()
    }
  ) {
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
    resetCurrentSegment()

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
      lastAudibleAt = Date()
      lastTranscriptAt = Date()
      startSilenceMonitoring(for: attemptID)
    } catch {
      guard activeAttemptID == attemptID else {
        return
      }

      isPreparing = false
      session = nil
      phase = .failed(failure(from: error))
    }
  }

  func pause() async {
    guard phase == .listening, let session else {
      return
    }

    silenceTask?.cancel()
    silenceTask = nil
    phase = .finishing

    do {
      let transcript = try await session.finish()
      appendCommittedSegment(transcript)
      self.session = nil
      phase = .paused
    } catch {
      self.session = nil
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

    guard let session else {
      return nil
    }

    silenceTask?.cancel()
    silenceTask = nil
    phase = .finishing

    do {
      let transcript = try await session.finish()
      appendCommittedSegment(transcript)
      self.session = nil
      let finalTranscript = joinedTranscript()
      resetAfterFinish()
      return finalTranscript.isEmpty ? nil : finalTranscript
    } catch {
      self.session = nil
      phase = .failed(failure(from: error))
      return nil
    }
  }

  func cancel() {
    activeAttemptID = nil
    silenceTask?.cancel()
    silenceTask = nil
    session?.cancel()
    session = nil
    committedSegments = []
    resetCurrentSegment()
    levelProcessor.reset()
    waveformLevels = levelProcessor.levels
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
      if isFinal {
        currentFinalTranscript = cleaned(transcript)
        latestFinalTranscript = currentFinalTranscript
        currentVolatileTranscript = ""
      } else {
        currentVolatileTranscript = cleaned(transcript)
      }
      lastTranscriptAt = Date()
      updateDisplayTranscript()

    case .audioLevels(let levels):
      guard Date().timeIntervalSince(lastWaveformUpdate) >= Metric.waveformUpdateInterval else {
        return
      }

      lastWaveformUpdate = Date()
      if (levels.max() ?? .zero) >= Metric.audibleLevelThreshold {
        lastAudibleAt = Date()
      }
      _ = levelProcessor.append(normalizedLevels: levels)
      waveformLevels = levelProcessor.levels

    case .interrupted, .routeChanged:
      Task { [weak self] in
        await self?.pause()
      }

    case .failed(let failure):
      guard phase != .finishing else {
        return
      }

      session = nil
      silenceTask?.cancel()
      silenceTask = nil
      phase = .failed(failure)
    }
  }

  private func startSilenceMonitoring(for attemptID: UUID) {
    silenceTask?.cancel()
    silenceTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self, self.activeAttemptID == attemptID, self.phase == .listening else {
          return
        }

        let now = Date()
        let lastActivity = max(self.lastAudibleAt, self.lastTranscriptAt)
        guard now.timeIntervalSince(lastActivity) >= Metric.silenceTimeout else {
          continue
        }

        self.session?.cancel()
        self.session = nil
        self.phase = .failed(.silence)
        return
      }
    }
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
    activeAttemptID = nil
    committedSegments = []
    resetCurrentSegment()
    levelProcessor.reset()
    waveformLevels = levelProcessor.levels
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
