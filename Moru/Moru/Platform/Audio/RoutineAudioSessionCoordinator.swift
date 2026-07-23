//
//  RoutineAudioSessionCoordinator.swift
//  Moru
//

import AVFAudio

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
  ) async
  func stop()
}

@MainActor
final class NoopRoutineGuidancePlayer: RoutineGuidancePlaying {
  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async {}

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
