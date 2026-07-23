//
//  RoutineGuidanceCoordinator.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineGuidanceDelaying {
  func wait(for delay: Duration) async throws
}

struct ContinuousRoutineGuidanceDelay: RoutineGuidanceDelaying {
  func wait(for delay: Duration) async throws {
    try await Task.sleep(for: delay)
  }
}

@MainActor
final class RoutineGuidanceCoordinator {
  private let player: any RoutineGuidancePlaying
  private let playbackState: RoutineGuidancePlaybackState
  private let voiceCode: String
  private let delay: any RoutineGuidanceDelaying

  private var generation = 0
  private var playTask: Task<Void, Never>?
  private var reminderTask: Task<Void, Never>?

  init(
    player: any RoutineGuidancePlaying = NoopRoutineGuidancePlayer(),
    playbackState: RoutineGuidancePlaybackState = RoutineGuidancePlaybackState(),
    voiceCode: String = VoiceProfile.aoede.assetVoiceCode,
    delay: any RoutineGuidanceDelaying = ContinuousRoutineGuidanceDelay()
  ) {
    self.player = player
    self.playbackState = playbackState
    self.voiceCode = voiceCode
    self.delay = delay
  }

  var isPlaying: Bool {
    playbackState.isPlaying
  }

  func stepDidStart(_ step: RoutineStep) {
    stopCurrentCue()

    guard let itemID = step.presetItemID else {
      return
    }

    let activeGeneration = generation
    playTask = Task { [weak self] in
      guard let self, activeGeneration == generation else {
        return
      }

      await player.play(
        itemID: itemID,
        voiceCode: voiceCode,
        kind: .intro
      )
    }

    guard let estimatedSeconds = step.estimatedSeconds, estimatedSeconds > 0 else {
      return
    }

    let halfwayDelay = Duration.milliseconds(estimatedSeconds * 500)
    reminderTask = Task { [weak self] in
      guard let self else {
        return
      }

      do {
        try await delay.wait(for: halfwayDelay)
      } catch {
        return
      }

      guard !Task.isCancelled, activeGeneration == generation else {
        return
      }

      await player.play(
        itemID: itemID,
        voiceCode: voiceCode,
        kind: .remind
      )
    }
  }

  func stepDidComplete(_ step: RoutineStep) {
    stopCurrentCue()

    guard let itemID = step.presetItemID else {
      return
    }

    let activeGeneration = generation
    playTask = Task { [weak self] in
      guard let self, activeGeneration == generation else {
        return
      }

      await player.play(
        itemID: itemID,
        voiceCode: voiceCode,
        kind: .done
      )
    }
  }

  func stop() {
    stopCurrentCue()
  }

  private func stopCurrentCue() {
    generation += 1
    playTask?.cancel()
    playTask = nil
    reminderTask?.cancel()
    reminderTask = nil
    player.stop()
  }
}
