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
    selectedTTSID: Int64,
    selectionVersion: Int64?
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
  private let prefetchJobStore: (any RoutineTTSPrefetchJobStoring)?
  private weak var backgroundTransferManager:
    (any RoutineTTSBackgroundTransferManaging)?
  private let voiceSelectionVersionStore:
    (any RoutineTTSVoiceSelectionVersionStoring)?
  private let preparationStatusCenter: RoutineTTSPreparationStatusCenter?
  private let pollingPolicy: RoutineTTSPrefetchPollingPolicy
  private let onSelectedVoiceResolved:
    @MainActor (Int64, Int64?, Int64?) -> Void
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?

  private var isSceneActive = false
  private var operationTask: Task<Void, Never>?
  private var generation: UInt = 0
  private var preparedPlan: PreparedPlan?
  private var preferredSelectedTTSID: Int64?

  init(
    remoteService: any AccountServerRemoteServing,
    audioCache: RoutineTTSAudioCache?,
    downloader: any RoutineTTSAudioDownloading,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    prefetchJobStore: (any RoutineTTSPrefetchJobStoring)? = nil,
    backgroundTransferManager:
      (any RoutineTTSBackgroundTransferManaging)? = nil,
    voiceSelectionVersionStore:
      (any RoutineTTSVoiceSelectionVersionStoring)? = nil,
    preparationStatusCenter: RoutineTTSPreparationStatusCenter? = nil,
    pollingPolicy: RoutineTTSPrefetchPollingPolicy =
      RoutineTTSPrefetchPollingPolicy(),
    onSelectedVoiceResolved:
      @escaping @MainActor (Int64, Int64?, Int64?) -> Void = { _, _, _ in }
  ) {
    self.remoteService = remoteService
    self.audioCache = audioCache
    self.downloader = downloader
    self.sessionIdentityProvider = sessionIdentityProvider
    self.prefetchJobStore = prefetchJobStore
    self.backgroundTransferManager = backgroundTransferManager
    self.voiceSelectionVersionStore = voiceSelectionVersionStore
    self.preparationStatusCenter = preparationStatusCenter
    self.pollingPolicy = pollingPolicy
    self.onSelectedVoiceResolved = onSelectedVoiceResolved
  }

  func setSceneActive(_ isActive: Bool) {
    self.isSceneActive = isActive
    guard isActive else {
      operationTask?.cancel()
      operationTask = nil
      RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
      return
    }
    prepareSelectedVoice()
  }

  func accountSessionDidChange() {
    generation &+= 1
    operationTask?.cancel()
    operationTask = nil
    preparedPlan = nil
    preferredSelectedTTSID = nil
    guard isSceneActive else { return }
    prepareSelectedVoice()
  }

  func serverVoiceSelectionDidChange(
    memberID: Int64,
    selectedTTSID: Int64,
    selectionVersion: Int64? = nil
  ) {
    guard sessionIdentityProvider?.currentAccountSessionIdentity?.memberID == memberID,
          selectedTTSID > 0 else {
      return
    }
    generation &+= 1
    operationTask?.cancel()
    operationTask = nil
    preparedPlan = nil
    preferredSelectedTTSID = selectedTTSID
    preparationStatusCenter?.report(
      .preparing,
      component: .commonCues,
      memberID: memberID,
      selectionVersion: selectionVersion,
      selectedTTSID: selectedTTSID
    )
    prepareSelectedVoice()
  }

  func resumeBackgroundPrefetchOpportunity() async {
    prepareSelectedVoice(allowsInactive: true)
    _ = await operationTask?.value
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
    if preparedPlan == nil {
      await restorePreparedPlan(identity: identity)
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

  private func prepareSelectedVoice(allowsInactive: Bool = false) {
    guard (isSceneActive || allowsInactive),
          let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          let audioCache else {
      return
    }

    guard operationTask == nil else { return }
    generation &+= 1
    let requestedGeneration = generation
    let remoteService = remoteService
    let downloader = downloader
    operationTask = Task { [weak self, audioCache, remoteService, downloader] in
      guard let self else { return }
      defer {
        if requestedGeneration == generation {
          operationTask = nil
        }
      }
      do {
        let resolvedProfile = try await remoteService.fetchProfile(
          memberID: identity.memberID
        )
        guard resolvedProfile.memberID == identity.memberID else { return }
        let selectionVersion = voiceSelectionVersionStore?.selectionVersion(
          forMemberID: identity.memberID
        )
        let targetTTSID = preferredSelectedTTSID
          ?? resolvedProfile.selectedTTSID
        let persistedTTSID = voiceSelectionVersionStore?.selectedTTSID(
          forMemberID: identity.memberID
        )
        voiceSelectionVersionStore?.setSelectedTTSID(
          targetTTSID,
          forMemberID: identity.memberID
        )
        if persistedTTSID != targetTTSID {
          onSelectedVoiceResolved(
            identity.memberID,
            targetTTSID,
            selectionVersion
          )
        }
        preparationStatusCenter?.beginIfNeeded(
          memberID: identity.memberID,
          selectionVersion: selectionVersion,
          selectedTTSID: targetTTSID
        )
        await backgroundTransferManager?.resumePendingTransfers(
          memberID: identity.memberID,
          selectionVersion: selectionVersion,
          selectedTTSID: targetTTSID
        )

        let persistedJobs = (try? await prefetchJobStore?.allJobs()) ?? []
        let pendingJobs = persistedJobs.filter {
          $0.memberID == identity.memberID
            && $0.selectionVersion == selectionVersion
            && $0.selectedTTSID == targetTTSID
            && ($0.assetKind == .commonDone || $0.assetKind == .commonRemind)
            && ($0.state == .pendingRemote || $0.state == .retryScheduled)
        }
        if !pendingJobs.isEmpty,
           pendingJobs.allSatisfy({
             guard let next = $0.nextRemoteAttemptAt else { return false }
             return next > pollingPolicy.now()
           }) {
          preparationStatusCenter?.report(
            .retryScheduled,
            component: .commonCues,
            memberID: identity.memberID,
            selectionVersion: selectionVersion,
            selectedTTSID: targetTTSID
          )
          RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
          return
        }
        let persistedAttempt = pendingJobs.map(\.remoteAttemptCount).max() ?? 0
        let firstAttempt = persistedAttempt >= pollingPolicy.maximumAttempts
          ? 0
          : persistedAttempt

        for attempt in firstAttempt..<pollingPolicy.maximumAttempts {
          let resolvedVoices = try await remoteService.fetchVoices(
            memberID: identity.memberID
          )
          guard !Task.isCancelled,
                requestedGeneration == generation,
                sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
            return
          }
          guard let voice = resolvedVoices.first(where: {
            $0.ttsID == targetTTSID
          }) else {
            throw RoutineTTSAudioDownloadError.invalidResponse
          }

          if prefetchJobStore != nil, backgroundTransferManager != nil {
            let hasPending = await persistCommonJobs(
              identity: identity,
              voice: voice,
              selectionVersion: selectionVersion,
              attempt: attempt
            )
            await restorePreparedPlan(identity: identity)
            guard hasPending,
                  attempt + 1 < pollingPolicy.maximumAttempts else {
              return
            }
            try await pollingPolicy.sleep(pollingPolicy.retryDelays[attempt])
            continue
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
          return
        }
      } catch is CancellationError {
        return
      } catch {
        // Keep any old plan only while it belongs to the exact current
        // session. A changed account or voice selection clears the plan before
        // this task begins, so this cannot cross voices.
        let selectionVersion = voiceSelectionVersionStore?.selectionVersion(
          forMemberID: identity.memberID
        )
        let selectedTTSID = preferredSelectedTTSID
          ?? voiceSelectionVersionStore?.selectedTTSID(
            forMemberID: identity.memberID
          )
        preparationStatusCenter?.report(
          .retryScheduled,
          component: .commonCues,
          memberID: identity.memberID,
          selectionVersion: selectionVersion,
          selectedTTSID: selectedTTSID
        )
        RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
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

  private func persistCommonJobs(
    identity: AccountSessionIdentity,
    voice: ServerTTSVoice,
    selectionVersion: Int64?,
    attempt: Int
  ) async -> Bool {
    guard let prefetchJobStore,
          let backgroundTransferManager else {
      return false
    }
    let cues: [(RoutineAudioCueKind, ServerTTSCommonAudio)] = [
      (.done, voice.doneAudio),
      (.remind, voice.remindAudio),
    ]
    var hasPending = false
    for (kind, cue) in cues {
      let assetKind = cacheKind(for: kind)
      let existing = try? await prefetchJobStore.allJobs().first(where: {
        $0.memberID == identity.memberID
          && $0.selectionVersion == selectionVersion
          && $0.selectedTTSID == voice.ttsID
          && $0.assetKind == assetKind
      })
      guard cue.isPlayable, let remoteURL = cue.audioURL else {
        hasPending = true
        let exhausted = attempt + 1 >= pollingPolicy.maximumAttempts
        let delay: TimeInterval
        if attempt < pollingPolicy.retryDelays.count {
          delay = Self.timeInterval(for: pollingPolicy.retryDelays[attempt])
        } else {
          delay = 15 * 60
        }
        let job = RoutineTTSPrefetchJob(
          id: existing?.id ?? UUID(),
          memberID: identity.memberID,
          selectionVersion: selectionVersion,
          selectedTTSID: voice.ttsID,
          assetKind: assetKind,
          state: exhausted ? .retryScheduled : .pendingRemote,
          assets: existing?.assets ?? [],
          remoteAttemptCount: attempt + 1,
          nextRemoteAttemptAt: pollingPolicy.now().addingTimeInterval(delay)
        )
        _ = try? await prefetchJobStore.upsert(job)
        continue
      }

      let key = RoutineTTSAudioCacheKey(
        accountID: String(identity.memberID),
        namespace: Self.cacheNamespace,
        ttsID: voice.ttsID,
        voiceCode: voice.voiceCode,
        commonAudioVersion: voice.commonAudioVersion,
        kind: assetKind,
        remoteURL: remoteURL
      )
      let existingAsset = existing?.assets.first(where: { $0.cacheKey == key })
      let job = RoutineTTSPrefetchJob(
        id: existing?.id ?? UUID(),
        memberID: identity.memberID,
        selectionVersion: selectionVersion,
        selectedTTSID: voice.ttsID,
        assetKind: assetKind,
        state: .downloading,
        assets: [
          RoutineTTSPrefetchAsset(
            id: existingAsset?.id ?? UUID(),
            cacheKey: key,
            state: existingAsset?.state ?? .queued
          ),
        ]
      )
      if let stored = try? await prefetchJobStore.upsert(job) {
        await backgroundTransferManager.enqueue(jobID: stored.id)
      }
    }

    preparationStatusCenter?.report(
      .preparing,
      component: .commonCues,
      memberID: identity.memberID,
      selectionVersion: selectionVersion,
      selectedTTSID: voice.ttsID
    )
    if hasPending && attempt + 1 >= pollingPolicy.maximumAttempts {
      preparationStatusCenter?.report(
        .retryScheduled,
        component: .commonCues,
        memberID: identity.memberID,
        selectionVersion: selectionVersion,
        selectedTTSID: voice.ttsID
      )
      RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
    }
    return hasPending
  }

  private func restorePreparedPlan(identity: AccountSessionIdentity) async {
    guard let prefetchJobStore,
          let audioCache,
          let selectedTTSID = voiceSelectionVersionStore?.selectedTTSID(
            forMemberID: identity.memberID
          ) else {
      return
    }
    let selectionVersion = voiceSelectionVersionStore?.selectionVersion(
      forMemberID: identity.memberID
    )
    guard let jobs = try? await prefetchJobStore.allJobs() else { return }
    let commonJobs = jobs.filter {
      $0.memberID == identity.memberID
        && $0.selectionVersion == selectionVersion
        && $0.selectedTTSID == selectedTTSID
        && ($0.assetKind == .commonDone || $0.assetKind == .commonRemind)
        && $0.state == .completed
    }
    var urls: [RoutineAudioCueKind: URL] = [:]
    var voiceCode: String?
    var commonVersion: Int64?
    for job in commonJobs {
      guard let key = job.assets.first?.cacheKey,
            let url = await audioCache.cachedFileURL(for: key, allowStale: true) else {
        continue
      }
      voiceCode = key.voiceCode
      commonVersion = key.commonAudioVersion
      switch job.assetKind {
      case .commonDone:
        urls[.done] = url
      case .commonRemind:
        urls[.remind] = url
      case .routineIntro:
        break
      }
    }
    guard !urls.isEmpty, let voiceCode else { return }
    preparedPlan = PreparedPlan(
      identity: identity,
      ttsID: selectedTTSID,
      voiceCode: voiceCode,
      commonAudioVersion: commonVersion,
      urls: urls
    )
  }

  private static func timeInterval(for duration: Duration) -> TimeInterval {
    let components = duration.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
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
