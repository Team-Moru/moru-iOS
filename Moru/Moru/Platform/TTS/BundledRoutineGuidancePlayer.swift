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

nonisolated private final class RoutineAudioNotificationObservation:
  @unchecked Sendable {
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

  deinit {
    notificationCenter.removeObserver(observer)
  }
}

@MainActor
final class BundledRoutineGuidancePlayer: NSObject, RoutineGuidancePlaying {
  private let resourceLoader: RoutineAudioResourceLoader
  private let playbackState: RoutineGuidancePlaybackState
  private let audioSession: AVAudioSession

  private var audioPlayer: AVAudioPlayer?
  private var playbackContinuation: CheckedContinuation<GuidancePlaybackResult, Never>?
  private var ownsAudioSession = false
  private var isSuspendedForSpeechInput = false
  private var interruptionObservation: RoutineAudioNotificationObservation?
  private var routeChangeObservation: RoutineAudioNotificationObservation?

  init(
    resourceLoader: RoutineAudioResourceLoader,
    playbackState: RoutineGuidancePlaybackState,
    audioSession: AVAudioSession = .sharedInstance(),
    notificationCenter: NotificationCenter = .default
  ) {
    self.resourceLoader = resourceLoader
    self.playbackState = playbackState
    self.audioSession = audioSession
    super.init()
    observeAudioSessionChanges(notificationCenter: notificationCenter)
  }

  func play(
    itemID: String,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) async -> GuidancePlaybackResult {
    guard !isSuspendedForSpeechInput else {
      return .cancelled
    }

    stop()

    do {
      guard let cue = try resourceLoader.cue(
        itemID: itemID,
        voiceCode: voiceCode,
        kind: kind
      ),
      let resourceURL = resourceLoader.resourceURL(for: cue) else {
        return .completed
      }

      try configureAudioSession()
      ownsAudioSession = true
      let player = try AVAudioPlayer(contentsOf: resourceURL)
      player.delegate = self
      player.prepareToPlay()

      audioPlayer = player
      return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          playbackContinuation = continuation

          guard player.play() else {
            finishPlayback(with: .cancelled)
            return
          }

          playbackState.update(isPlaying: true)
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          self?.finishPlayback(with: .cancelled)
        }
      }
    } catch {
      finishPlayback(with: .cancelled)
      return .cancelled
    }
  }

  func stop() {
    audioPlayer?.stop()
    finishPlayback(with: .cancelled)
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

  private func finishPlayback(with result: GuidancePlaybackResult) {
    let continuation = playbackContinuation
    playbackContinuation = nil
    audioPlayer?.delegate = nil
    audioPlayer = nil
    playbackState.update(isPlaying: false)
    if ownsAudioSession {
      ownsAudioSession = false
      deactivateAudioSession()
    }
    continuation?.resume(returning: result)
  }

  private func deactivateAudioSession() {
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func observeAudioSessionChanges(notificationCenter: NotificationCenter) {
    interruptionObservation = RoutineAudioNotificationObservation(
      notificationCenter: notificationCenter,
      name: AVAudioSession.interruptionNotification
    ) { [weak self] notification in
      let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      guard typeValue == AVAudioSession.InterruptionType.began.rawValue else {
        return
      }

      Task { @MainActor [weak self] in
        self?.finishPlayback(with: .cancelled)
      }
    }

    routeChangeObservation = RoutineAudioNotificationObservation(
      notificationCenter: notificationCenter,
      name: AVAudioSession.routeChangeNotification
    ) { [weak self] notification in
      let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      guard let reasonValue,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            Self.shouldCancelPlayback(for: reason) else {
        return
      }

      Task { @MainActor [weak self] in
        self?.finishPlayback(with: .cancelled)
      }
    }
  }

  nonisolated private static func shouldCancelPlayback(
    for reason: AVAudioSession.RouteChangeReason
  ) -> Bool {
    switch reason {
    case .newDeviceAvailable,
         .oldDeviceUnavailable,
         .override,
         .wakeFromSleep,
         .noSuitableRouteForCategory,
         .routeConfigurationChange:
      return true
    case .unknown, .categoryChange:
      return false
    @unknown default:
      return true
    }
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

      self?.finishPlayback(with: flag ? .completed : .cancelled)
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

      self?.finishPlayback(with: .cancelled)
    }
  }
}
