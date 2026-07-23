//
//  BundledRoutineGuidancePlayer.swift
//  Moru
//

import AVFAudio
import Foundation
import Observation

@MainActor
@Observable
final class RoutineGuidancePlaybackState {
  private(set) var isPlaying = false

  func update(isPlaying: Bool) {
    self.isPlaying = isPlaying
  }
}

@MainActor
final class BundledRoutineGuidancePlayer: NSObject, RoutineGuidancePlaying {
  private let resourceLoader: RoutineAudioResourceLoader
  private let playbackState: RoutineGuidancePlaybackState
  private let audioSession: AVAudioSession

  private var audioPlayer: AVAudioPlayer?
  private var ownsAudioSession = false
  private var isSuspendedForSpeechInput = false

  init(
    resourceLoader: RoutineAudioResourceLoader,
    playbackState: RoutineGuidancePlaybackState,
    audioSession: AVAudioSession = .sharedInstance()
  ) {
    self.resourceLoader = resourceLoader
    self.playbackState = playbackState
    self.audioSession = audioSession
    super.init()
  }

  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async {
    guard !isSuspendedForSpeechInput else {
      return
    }

    stop()

    do {
      guard let cue = try resourceLoader.cue(
        itemID: itemID,
        voiceCode: voiceCode,
        kind: kind
      ),
      let resourceURL = resourceLoader.resourceURL(for: cue) else {
        return
      }

      try configureAudioSession()
      ownsAudioSession = true
      let player = try AVAudioPlayer(contentsOf: resourceURL)
      player.delegate = self
      player.prepareToPlay()

      guard player.play() else {
        finishPlayback()
        return
      }

      audioPlayer = player
      playbackState.update(isPlaying: true)
    } catch {
      finishPlayback()
    }
  }

  func stop() {
    audioPlayer?.stop()
    finishPlayback()
  }

  func stopAndWaitUntilIdle() async {
    isSuspendedForSpeechInput = true
    stop()
    await Task.yield()
  }

  func resumeAfterSpeechInput() {
    isSuspendedForSpeechInput = false
  }

  private func configureAudioSession() throws {
    try audioSession.setCategory(
      .playback,
      mode: .spokenAudio,
      options: [.duckOthers]
    )
    try audioSession.setActive(true)
  }

  private func finishPlayback() {
    audioPlayer?.delegate = nil
    audioPlayer = nil
    playbackState.update(isPlaying: false)
    if ownsAudioSession {
      ownsAudioSession = false
      deactivateAudioSession()
    }
  }

  private func deactivateAudioSession() {
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }
}

extension BundledRoutineGuidancePlayer: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(
    _ player: AVAudioPlayer,
    successfully flag: Bool
  ) {
    let playerIdentifier = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let audioPlayer = self?.audioPlayer,
            ObjectIdentifier(audioPlayer) == playerIdentifier else {
        return
      }

      self?.finishPlayback()
    }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(
    _ player: AVAudioPlayer,
    error: Error?
  ) {
    let playerIdentifier = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let audioPlayer = self?.audioPlayer,
            ObjectIdentifier(audioPlayer) == playerIdentifier else {
        return
      }

      self?.finishPlayback()
    }
  }
}
