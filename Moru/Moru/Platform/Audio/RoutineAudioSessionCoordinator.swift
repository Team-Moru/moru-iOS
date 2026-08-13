//
//  RoutineAudioSessionCoordinator.swift
//  Moru
//

import AVFAudio

enum GuidancePlaybackResult: Equatable {
  case completed
  case cancelled
}

/// Carries the local identities needed to select an already-warmed remote
/// intro while retaining the bundled cue as the fail-safe path.
struct RoutineGuidanceCueRequest: Equatable {
  let routineGroupLocalID: UUID?
  let routineLocalID: UUID?
  let routineTitle: String?
  let routineType: RoutineStepType?
  let fallbackItemID: String?
  let voiceCode: String
  let kind: RoutineAudioCueKind

  init(
    routineGroupLocalID: UUID? = nil,
    routineLocalID: UUID? = nil,
    routineTitle: String? = nil,
    routineType: RoutineStepType? = nil,
    fallbackItemID: String?,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) {
    self.routineGroupLocalID = routineGroupLocalID
    self.routineLocalID = routineLocalID
    self.routineTitle = routineTitle
    self.routineType = routineType
    self.fallbackItemID = fallbackItemID
    self.voiceCode = voiceCode
    self.kind = kind
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
      return .completed
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
