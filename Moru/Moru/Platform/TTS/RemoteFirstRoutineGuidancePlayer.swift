//
//  RemoteFirstRoutineGuidancePlayer.swift
//  Moru
//

import AVFAudio
import Foundation

nonisolated private final class LocalAudioNotificationObservation: @unchecked Sendable {
  private let notificationCenter: NotificationCenter
  private let observer: NSObjectProtocol

  init(
    notificationCenter: NotificationCenter,
    name: Notification.Name,
    handler: @escaping @Sendable (Notification) -> Void
  ) {
    self.notificationCenter = notificationCenter
    observer = notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: .main,
      using: handler
    )
  }

  deinit { notificationCenter.removeObserver(observer) }
}

nonisolated struct RoutineTTSLocalAudioRequest: Equatable, Sendable {
  let routineGroupLocalID: UUID
  let routineLocalID: UUID
  let routineTitle: String
  let routineType: RoutineStepType
}

protocol RoutineTTSLocalAudioProviding: AnyObject {
  @MainActor
  func localAudioURLs(for request: RoutineTTSLocalAudioRequest) async -> [URL]?
}

@MainActor
protocol RoutineTTSPlaybackSessionInvalidating: AnyObject {
  func invalidatePlaybackForAccountSessionChange()
}

enum RoutineLocalAudioPlaybackResult: Equatable {
  case completed
  case cancelled
  case failedToStart
}

@MainActor
protocol RoutineLocalAudioSequencePlaying: GuidancePlaybackControlling {
  func playLocalAudioSequence(_ urls: [URL]) async -> RoutineLocalAudioPlaybackResult
  func stop()
  func stopLocalAudioSequenceAndWaitUntilIdle() async
}

extension RoutineLocalAudioSequencePlaying {
  /// Stops only routine-file playback. Unlike the speech-input barrier this
  /// must not leave future remote playback suspended.
  func stopLocalAudioSequenceAndWaitUntilIdle() async {
    stop()
    await Task.yield()
  }
}

@MainActor
final class RemoteFirstRoutineGuidancePlayer:
  RoutineGuidancePlaying,
  RoutineTTSPlaybackSessionInvalidating {
  private let bundledPlayer: any RoutineGuidancePlaying
  private let remotePlayer: any RoutineLocalAudioSequencePlaying
  private let localAudioProvider: any RoutineTTSLocalAudioProviding
  private let diagnostics = RoutineTTSDiagnostics()
  private var accountSessionGeneration: UInt = 0
  private var playbackGeneration: UInt = 0

  init(
    bundledPlayer: any RoutineGuidancePlaying,
    remotePlayer: any RoutineLocalAudioSequencePlaying,
    localAudioProvider: any RoutineTTSLocalAudioProviding
  ) {
    self.bundledPlayer = bundledPlayer
    self.remotePlayer = remotePlayer
    self.localAudioProvider = localAudioProvider
  }

  /// The legacy seam is intentionally bundle-only. Voice preview uses it and
  /// must never resolve account-scoped routine audio.
  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async -> GuidancePlaybackResult {
    playbackGeneration &+= 1
    let requestedPlaybackGeneration = playbackGeneration
    guard !Task.isCancelled else { return .cancelled }
    await stopRemoteBeforeBundledPlayback()
    guard !Task.isCancelled,
          requestedPlaybackGeneration == playbackGeneration else { return .cancelled }
    return await bundledPlayer.play(itemID: itemID, voiceCode: voiceCode, kind: kind)
  }

  func play(_ request: RoutineGuidanceCueRequest) async -> GuidancePlaybackResult {
    playbackGeneration &+= 1
    let requestedPlaybackGeneration = playbackGeneration
    let requestedSessionGeneration = accountSessionGeneration
    guard request.kind == .intro,
          let groupID = request.routineGroupLocalID,
          let routineID = request.routineLocalID,
          let routineTitle = request.routineTitle,
          let routineType = request.routineType else {
      return await playBundledFallback(
        request,
        expectedPlaybackGeneration: requestedPlaybackGeneration
      )
    }
    let urls = await localAudioProvider.localAudioURLs(
      for: RoutineTTSLocalAudioRequest(
        routineGroupLocalID: groupID,
        routineLocalID: routineID,
        routineTitle: routineTitle,
        routineType: routineType
      )
    )
    guard !Task.isCancelled,
          requestedSessionGeneration == accountSessionGeneration,
          requestedPlaybackGeneration == playbackGeneration else {
      return .cancelled
    }
    guard let urls, !urls.isEmpty else {
      return await playBundledFallback(
        request,
        expectedPlaybackGeneration: requestedPlaybackGeneration
      )
    }

    bundledPlayer.stop()
    let remoteResult = await remotePlayer.playLocalAudioSequence(urls)
    guard requestedSessionGeneration == accountSessionGeneration,
          requestedPlaybackGeneration == playbackGeneration else {
      return .cancelled
    }
    switch remoteResult {
    case .completed:
      return .completed
    case .cancelled:
      // Once remote playback starts, cancellation/interruption must end the
      // cue. Mixing in a bundle fallback would repeat or cross voices.
      return .cancelled
    case .failedToStart:
      guard !Task.isCancelled,
            requestedSessionGeneration == accountSessionGeneration,
            requestedPlaybackGeneration == playbackGeneration else {
        return .cancelled
      }
      return await playBundledFallback(
        request,
        expectedPlaybackGeneration: requestedPlaybackGeneration
      )
    }
  }

  func stop() {
    playbackGeneration &+= 1
    bundledPlayer.stop()
    remotePlayer.stop()
  }

  func invalidatePlaybackForAccountSessionChange() {
    accountSessionGeneration &+= 1
    playbackGeneration &+= 1
    remotePlayer.stop()
  }

  func stopAndWaitUntilIdle() async {
    playbackGeneration &+= 1
    await bundledPlayer.stopAndWaitUntilIdle()
    await remotePlayer.stopAndWaitUntilIdle()
  }

  func resumeAfterSpeechInput() {
    bundledPlayer.resumeAfterSpeechInput()
    remotePlayer.resumeAfterSpeechInput()
  }

  private func playBundledFallback(
    _ request: RoutineGuidanceCueRequest,
    expectedPlaybackGeneration: UInt
  ) async -> GuidancePlaybackResult {
    guard !Task.isCancelled,
          expectedPlaybackGeneration == playbackGeneration else { return .cancelled }
    guard !request.requiresServerGeneratedIntro else {
      diagnostics.record(.serverCueUnavailable)
      return .unavailable
    }
    guard let itemID = request.fallbackItemID else {
      diagnostics.record(.customCueUnavailable)
      // A local-only custom cue has no bundled asset by design. It must still
      // complete so the normal voice-input flow can begin; only a
      // server-required cue is surfaced as unavailable above.
      return .completed
    }

    await stopRemoteBeforeBundledPlayback()
    guard !Task.isCancelled,
          expectedPlaybackGeneration == playbackGeneration else { return .cancelled }
    return await bundledPlayer.play(
      itemID: itemID,
      voiceCode: request.voiceCode,
      kind: request.kind
    )
  }


  private func stopRemoteBeforeBundledPlayback() async {
    await remotePlayer.stopLocalAudioSequenceAndWaitUntilIdle()
  }
}

@MainActor
final class LocalFileRoutineAudioPlayer: NSObject, RoutineLocalAudioSequencePlaying {
  private let playbackState: RoutineGuidancePlaybackState
  private let audioSession: AVAudioSession
  private var audioPlayer: AVAudioPlayer?
  private var continuation: CheckedContinuation<Bool, Never>?
  private var isSuspendedForSpeechInput = false
  private var sequenceHasStarted = false
  private var interruptionObservation: LocalAudioNotificationObservation?
  private var routeChangeObservation: LocalAudioNotificationObservation?
  private var mediaResetObservation: LocalAudioNotificationObservation?

  init(
    playbackState: RoutineGuidancePlaybackState,
    audioSession: AVAudioSession = .sharedInstance(),
    notificationCenter: NotificationCenter = .default
  ) {
    self.playbackState = playbackState
    self.audioSession = audioSession
    super.init()
    observeAudioSessionChanges(notificationCenter: notificationCenter)
  }

  func playLocalAudioSequence(_ urls: [URL]) async -> RoutineLocalAudioPlaybackResult {
    guard !isSuspendedForSpeechInput, !urls.isEmpty,
          urls.allSatisfy({ $0.isFileURL }) else {
      return .failedToStart
    }

    stop()
    sequenceHasStarted = false
    for url in urls {
      guard !Task.isCancelled else {
        stop()
        return sequenceHasStarted ? .cancelled : .failedToStart
      }

      let result = await playOne(url)
      guard result else {
        deactivateAudioSession()
        return sequenceHasStarted ? .cancelled : .failedToStart
      }
    }

    deactivateAudioSession()
    return .completed
  }

  func stop() {
    audioPlayer?.stop()
    finishCurrent(successfully: false)
    deactivateAudioSession()
  }

  func stopAndWaitUntilIdle() async {
    isSuspendedForSpeechInput = true
    stop()
    await Task.yield()
  }

  func resumeAfterSpeechInput() {
    isSuspendedForSpeechInput = false
  }

  private func playOne(_ url: URL) async -> Bool {
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try audioSession.setActive(true)
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      player.prepareToPlay()
      audioPlayer = player

      return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          self.continuation = continuation
          guard player.play() else {
            finishCurrent(successfully: false)
            return
          }
          sequenceHasStarted = true
          playbackState.update(isPlaying: true)
        }
      } onCancel: {
        Task { @MainActor [weak self] in self?.stop() }
      }
    } catch {
      finishCurrent(successfully: false)
      deactivateAudioSession()
      return false
    }
  }

  private func finishCurrent(successfully: Bool) {
    let continuation = continuation
    self.continuation = nil
    audioPlayer?.delegate = nil
    audioPlayer = nil
    playbackState.update(isPlaying: false)
    continuation?.resume(returning: successfully)
  }

  private func deactivateAudioSession() {
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func observeAudioSessionChanges(notificationCenter: NotificationCenter) {
    interruptionObservation = LocalAudioNotificationObservation(
      notificationCenter: notificationCenter,
      name: AVAudioSession.interruptionNotification
    ) { [weak self] notification in
      let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      guard value == AVAudioSession.InterruptionType.began.rawValue else { return }
      Task { @MainActor [weak self] in self?.stop() }
    }

    routeChangeObservation = LocalAudioNotificationObservation(
      notificationCenter: notificationCenter,
      name: AVAudioSession.routeChangeNotification
    ) { [weak self] notification in
      let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      guard let value,
            let reason = AVAudioSession.RouteChangeReason(rawValue: value),
            Self.shouldCancelPlayback(for: reason) else { return }
      Task { @MainActor [weak self] in self?.stop() }
    }

    mediaResetObservation = LocalAudioNotificationObservation(
      notificationCenter: notificationCenter,
      name: AVAudioSession.mediaServicesWereResetNotification
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.stop() }
    }
  }

  nonisolated private static func shouldCancelPlayback(
    for reason: AVAudioSession.RouteChangeReason
  ) -> Bool {
    switch reason {
    case .unknown, .categoryChange:
      false
    case .newDeviceAvailable, .oldDeviceUnavailable, .override,
         .wakeFromSleep, .noSuitableRouteForCategory, .routeConfigurationChange:
      true
    @unknown default:
      true
    }
  }
}

extension LocalFileRoutineAudioPlayer: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(
    _ player: AVAudioPlayer,
    successfully flag: Bool
  ) {
    let identifier = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let current = self?.audioPlayer,
            ObjectIdentifier(current) == identifier else { return }
      self?.finishCurrent(successfully: flag)
    }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(
    _ player: AVAudioPlayer,
    error: Error?
  ) {
    let identifier = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let current = self?.audioPlayer,
            ObjectIdentifier(current) == identifier else { return }
      self?.finishCurrent(successfully: false)
    }
  }
}
