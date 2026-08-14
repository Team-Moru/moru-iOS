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
  private let routineGroupLocalID: UUID?
  private weak var warmupCoordinator: (any RoutineTTSWarming)?
  private let delay: any RoutineGuidanceDelaying
  private let systemSpeechAnnouncer: any RoutineSystemSpeechAnnouncing

  private var generation = 0
  private var playTask: Task<GuidancePlaybackResult, Never>?
  private var reminderTask: Task<Void, Never>?

  init(
    player: any RoutineGuidancePlaying = NoopRoutineGuidancePlayer(),
    playbackState: RoutineGuidancePlaybackState = RoutineGuidancePlaybackState(),
    voiceCode: String = VoiceProfile.aoede.assetVoiceCode,
    routineGroupLocalID: UUID? = nil,
    warmupCoordinator: (any RoutineTTSWarming)? = nil,
    delay: any RoutineGuidanceDelaying = ContinuousRoutineGuidanceDelay(),
    systemSpeechAnnouncer: any RoutineSystemSpeechAnnouncing =
      SystemRoutineSpeechAnnouncer()
  ) {
    self.player = player
    self.playbackState = playbackState
    self.voiceCode = voiceCode
    self.routineGroupLocalID = routineGroupLocalID
    self.warmupCoordinator = warmupCoordinator
    self.delay = delay
    self.systemSpeechAnnouncer = systemSpeechAnnouncer
  }

  var isPlaying: Bool {
    playbackState.isPlaying
  }

  func stepDidStart(_ step: RoutineStep) {
    stopCurrentCue()

    guard step.presetItemID != nil || routineGroupLocalID != nil else {
      return
    }

    let requiresRemoteReadiness =
      step.presetItemID == nil && routineGroupLocalID != nil
    if let routineGroupLocalID, !requiresRemoteReadiness {
      warmupCoordinator?.prepare(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalIDs: [step.id]
      )
    }

    let activeGeneration = generation
    playTask = Task { [weak self] in
      guard let self, activeGeneration == generation else {
        return .cancelled
      }

      // A server-generated step has no truthful bundled equivalent. Wait for
      // its bounded remote preparation window before the player reads the
      // cache, instead of racing a fire-and-forget warm-up into a silent cue.
      if requiresRemoteReadiness, let routineGroupLocalID {
        await warmupCoordinator?.prepareAndWait(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: [step.id]
        )
        guard !Task.isCancelled, activeGeneration == generation else {
          return .cancelled
        }
      }

      return await player.play(RoutineGuidanceCueRequest(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: step.id,
        routineTitle: step.title,
        routineType: step.type,
        fallbackItemID: step.presetItemID,
        voiceCode: voiceCode,
        kind: .intro
      ))
    }

    guard step.type == .timer,
          let estimatedSeconds = step.estimatedSeconds,
          estimatedSeconds > 0 else {
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

      guard let itemID = step.presetItemID else {
        return
      }

      _ = await player.play(
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
        return .cancelled
      }

      return await player.play(RoutineGuidanceCueRequest(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: step.id,
        routineTitle: step.title,
        routineType: step.type,
        fallbackItemID: itemID,
        voiceCode: voiceCode,
        kind: .done
      ))
    }
  }

  func waitUntilCurrentCueFinishes() async -> GuidancePlaybackResult {
    guard let playTask else {
      return .completed
    }

    let activeGeneration = generation
    let result = await playTask.value
    guard !Task.isCancelled, activeGeneration == generation else {
      return .cancelled
    }

    return result
  }

  func playReminder(for step: RoutineStep) async -> GuidancePlaybackResult {
    stopCurrentCue()
    let activeGeneration = generation

    guard step.presetItemID != nil || routineGroupLocalID != nil else {
      systemSpeechAnnouncer.announceNoSpeechReminder()
      defer {
        if activeGeneration == generation {
          systemSpeechAnnouncer.stop()
        }
      }

      do {
        try await delay.wait(for: .seconds(3))
      } catch {
        return .cancelled
      }

      guard !Task.isCancelled, activeGeneration == generation else {
        return .cancelled
      }

      return .completed
    }

    let task = Task { [weak self] in
      guard let self, activeGeneration == generation else {
        return GuidancePlaybackResult.cancelled
      }

      return await player.play(RoutineGuidanceCueRequest(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: step.id,
        routineTitle: step.title,
        routineType: step.type,
        fallbackItemID: step.presetItemID,
        voiceCode: voiceCode,
        kind: .remind
      ))
    }
    playTask = task

    let result = await task.value
    guard !Task.isCancelled, activeGeneration == generation else {
      return .cancelled
    }

    return result
  }

  func timerCountdownDidReach(_ seconds: Int) {
    guard (1...5).contains(seconds) else {
      return
    }

    generation += 1
    playTask?.cancel()
    playTask = nil
    reminderTask?.cancel()
    reminderTask = nil
    player.stop()
    systemSpeechAnnouncer.announceCountdown(seconds)
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
    systemSpeechAnnouncer.stop()
  }
}
