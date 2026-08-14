//
//  ServerVoicePreviewPlayer.swift
//  Moru
//

import Foundation
import Observation

@MainActor
enum ServerVoicePreviewPlaybackState: Equatable {
  case idle
  case loading(ttsID: Int64)
  case playing(ttsID: Int64)
  case failed(ttsID: Int64)
}

/// Plays the backend-provided, common sample for a server voice. Preview
/// files are cached separately from routine cues and never change the
/// account's selected server voice.
@MainActor
@Observable
final class ServerVoicePreviewPlayer {
  private static let cacheNamespace = "server-voice-preview"
  private static let previewStepID: Int64 = 1

  private let audioCache: RoutineTTSAudioCache?
  private let downloader: any RoutineTTSAudioDownloading
  private let localPlayer: any RoutineLocalAudioSequencePlaying

  private var previewTask: Task<Void, Never>?
  private var previewGeneration = 0

  private(set) var state: ServerVoicePreviewPlaybackState = .idle
  private(set) var errorMessage: String?

  init(
    audioCache: RoutineTTSAudioCache? = nil,
    downloader: any RoutineTTSAudioDownloading = RoutineTTSAudioDownloader(
      policy: RoutineTTSAudioDownloadPolicy(
        // Preview URLs are supplied by the authenticated MORU catalogue. The
        // downloader still enforces HTTPS, no cross-host redirects, size,
        // MIME type, and audio decodability before caching a file.
        sourceValidator: { _ in true }
      )
    ),
    localPlayer: (any RoutineLocalAudioSequencePlaying)? = nil
  ) {
    self.audioCache = audioCache
    self.downloader = downloader
    self.localPlayer = localPlayer ?? LocalFileRoutineAudioPlayer(
      playbackState: RoutineGuidancePlaybackState()
    )
  }

  func isPreviewAvailable(for voice: ServerTTSVoice) -> Bool {
    audioCache != nil && voice.previewAudioURL != nil
  }

  func isLoading(_ voice: ServerTTSVoice) -> Bool {
    state == .loading(ttsID: voice.ttsID)
  }

  func isPlaying(_ voice: ServerTTSVoice) -> Bool {
    state == .playing(ttsID: voice.ttsID)
  }

  func togglePreview(
    _ voice: ServerTTSVoice,
    memberID: Int64
  ) {
    if isPlaying(voice) || isLoading(voice) {
      stopPreview()
      return
    }

    guard memberID > 0,
          let audioCache,
          let previewURL = voice.previewAudioURL else {
      errorMessage = "이 음성의 미리듣기를 아직 준비하지 못했어요."
      state = .failed(ttsID: voice.ttsID)
      return
    }

    stopPreview()
    previewGeneration &+= 1
    let generation = previewGeneration
    state = .loading(ttsID: voice.ttsID)
    errorMessage = nil

    let key = RoutineTTSAudioCacheKey(
      accountID: String(memberID),
      namespace: Self.cacheNamespace,
      routineGroupID: voice.ttsID,
      routineID: voice.ttsID,
      stepID: Self.previewStepID,
      remoteURL: previewURL
    )
    let downloader = downloader

    previewTask = Task { [weak self, audioCache, downloader] in
      do {
        let localURL = try await audioCache.fileURL(for: key) { stagingDirectory in
          try await downloader.download(
            RoutineTTSAudioDownloadRequest(remoteURL: previewURL),
            stagingDirectory: stagingDirectory
          )
        }
        guard !Task.isCancelled,
              let self,
              generation == previewGeneration else {
          return
        }

        state = .playing(ttsID: voice.ttsID)
        let result = await localPlayer.playLocalAudioSequence([localURL])
        guard !Task.isCancelled,
              generation == previewGeneration else {
          return
        }

        switch result {
        case .completed, .cancelled:
          state = .idle
        case .failedToStart:
          state = .failed(ttsID: voice.ttsID)
          errorMessage = "미리듣기 음성을 재생하지 못했어요."
        }
      } catch is CancellationError {
        return
      } catch {
        guard let self, generation == previewGeneration else {
          return
        }
        state = .failed(ttsID: voice.ttsID)
        errorMessage = "미리듣기 음성을 불러오지 못했어요."
      }
    }
  }

  func stopPreview() {
    previewGeneration &+= 1
    previewTask?.cancel()
    previewTask = nil
    localPlayer.stop()
    state = .idle
    errorMessage = nil
  }
}
