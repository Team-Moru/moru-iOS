//
//  ServerVoiceCommonAudioProvider.swift
//  Moru
//

import Foundation

/// The player must distinguish a local-only user from a signed-in user whose
/// selected server cue is not ready yet. Only the latter fails open silently;
/// replaying a bundled cue would otherwise switch the user's voice mid-routine.
@MainActor
enum RoutineTTSCommonAudioAvailability: Equatable {
  case localFile(URL)
  case unavailableForServerVoice
  case useBundledFallback
}

@MainActor
protocol RoutineTTSCommonAudioProviding: AnyObject {
  func localCommonAudio(
    for kind: RoutineAudioCueKind
  ) async -> RoutineTTSCommonAudioAvailability
}

@MainActor
protocol RoutineTTSCommonAudioWarming: AnyObject {
  func setSceneActive(_ isActive: Bool)
  func accountSessionDidChange()
  func serverVoiceSelectionDidChange(
    memberID: Int64,
    selectedTTSID: Int64
  )
}

/// Downloads and owns the selected voice's fixed DONE/REMIND assets. The
/// result is always a local file; routine playback never streams an S3 URL or
/// waits for a network request at cue time.
@MainActor
final class ServerVoiceCommonAudioProvider:
  RoutineTTSCommonAudioProviding,
  RoutineTTSCommonAudioWarming {
  private struct PreparedPlan {
    let identity: AccountSessionIdentity
    let ttsID: Int64
    let voiceCode: String
    let commonAudioVersion: Int64?
    let urls: [RoutineAudioCueKind: URL]
  }

  private static let cacheNamespace = "server-voice-common-cues"

  private let remoteService: any AccountServerRemoteServing
  private let audioCache: RoutineTTSAudioCache?
  private let downloader: any RoutineTTSAudioDownloading
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?

  private var isSceneActive = false
  private var operationTask: Task<Void, Never>?
  private var generation: UInt = 0
  private var preparedPlan: PreparedPlan?

  init(
    remoteService: any AccountServerRemoteServing,
    audioCache: RoutineTTSAudioCache?,
    downloader: any RoutineTTSAudioDownloading,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding
  ) {
    self.remoteService = remoteService
    self.audioCache = audioCache
    self.downloader = downloader
    self.sessionIdentityProvider = sessionIdentityProvider
  }

  func setSceneActive(_ isActive: Bool) {
    self.isSceneActive = isActive
    guard isActive else {
      operationTask?.cancel()
      operationTask = nil
      return
    }
    prepareSelectedVoice()
  }

  func accountSessionDidChange() {
    generation &+= 1
    operationTask?.cancel()
    operationTask = nil
    preparedPlan = nil
    guard isSceneActive else { return }
    prepareSelectedVoice()
  }

  func serverVoiceSelectionDidChange(
    memberID: Int64,
    selectedTTSID: Int64
  ) {
    guard sessionIdentityProvider?.currentAccountSessionIdentity?.memberID == memberID,
          selectedTTSID > 0 else {
      return
    }
    generation &+= 1
    operationTask?.cancel()
    operationTask = nil
    preparedPlan = nil
    guard isSceneActive else { return }
    prepareSelectedVoice()
  }

  func localCommonAudio(
    for kind: RoutineAudioCueKind
  ) async -> RoutineTTSCommonAudioAvailability {
    guard kind == .done || kind == .remind else {
      return .useBundledFallback
    }
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity else {
      return .useBundledFallback
    }
    guard let preparedPlan,
          preparedPlan.identity == identity,
          let url = preparedPlan.urls[kind] else {
      // Signed-in playback must never fall through to a bundled voice.
      prepareSelectedVoice()
      return .unavailableForServerVoice
    }
    return .localFile(url)
  }

  private func prepareSelectedVoice() {
    guard isSceneActive,
          let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          let audioCache else {
      return
    }

    generation &+= 1
    let requestedGeneration = generation
    operationTask?.cancel()
    let remoteService = remoteService
    let downloader = downloader
    operationTask = Task { [weak self, audioCache, remoteService, downloader] in
      do {
        async let profile = remoteService.fetchProfile(memberID: identity.memberID)
        async let voices = remoteService.fetchVoices(memberID: identity.memberID)
        let (resolvedProfile, resolvedVoices) = try await (profile, voices)
        guard !Task.isCancelled,
              let self,
              requestedGeneration == generation,
              sessionIdentityProvider?.currentAccountSessionIdentity == identity,
              resolvedProfile.memberID == identity.memberID,
              let voice = resolvedVoices.first(where: {
                $0.ttsID == resolvedProfile.selectedTTSID
              }) else {
          return
        }

        let assets = commonAssets(for: voice)
        var urls: [RoutineAudioCueKind: URL] = [:]
        for (kind, asset) in assets {
          guard !Task.isCancelled,
                requestedGeneration == generation,
                sessionIdentityProvider?.currentAccountSessionIdentity == identity,
                let remoteURL = asset.audioURL else {
            return
          }
          let key = RoutineTTSAudioCacheKey(
            accountID: String(identity.memberID),
            namespace: Self.cacheNamespace,
            ttsID: voice.ttsID,
            voiceCode: voice.voiceCode,
            commonAudioVersion: voice.commonAudioVersion,
            kind: cacheKind(for: kind),
            remoteURL: remoteURL
          )
          do {
            let localURL = try await audioCache.fileURL(for: key) { stagingDirectory in
              try await downloader.download(
                RoutineTTSAudioDownloadRequest(remoteURL: remoteURL),
                stagingDirectory: stagingDirectory
              )
            }
            urls[kind] = localURL
          } catch is CancellationError {
            return
          } catch {
            // A failure in one fixed cue must not discard another cue that
            // downloaded successfully for the same selected voice.
            continue
          }
        }

        guard !Task.isCancelled,
              requestedGeneration == generation,
              sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
          return
        }
        preparedPlan = PreparedPlan(
          identity: identity,
          ttsID: voice.ttsID,
          voiceCode: voice.voiceCode,
          commonAudioVersion: voice.commonAudioVersion,
          urls: urls
        )
      } catch is CancellationError {
        return
      } catch {
        // Keep any old plan only while it belongs to the exact current
        // session. A changed account or voice selection clears the plan before
        // this task begins, so this cannot cross voices.
        return
      }
    }
  }

  private func commonAssets(
    for voice: ServerTTSVoice
  ) -> [(RoutineAudioCueKind, ServerTTSCommonAudio)] {
    [
      (.done, voice.doneAudio),
      (.remind, voice.remindAudio),
    ].filter { $0.1.isPlayable }
  }

  private func cacheKind(
    for kind: RoutineAudioCueKind
  ) -> RoutineTTSAudioCacheKey.AssetKind {
    switch kind {
    case .done:
      .commonDone
    case .remind:
      .commonRemind
    case .intro:
      preconditionFailure("INTRO is not a common voice cue")
    }
  }
}
