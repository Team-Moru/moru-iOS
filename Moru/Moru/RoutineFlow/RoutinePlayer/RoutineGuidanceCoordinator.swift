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

    // A current-account binding (or staged creation) marks this as a
    // server-only intro. Missing cache data then becomes silence rather than
    // either a bundled-voice substitution or a blocked routine step.
    return warmupCoordinator?.expectsServerGeneratedIntro(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalID: step.id
    ) ?? false
  }

  func stepDidStart(_ step: RoutineStep) {
    stopCurrentCue()

    guard step.presetItemID != nil || routineGroupLocalID != nil else {
      return
    }

    let requiresRemoteReadiness = requiresServerVoiceReadiness(for: step)
    if let routineGroupLocalID, !requiresRemoteReadiness {
      // Local-only steps keep background warming opportunistic. A server-only
      // intro instead joins the bounded foreground preparation below.
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

      if requiresRemoteReadiness, let routineGroupLocalID {
        guard let warmupCoordinator else {
          return .unavailable
        }
        let preparation = await warmupCoordinator.prepareAndWait(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: [step.id]
        )
        guard !Task.isCancelled, activeGeneration == generation else {
          return .cancelled
        }
        guard preparation == .prepared else {
          return preparation == .cancelled ? .cancelled : .unavailable
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

  }

  func stepDidComplete(_ step: RoutineStep) {
    stopCurrentCue()

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
        fallbackItemID: step.presetItemID,
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
