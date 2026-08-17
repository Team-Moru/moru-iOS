//
//  RoutineAudioSessionCoordinator.swift
//  Moru
//

import AVFAudio

@MainActor
protocol RoutineSystemSpeechAnnouncing: AnyObject {
  func announceCountdown(_ seconds: Int)
  func announceNoSpeechReminder() async -> GuidancePlaybackResult
  func stop()
}

/// Fixed runtime prompts are explicit cues, not fallback speech for missing
/// routine-specific guidance audio.
@MainActor
final class SystemRoutineSpeechAnnouncer:
  NSObject,
  RoutineSystemSpeechAnnouncing,
  AVSpeechSynthesizerDelegate {
  private struct PendingReminder {
    let utteranceID: ObjectIdentifier
    let continuation: CheckedContinuation<GuidancePlaybackResult, Never>
  }

  private let synthesizer: AVSpeechSynthesizer
  private let audioSession: AVAudioSession
  private var pendingReminder: PendingReminder?

  init(
    synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
    audioSession: AVAudioSession = .sharedInstance()
  ) {
    self.synthesizer = synthesizer
    self.audioSession = audioSession
    super.init()
    self.synthesizer.delegate = self
  }

  func announceCountdown(_ seconds: Int) {
    guard (1...5).contains(seconds) else {
      return
    }

    speak("\(seconds)")
  }

  func announceNoSpeechReminder() async -> GuidancePlaybackResult {
    let utterance = makeUtterance(
      text: "아직 음성이 들리지 않아요. 준비되면 말해 주세요."
    )
    let utteranceID = ObjectIdentifier(utterance)

    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(returning: .cancelled)
          return
        }

        cancelPendingReminder()
        pendingReminder = PendingReminder(
          utteranceID: utteranceID,
          continuation: continuation
        )
        speak(utterance)
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancelPendingReminder(matching: utteranceID)
      }
    }
  }

  func stop() {
    let pendingContinuation = takePendingReminder()
    synthesizer.stopSpeaking(at: .immediate)
    deactivateAudioSession()
    pendingContinuation?.resume(returning: .cancelled)
  }

  private func speak(_ text: String) {
    speak(makeUtterance(text: text))
  }

  private func speak(_ utterance: AVSpeechUtterance) {
    cancelPendingReminder(unlessMatching: ObjectIdentifier(utterance))
    synthesizer.stopSpeaking(at: .immediate)
    try? audioSession.setCategory(
      .playback,
      mode: .spokenAudio,
      options: [.duckOthers]
    )
    try? audioSession.setActive(true)
    synthesizer.speak(utterance)
  }

  private func makeUtterance(text: String) -> AVSpeechUtterance {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
    utterance.rate = 0.48
    return utterance
  }

  private func cancelPendingReminder(
    matching utteranceID: ObjectIdentifier? = nil
  ) {
    guard let pendingReminder,
          utteranceID.map({ $0 == pendingReminder.utteranceID }) ?? true else {
      return
    }

    self.pendingReminder = nil
    synthesizer.stopSpeaking(at: .immediate)
    deactivateAudioSession()
    pendingReminder.continuation.resume(returning: .cancelled)
  }

  private func cancelPendingReminder(
    unlessMatching utteranceID: ObjectIdentifier
  ) {
    guard pendingReminder?.utteranceID != utteranceID else {
      return
    }

    cancelPendingReminder()
  }

  private func takePendingReminder()
    -> CheckedContinuation<GuidancePlaybackResult, Never>? {
    let continuation = pendingReminder?.continuation
    pendingReminder = nil
    return continuation
  }

  private func finishPendingReminder(
    matching utteranceID: ObjectIdentifier,
    result: GuidancePlaybackResult
  ) {
    guard pendingReminder?.utteranceID == utteranceID else {
      return
    }

    let continuation = takePendingReminder()
    deactivateAudioSession()
    continuation?.resume(returning: result)
  }

  private func deactivateAudioSession() {
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.finishPendingReminder(
        matching: utteranceID,
        result: .completed
      )
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.finishPendingReminder(
        matching: utteranceID,
        result: .cancelled
      )
    }
  }
}

enum GuidancePlaybackResult: Equatable {
  case completed
  case cancelled
  /// A server-required cue has no truthful bundled replacement and could not
  /// be prepared or played. The UI must offer an explicit retry or opt-out.
  case unavailable
}

/// Carries the local identities needed to select an already-warmed remote
/// intro. A synced server intro may prohibit a bundled fallback so a selected
/// server voice can never silently become the device voice.
struct RoutineGuidanceCueRequest: Equatable {
  let routineGroupLocalID: UUID?
  let routineLocalID: UUID?
  let routineTitle: String?
  let routineType: RoutineStepType?
  let fallbackItemID: String?
  let voiceCode: String
  let kind: RoutineAudioCueKind
  let requiresServerGeneratedIntro: Bool

  init(
    routineGroupLocalID: UUID? = nil,
    routineLocalID: UUID? = nil,
    routineTitle: String? = nil,
    routineType: RoutineStepType? = nil,
    fallbackItemID: String?,
    voiceCode: String,
    kind: RoutineAudioCueKind,
    requiresServerGeneratedIntro: Bool = false
  ) {
    self.routineGroupLocalID = routineGroupLocalID
    self.routineLocalID = routineLocalID
    self.routineTitle = routineTitle
    self.routineType = routineType
    self.fallbackItemID = fallbackItemID
    self.voiceCode = voiceCode
    self.kind = kind
    self.requiresServerGeneratedIntro = requiresServerGeneratedIntro
  }
}

@MainActor
protocol GuidancePlaybackControlling {
  func stopAndWaitUntilIdle() async
  func resumeAfterSpeechInput()
}

@MainActor
protocol RoutineGuidancePlaying: GuidancePlaybackControlling {
  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async -> GuidancePlaybackResult
  func play(_ request: RoutineGuidanceCueRequest) async -> GuidancePlaybackResult
  func stop()
}

extension RoutineGuidancePlaying {
  func play(_ request: RoutineGuidanceCueRequest) async -> GuidancePlaybackResult {
    guard let itemID = request.fallbackItemID else {
      return .unavailable
    }

    return await play(
      itemID: itemID,
      voiceCode: request.voiceCode,
      kind: request.kind
    )
  }
}

@MainActor
final class NoopRoutineGuidancePlayer: RoutineGuidancePlaying {
  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async -> GuidancePlaybackResult {
    .completed
  }

  func stop() {}

  func stopAndWaitUntilIdle() async {}

  func resumeAfterSpeechInput() {}
}

@MainActor
final class RoutineAudioSessionCoordinator {
  private let guidancePlayback: any GuidancePlaybackControlling
  private let audioSession: AVAudioSession
  private var isSpeechInputActive = false

  init(
    guidancePlayback: any GuidancePlaybackControlling = NoopRoutineGuidancePlayer(),
    audioSession: AVAudioSession = .sharedInstance()
  ) {
    self.guidancePlayback = guidancePlayback
    self.audioSession = audioSession
  }

  func activateForSpeechInput() async throws {
    await guidancePlayback.stopAndWaitUntilIdle()

    do {
      try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
      try audioSession.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
      )
      try audioSession.setActive(true)
      isSpeechInputActive = true
    } catch {
      try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
      guidancePlayback.resumeAfterSpeechInput()
      throw error
    }
  }

  func deactivateSpeechInput() {
    guard isSpeechInputActive else {
      return
    }

    isSpeechInputActive = false
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    guidancePlayback.resumeAfterSpeechInput()
  }
}
