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

  func requiresServerVoiceReadiness(for step: RoutineStep) -> Bool {
    guard let routineGroupLocalID else {
      return false
    }

    // Both custom and preset steps wait only when their current-account
    // binding (or staged creation) proves that a server intro is expected.
    // A local custom step has no bundled audio, but must still start normally
    // rather than being mistaken for a broken server cue.
    return warmupCoordinator?.expectsServerGeneratedIntro(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalID: step.id
    ) ?? false
  }

  /// Prepares a server-generated intro before the player presents a step.
  /// A custom step has no bundled equivalent, so callers must surface a
  /// non-ready result instead of silently proceeding.
  func prepareServerVoiceIntro(
    for step: RoutineStep,
    serverVoiceRequired: Bool? = nil
  ) async -> RoutineTTSForegroundPreparationStatus {
    let requiresRemoteReadiness = serverVoiceRequired
      ?? requiresServerVoiceReadiness(for: step)
    guard requiresRemoteReadiness,
          let routineGroupLocalID else {
      return .prepared
    }

    guard let warmupCoordinator else {
      return .unavailable
    }

    return await warmupCoordinator.prepareAndWait(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalIDs: [step.id]
    )
  }

  func stepDidStart(
    _ step: RoutineStep,
    serverVoiceIsPrepared: Bool = false
  ) {
    stopCurrentCue()

    guard step.presetItemID != nil || routineGroupLocalID != nil else {
      return
    }

    // A successful foreground preparation already proved the server intent.
    // Do not repeat that storage lookup here: a transient read failure between
    // preparation and playback must become a visible retry, never a bundled
    // voice fallback.
    let requiresRemoteReadiness = serverVoiceIsPrepared
      || requiresServerVoiceReadiness(for: step)
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
      if requiresRemoteReadiness, !serverVoiceIsPrepared {
        let preparation = await self.prepareServerVoiceIntro(
          for: step,
          serverVoiceRequired: true
        )
        guard preparation == .prepared else {
          return .unavailable
        }
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
        kind: .intro,
        requiresServerGeneratedIntro: requiresRemoteReadiness
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
      let result = await systemSpeechAnnouncer.announceNoSpeechReminder()

      guard !Task.isCancelled, activeGeneration == generation else {
        return .cancelled
      }

      return result
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
