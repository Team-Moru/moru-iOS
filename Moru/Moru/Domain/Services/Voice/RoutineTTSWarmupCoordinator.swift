//
//  RoutineTTSWarmupCoordinator.swift
//  Moru
//

import Foundation
import OSLog

@MainActor
final class RoutineTTSWarmupCoordinator: RoutineTTSWarming, RoutineTTSLocalAudioProviding {
  private struct PreparedPlan {
    let identity: AccountSessionIdentity
    let fingerprint: RoutineTTSLocalFingerprint
    let routineGroupRemoteID: Int64
    let routineRemoteID: Int64
    let keys: [RoutineTTSAudioCacheKey]
  }

  private struct RoutineTTSLocalFingerprint: Equatable {
    let normalizedTitle: String
    let type: RoutineStepType

    init(title: String, type: RoutineStepType) {
      normalizedTitle = title
        .precomposedStringWithCanonicalMapping
        .trimmingCharacters(in: .whitespacesAndNewlines)
      self.type = type
    }
  }

  private struct LocalPlanKey: Hashable {
    let routineGroupLocalID: UUID
    let routineLocalID: UUID
  }

  /// 계획을 실제로 싣었는지, 못 실었다면 기존 계획을 버려야 하는지.
  ///
  /// 이 구분이 필요한 이유: 로컬 단계가 바뀌었거나 사라졌다면 들고 있던 계획은
  /// 틀린 것이므로 버려야 하고, 저장소 읽기가 잠깐 실패한 것뿐이라면 버리면
  /// 안 된다. 버리면 다음 재생 때 안내가 통째로 없어진다.
  private enum PlanPublication {
    case published
    /// 로컬이 달라졌다 — 들고 있던 계획은 더 이상 이 단계의 것이 아니다.
    case rejectedStalePlan
    /// 일시적 실패 — 판단할 수 없으므로 기존 계획을 그대로 둔다.
    case unavailable
  }

  private enum ForegroundPreparationResult {
    case prepared
    case pendingBinding
    case pendingGeneration
    case retryableDownload
    case retryableRemoteRequest
    case unavailable
  }

  private struct ForegroundCandidate {
    let localStep: RoutineStep
    let localKey: LocalPlanKey
    let routineGroupRemoteID: Int64
    let routineRemoteID: Int64
    let assets: [RoutineTTSResolvedAsset]
  }


  private let remoteService: any RoutineTTSRemoteServing
  private let bindingRepository: any RoutineSyncRepository
  private let bindingValidator: RoutineTTSBindingValidator
  private let routineRepository: (any RoutineRepository)?
  private let audioCache: RoutineTTSAudioCache?
  private let downloader: any RoutineTTSAudioDownloading
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let serverNamespace: RoutineSyncServerNamespace
  private let resolver: RoutineTTSCuePlanResolver
  private let foregroundPollingPolicy: RoutineTTSForegroundPollingPolicy
  private let prefetchPollingPolicy: RoutineTTSPrefetchPollingPolicy
  private let diagnostics: RoutineTTSDiagnostics
  /// `RoutineSyncBlockReason` carries no account or routine content, so it is
  /// safe to log verbatim, unlike the identifier-free `RoutineTTSDiagnostics`.
  private let blockReasonLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineTTSWarmup"
  )
  private let voiceSelectionVersionStore: any RoutineTTSVoiceSelectionVersionStoring
  private let prefetchJobStore: (any RoutineTTSPrefetchJobStoring)?
  private weak var backgroundTransferManager:
    (any RoutineTTSBackgroundTransferManaging)?
  private let preparationStatusCenter: RoutineTTSPreparationStatusCenter?
  private weak var playbackSessionInvalidator:
    (any RoutineTTSPlaybackSessionInvalidating)?

  private var preparedPlans: [LocalPlanKey: PreparedPlan] = [:]
  private var operationTask: Task<Void, Never>?
  private var operationGeneration: UInt = 0
  private var sessionTransitionTask: Task<Void, Never>?
  private var isSceneActive = false
  private var observedIdentity: AccountSessionIdentity?
  /// If a purge fails, normalized cache keys can still resolve old bytes.
  /// Keep the affected account muted until a later purge succeeds instead of
  /// risking the newly selected voice playing stale audio.
  private var cacheUnavailableMemberIDs = Set<Int64>()
  private var encounteredPendingGeneration = false

  init(
    remoteService: any RoutineTTSRemoteServing,
    bindingRepository: any RoutineSyncRepository,
    routineRepository: (any RoutineRepository)? = nil,
    audioCache: RoutineTTSAudioCache?,
    downloader: any RoutineTTSAudioDownloading,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    serverNamespace: RoutineSyncServerNamespace = .production,
    resolver: RoutineTTSCuePlanResolver = RoutineTTSCuePlanResolver(),
    foregroundPollingPolicy: RoutineTTSForegroundPollingPolicy =
      RoutineTTSForegroundPollingPolicy(),
    prefetchPollingPolicy: RoutineTTSPrefetchPollingPolicy =
      RoutineTTSPrefetchPollingPolicy(),
    diagnostics: RoutineTTSDiagnostics = RoutineTTSDiagnostics(),
    voiceSelectionVersionStore: any RoutineTTSVoiceSelectionVersionStoring,
    prefetchJobStore: (any RoutineTTSPrefetchJobStoring)? = nil,
    backgroundTransferManager:
      (any RoutineTTSBackgroundTransferManaging)? = nil,
    preparationStatusCenter: RoutineTTSPreparationStatusCenter? = nil
  ) {
    self.remoteService = remoteService
    self.bindingRepository = bindingRepository
    self.bindingValidator = RoutineTTSBindingValidator(
      bindingRepository: bindingRepository,
      serverNamespace: serverNamespace
    )
    self.routineRepository = routineRepository
    self.audioCache = audioCache
    self.downloader = downloader
    self.sessionIdentityProvider = sessionIdentityProvider
    self.serverNamespace = serverNamespace
    self.resolver = resolver
    self.foregroundPollingPolicy = foregroundPollingPolicy
    self.prefetchPollingPolicy = prefetchPollingPolicy
    self.diagnostics = diagnostics
    self.voiceSelectionVersionStore = voiceSelectionVersionStore
    self.prefetchJobStore = prefetchJobStore
    self.backgroundTransferManager = backgroundTransferManager
    self.preparationStatusCenter = preparationStatusCenter
    let identity = sessionIdentityProvider.currentAccountSessionIdentity
    observedIdentity = identity
  }

  func setSceneActive(_ isActive: Bool) {
    isSceneActive = isActive
    guard isActive else {
      operationGeneration &+= 1
      operationTask?.cancel()
      operationTask = nil
      RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
      return
    }
    resumePersistedTransfers()
    prepareActiveRoutines()
  }

  func setPlaybackSessionInvalidator(
    _ invalidator: any RoutineTTSPlaybackSessionInvalidating
  ) {
    playbackSessionInvalidator = invalidator
  }

  func accountSessionDidChange() {
    playbackSessionInvalidator?.invalidatePlaybackForAccountSessionChange()
    let previousIdentity = observedIdentity
    let currentIdentity = sessionIdentityProvider?.currentAccountSessionIdentity
    observedIdentity = currentIdentity
    preparedPlans.removeAll()
    if currentIdentity == nil {
      preparationStatusCenter?.reset()
      Task { [weak self] in
        await self?.backgroundTransferManager?.discardAllTransfers()
      }
    } else if let currentIdentity {
      Task { [weak self] in
        await self?.resumePersistedTransfersNow(identity: currentIdentity)
      }
    }
    var memberIDsToPurge = Set<Int64>()
    if let previousIdentity {
      cacheUnavailableMemberIDs.insert(previousIdentity.memberID)
      memberIDsToPurge.insert(previousIdentity.memberID)
    }
    // A prior failed purge must be retried when that account becomes current
    // again; otherwise the safety gate would keep TTS muted for this process.
    if let currentIdentity,
       cacheUnavailableMemberIDs.contains(currentIdentity.memberID) {
      memberIDsToPurge.insert(currentIdentity.memberID)
    }
    guard let audioCache else {
      sessionTransitionTask?.cancel()
      sessionTransitionTask = nil
      return
    }
    let previousTransition = sessionTransitionTask
    sessionTransitionTask = Task { [weak self, audioCache, diagnostics, serverNamespace] in
      _ = await previousTransition?.value
      for memberID in memberIDsToPurge {
        do {
          try await audioCache.purge(
            accountID: String(memberID),
            namespace: serverNamespace.rawValue
          )
          self?.cacheUnavailableMemberIDs.remove(memberID)
        } catch {
          diagnostics.record(.cachePurgeFailed)
        }
      }
    }
    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      guard let self else { return }
      _ = await transition?.value
      guard sessionIdentityProvider?.currentAccountSessionIdentity == currentIdentity,
            isSceneActive,
            let currentIdentity,
            isAudioCacheUsable(for: currentIdentity) else { return }
      guard let routineRepository else { return }
      await prepareActiveRoutinesNow(
        identity: currentIdentity,
        routineRepository: routineRepository
      )
    }
  }

  /// A server-side voice switch can reuse the same generated-object path with
  /// a new signed URL. The cache key intentionally normalizes URL queries, so
  /// invalidate this account's namespace before any next cue can use old
  /// bytes. Rewarming is deferred until the purge completes.
  func serverVoiceSelectionDidChange(
    memberID: Int64,
    selectionVersion: Int64? = nil,
    selectedTTSID: Int64? = nil
  ) {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          identity.memberID == memberID else {
      return
    }

    if let selectionVersion, selectionVersion >= 0 {
      voiceSelectionVersionStore.setSelectionVersion(
        selectionVersion,
        forMemberID: memberID
      )
    } else {
      voiceSelectionVersionStore.removeSelectionVersion(forMemberID: memberID)
    }
    if let selectedTTSID, selectedTTSID > 0 {
      voiceSelectionVersionStore.setSelectedTTSID(
        selectedTTSID,
        forMemberID: memberID
      )
    } else {
      voiceSelectionVersionStore.removeSelectedTTSID(forMemberID: memberID)
    }
    preparedPlans.removeAll()
    preparationStatusCenter?.begin(
      memberID: memberID,
      selectionVersion: selectionVersion,
      selectedTTSID: selectedTTSID
    )
    cacheUnavailableMemberIDs.insert(memberID)
    let staleTransferReconciliation = Task { [weak self] in
      await self?.resumePersistedTransfersNow(identity: identity)
    }
    guard let audioCache else {
      return
    }
    let previousTransition = sessionTransitionTask
    sessionTransitionTask = Task { [weak self, audioCache, diagnostics, serverNamespace] in
      _ = await previousTransition?.value
      _ = await staleTransferReconciliation.value
      do {
        try await audioCache.purge(
          accountID: String(memberID),
          namespace: serverNamespace.rawValue
        )
        self?.cacheUnavailableMemberIDs.remove(memberID)
        diagnostics.record(.voiceCacheInvalidated)
      } catch {
        diagnostics.record(.cachePurgeFailed)
      }
    }

    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      guard let self else { return }
      _ = await transition?.value
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isSceneActive,
            isAudioCacheUsable(for: identity),
            let routineRepository else {
        return
      }
      await prepareActiveRoutinesNow(
        identity: identity,
        routineRepository: routineRepository
      )
      await resumePersistedTransfersNow(identity: identity)
    }
  }

  /// The outbox records group and child bindings atomically before reporting a
  /// completed mutation. Starting a background warm-up here closes the gap
  /// between saving a server recommendation and its first playable cue.
  func routineSyncDidComplete() {
    guard isSceneActive,
          let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity) else { return }
    prepareActiveRoutines()
  }

  /// Called from BGAppRefresh and background-session completion. This performs
  /// only read-only status GETs and transfer reconciliation.
  func resumeBackgroundPrefetchOpportunity() async {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity),
          let routineRepository else {
      return
    }
    await resumePersistedTransfersNow(identity: identity)
    if let operationTask {
      _ = await operationTask.value
      return
    }
    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      _ = await transition?.value
      guard self?.sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            self?.isAudioCacheUsable(for: identity) == true else {
        return
      }
      await self?.prepareActiveRoutinesNow(
        identity: identity,
        routineRepository: routineRepository
      )
    }
    _ = await operationTask?.value
  }

  func prepare(routineGroupLocalID: UUID, routineLocalIDs: [UUID]) {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity),
          !routineLocalIDs.isEmpty else { return }
    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      _ = await transition?.value
      guard self?.sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
        return
      }
      await self?.prepareNow(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalIDs: routineLocalIDs,
        identity: identity
      )
    }
  }

  /// A routine step expects server-first playback when it has a validated
  /// current-account binding or a recorded server-sync intent. This deliberately
  /// does not depend on cache availability: a voice change temporarily
  /// invalidates the cache, but must never downgrade a synced routine to a
  /// bundled voice during that purge.
  func expectsServerGeneratedIntro(
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) -> Bool {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity else {
      return false
    }

    do {
      guard let groupBinding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routineGroup,
        localEntityID: routineGroupLocalID
      ) else {
        return try bindingValidator.hasServerSyncIntent(
          memberID: identity.memberID,
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
      }
      guard bindingValidator.isValidGroupBinding(
        groupBinding,
        routineGroupLocalID: routineGroupLocalID,
        identity: identity
      ) else {
        // A current-account binding that fails validation is still evidence of
        // server intent. Fail closed instead of treating it as a local routine.
        return true
      }
      guard let routineBinding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routine,
        localEntityID: routineLocalID
      ) else {
        return try bindingValidator.hasServerSyncIntent(
          memberID: identity.memberID,
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
      }
      guard bindingValidator.isValidRoutineBinding(
        routineBinding,
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        groupBinding: groupBinding,
        identity: identity
      ) else {
        // A current-account binding that fails validation is still evidence of
        // server intent. Fail closed instead of treating it as a local routine.
        return true
      }
      return true
    } catch {
      // A transient local binding-store failure must never turn a selected
      // server voice into a bundled fallback. Present retry instead.
      return true
    }
  }

  /// Waits only for the server readiness states that can still become
  /// playable soon: a locally staged binding, a queued/attempting binding, or
  /// a valid `PENDING` TTS response. This is called by a custom routine's
  /// first cue, before the remote-first player reads the cache.
  func prepareAndWait(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) async -> RoutineTTSForegroundPreparationStatus {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity),
          !routineLocalIDs.isEmpty else { return .unavailable }

    // Keep an already-running active-routine warm-up alive. It may have
    // fetched the final manifest or started the same cache download already.
    // The cache coalesces matching foreground loads after this join.
    let transition = sessionTransitionTask
    let existingPreparation = operationTask
    let preparationTask = Task { [weak self] in
      guard let self else { return RoutineTTSForegroundPreparationStatus.unavailable }
      _ = await transition?.value
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isAudioCacheUsable(for: identity) else {
        return Task.isCancelled ? .cancelled : .unavailable
      }
      _ = await existingPreparation?.value
      return await pollForegroundPreparation(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalIDs: routineLocalIDs,
        identity: identity
      )
    }
    let status = await waitForForegroundPreparation(preparationTask)
    if status == .retryablePending {
      diagnostics.record(.foregroundRetryExhausted)
      await scheduleForegroundRetry(
        identity: identity,
        routineGroupLocalID: routineGroupLocalID,
        routineLocalIDs: routineLocalIDs
      )
    }
    return status
  }

  private func pollForegroundPreparation(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID],
    identity: AccountSessionIdentity
  ) async -> RoutineTTSForegroundPreparationStatus {
    for attempt in 0..<foregroundPollingPolicy.maximumAttempts {
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isAudioCacheUsable(for: identity) else {
        return Task.isCancelled ? .cancelled : .unavailable
      }

      let result = await prepareForegroundNow(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalIDs: routineLocalIDs,
        identity: identity
      )
      switch result {
      case .prepared:
        diagnostics.record(.foregroundPrepared)
        return .prepared

      case .unavailable:
        return .unavailable

      case .pendingBinding:
        guard attempt + 1 < foregroundPollingPolicy.maximumAttempts else {
          return .retryablePending
        }
        diagnostics.record(.waitingForBinding)
        do {
          try await Task.sleep(for: foregroundPollingPolicy.retryDelay)
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .unavailable
        }

      case .pendingGeneration:
        guard attempt + 1 < foregroundPollingPolicy.maximumAttempts else {
          return .retryablePending
        }
        diagnostics.record(.waitingForGeneration)
        do {
          try await Task.sleep(for: foregroundPollingPolicy.retryDelay)
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .unavailable
        }

      case .retryableDownload, .retryableRemoteRequest:
        guard attempt + 1 < foregroundPollingPolicy.maximumAttempts else {
          return .retryablePending
        }
        do {
          try await Task.sleep(for: foregroundPollingPolicy.retryDelay)
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .unavailable
        }
      }
    }

    return .retryablePending
  }

  private func waitForForegroundPreparation(
    _ preparationTask: Task<RoutineTTSForegroundPreparationStatus, Never>
  ) async -> RoutineTTSForegroundPreparationStatus {
    let gate = RoutineTTSForegroundWaitGate()
    let completionObserver = Task {
      await gate.resolve(await preparationTask.value)
    }
    let timeoutObserver = Task { [maximumWait = foregroundPollingPolicy.maximumWait] in
      do {
        try await Task.sleep(for: maximumWait)
      } catch {
        return
      }
      await gate.resolve(.retryablePending)
    }

    let result = await withTaskCancellationHandler {
      await gate.value()
    } onCancel: {
      Task {
        await gate.resolve(.cancelled)
      }
    }

    timeoutObserver.cancel()
    completionObserver.cancel()
    if result == .retryablePending || result == .cancelled {
      // Cancelling this waiter stops further status polling. A cache actor's
      // already-created in-flight download and the independent background
      // transfer remain alive and can still finish for the next playback.
      preparationTask.cancel()
    }
    return result
  }

  private func scheduleForegroundRetry(
    identity: AccountSessionIdentity,
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) async {
    if let prefetchJobStore,
       let jobs = try? await prefetchJobStore.allJobs() {
      let requestedRoutineIDs = Set(routineLocalIDs)
      for var job in jobs where
        job.memberID == identity.memberID
          && job.selectionVersion == currentSelectionVersion(for: identity)
          && job.selectedTTSID == currentSelectedTTSID(for: identity)
          && job.assetKind == .routineIntro
          && job.routineGroupLocalID == routineGroupLocalID
          && job.routineLocalID.map(requestedRoutineIDs.contains) == true
          && job.state == .pendingRemote {
        job.state = .retryScheduled
        job.updatedAt = prefetchPollingPolicy.now()
        try? await prefetchJobStore.replace(job)
      }
    }
    preparationStatusCenter?.report(
      .retryScheduled,
      component: .routineIntro,
      memberID: identity.memberID,
      selectionVersion: currentSelectionVersion(for: identity),
      selectedTTSID: currentSelectedTTSID(for: identity)
    )
    RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
  }

  func localAudioURLs(for request: RoutineTTSLocalAudioRequest) async -> [URL]? {
    let planKey = LocalPlanKey(
      routineGroupLocalID: request.routineGroupLocalID,
      routineLocalID: request.routineLocalID
    )
    guard let audioCache,
          let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity) else {
      diagnostics.record(.cachePlanMissing)
      return nil
    }
    if preparedPlans[planKey] == nil {
      _ = await restorePreparedPlanFromPersistence(
        identity: identity,
        routineGroupLocalID: request.routineGroupLocalID,
        routineLocalID: request.routineLocalID,
        routineTitle: request.routineTitle,
        routineType: request.routineType
      )
    }
    guard let plan = preparedPlans[planKey],
          plan.identity == identity,
          plan.fingerprint == RoutineTTSLocalFingerprint(
            title: request.routineTitle,
            type: request.routineType
          ),
          !plan.keys.isEmpty else {
      diagnostics.record(.cachePlanMissing)
      return nil
    }

    switch bindingValidator.validateCurrentBinding(
      routineGroupLocalID: planKey.routineGroupLocalID,
      routineLocalID: planKey.routineLocalID,
      expectedGroupRemoteID: plan.routineGroupRemoteID,
      expectedRoutineRemoteID: plan.routineRemoteID,
      identity: identity
    ) {
    case .valid, .unavailable:
      // A repository read failure is transient. The manifest remains guarded
      // by identity, local fingerprint, and its last known valid binding.
      break
    case .invalid:
      preparedPlans[planKey] = nil
      diagnostics.record(.responseUnavailable)
      return nil
    }

    var urls: [URL] = []
    urls.reserveCapacity(plan.keys.count)
    // A stale byte is usable only while its fresh, identity-gated in-memory
    // manifest survives. Session changes remove the manifest before purge.
    for key in plan.keys {
      guard let url = await audioCache.cachedFileURL(for: key, allowStale: true) else {
        preparedPlans[planKey] = nil
        diagnostics.record(.cachePlanMissing)
        return nil
      }
      urls.append(url)
    }

    guard sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return nil
    }
    return urls
  }

  private func prepareActiveRoutines() {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity),
          let routineRepository else { return }
    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      _ = await transition?.value
      guard self?.sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            self?.isAudioCacheUsable(for: identity) == true else {
        return
      }
      await self?.prepareActiveRoutinesNow(
        identity: identity,
        routineRepository: routineRepository
      )
    }
  }

  private func prepareActiveRoutinesNow(
    identity: AccountSessionIdentity,
    routineRepository: any RoutineRepository
  ) async {
    let routines: [Routine]
    guard isAudioCacheUsable(for: identity) else { return }
    do {
      routines = try routineRepository.fetchActiveRoutines().filter(\.isActive)
    } catch {
      return
    }

    guard !routines.isEmpty else {
      preparationStatusCenter?.report(
        .ready,
        component: .routineIntro,
        memberID: identity.memberID,
        selectionVersion: currentSelectionVersion(for: identity),
        selectedTTSID: currentSelectedTTSID(for: identity)
      )
      return
    }

    for attempt in 0..<prefetchPollingPolicy.maximumAttempts {
      encounteredPendingGeneration = false
      for routine in routines {
        guard !Task.isCancelled,
              sessionIdentityProvider?.currentAccountSessionIdentity == identity,
              isAudioCacheUsable(for: identity) else {
          return
        }
        await prepareNow(
          routineGroupLocalID: routine.id,
          routineLocalIDs: routine.steps.map(\.id),
          identity: identity
        )
      }
      guard encounteredPendingGeneration,
            attempt + 1 < prefetchPollingPolicy.maximumAttempts else {
        break
      }
      do {
        try await prefetchPollingPolicy.sleep(
          prefetchPollingPolicy.retryDelays[attempt]
        )
      } catch {
        return
      }
    }
  }

  private func replaceOperation(
    _ operation: @escaping @MainActor () async -> Void
  ) {
    let previous = operationTask
    previous?.cancel()
    operationGeneration &+= 1
    let requestedGeneration = operationGeneration
    operationTask = Task { [weak self] in
      _ = await previous?.value
      guard !Task.isCancelled else { return }
      await operation()
      guard let self,
            requestedGeneration == operationGeneration else { return }
      operationTask = nil
    }
  }

  private func prepareNow(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID],
    identity: AccountSessionIdentity
  ) async {
    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else { return }

    let initialLocalSteps: [UUID: RoutineStep]
    do {
      guard let routineRepository,
            let routine = try routineRepository.routine(id: routineGroupLocalID) else {
        invalidatePreparedPlans(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: routineLocalIDs
        )
        return
      }
      initialLocalSteps = Dictionary(
        uniqueKeysWithValues: routine.steps
          .filter { routineLocalIDs.contains($0.id) }
          .map { ($0.id, $0) }
      )
    } catch {
      // Local-store read failures are transient; retain a previously checked
      // manifest until it can be revalidated at playback.
      return
    }

    let groupBinding: RoutineServerBinding
    do {
      guard let binding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routineGroup,
        localEntityID: routineGroupLocalID
      ), bindingValidator.isValidGroupBinding(
        binding,
        routineGroupLocalID: routineGroupLocalID,
        identity: identity
      ) else {
        invalidatePreparedPlans(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: routineLocalIDs
        )
        diagnostics.record(.missingGroupBinding)
        return
      }
      groupBinding = binding
    } catch {
      // Do not discard a valid plan on a transient binding-store failure.
      return
    }

    let response: [ServerRoutineTTSRoutine]
    if await shouldDeferRemoteRequest(
      identity: identity,
      routineGroupLocalID: routineGroupLocalID
    ) {
      encounteredPendingGeneration = true
      return
    }
    do {
      response = try await remoteService.fetchRoutineTTS(
        routineGroupID: groupBinding.remoteID,
        identity: identity
      )
    } catch {
      diagnostics.record(.remoteFetchFailed)
      preparationStatusCenter?.report(
        .retryScheduled,
        component: .routineIntro,
        memberID: identity.memberID,
        selectionVersion: currentSelectionVersion(for: identity),
        selectedTTSID: currentSelectedTTSID(for: identity)
      )
      RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
      return
    }

    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else { return }

    for routineLocalID in routineLocalIDs {
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isAudioCacheUsable(for: identity) else {
        return
      }
      let localKey = LocalPlanKey(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID
      )
      let routineBinding: RoutineServerBinding?
      guard let localStep = initialLocalSteps[routineLocalID] else {
        preparedPlans[localKey] = nil
        continue
      }
      do {
        routineBinding = try bindingRepository.binding(
          memberID: identity.memberID,
          entityKind: .routine,
          localEntityID: routineLocalID
        )
      } catch {
        // A transient repository failure must not discard a previously
        // identity- and fingerprint-validated plan.
        continue
      }

      guard let routineBinding else {
        preparedPlans[localKey] = nil
        diagnostics.record(.missingRoutineBinding)
        continue
      }
      guard let remoteRoutine = response.first(where: {
        $0.routineID == routineBinding.remoteID
      }), Self.matches(remoteRoutine: remoteRoutine, localStep: localStep) else {
        preparedPlans[localKey] = nil
        diagnostics.record(.responseUnavailable)
        continue
      }

      let resolution = resolver.resolve(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        groupBinding: groupBinding,
        routineBinding: routineBinding,
        response: response,
        currentSelectionVersion: currentSelectionVersion(for: identity)
      )
      let assets: [RoutineTTSResolvedAsset]
      switch resolution {
      case .playable(let resolvedAssets):
        assets = resolvedAssets
      case .pending:
        encounteredPendingGeneration = true
        await persistPendingIntroJob(
          identity: identity,
          localStep: localStep,
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID,
          groupBinding: groupBinding,
          routineBinding: routineBinding
        )
        // Preserve a complete prior plan while a replacement generation is
        // still pending. A complete response replaces it atomically below.
        continue
      case .unavailable:
        preparedPlans[localKey] = nil
        diagnostics.record(.responseUnavailable)
        continue
      }


      if await persistPlayableIntroJobIfSupported(
        identity: identity,
        localStep: localStep,
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        groupBinding: groupBinding,
        routineBinding: routineBinding,
        assets: assets
      ) {
        continue
      }

      let keys: [RoutineTTSAudioCacheKey]
      do {
        keys = try await cacheKeys(
          for: assets,
          groupBinding: groupBinding,
          identity: identity
        )
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled,
              sessionIdentityProvider?.currentAccountSessionIdentity == identity,
              isAudioCacheUsable(for: identity) else {
          return
        }
        diagnostics.record(.audioDownloadFailed)
        continue
      }

      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isAudioCacheUsable(for: identity) else {
        return
      }
      // 전경 경로와 같은 일이다. 예전에는 여기에 같은 로직이 한 벌 더 있었고,
      // 한쪽만 고치면 배경으로 데운 안내와 재생 직전에 데운 안내가 서로 다른
      // 기준으로 실린다.
      switch publishPreparedPlan(
        candidate: ForegroundCandidate(
          localStep: localStep,
          localKey: localKey,
          routineGroupRemoteID: groupBinding.remoteID,
          routineRemoteID: routineBinding.remoteID,
          assets: assets
        ),
        keys: keys,
        identity: identity
      ) {
      case .published:
        break
      case .rejectedStalePlan:
        preparedPlans[localKey] = nil
      case .unavailable:
        break
      }
    }
  }

  private func prepareForegroundNow(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID],
    identity: AccountSessionIdentity
  ) async -> ForegroundPreparationResult {
    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return .unavailable
    }

    let requestedRoutineIDs = Self.uniqueRoutineIDs(routineLocalIDs)
    guard !requestedRoutineIDs.isEmpty else { return .unavailable }

    let initialLocalSteps: [UUID: RoutineStep]
    do {
      guard let routineRepository,
            let routine = try routineRepository.routine(id: routineGroupLocalID) else {
        invalidatePreparedPlans(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: requestedRoutineIDs
        )
        return .unavailable
      }
      initialLocalSteps = Dictionary(
        uniqueKeysWithValues: routine.steps
          .filter { requestedRoutineIDs.contains($0.id) }
          .map { ($0.id, $0) }
      )
    } catch {
      return .unavailable
    }
    guard initialLocalSteps.count == requestedRoutineIDs.count else {
      invalidatePreparedPlans(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalIDs: requestedRoutineIDs
      )
      return .unavailable
    }

    let groupBinding: RoutineServerBinding
    do {
      guard let binding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routineGroup,
        localEntityID: routineGroupLocalID
      ) else {
        invalidatePreparedPlans(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: requestedRoutineIDs
        )
        if try bindingValidator.hasPendingGroupBinding(
          memberID: identity.memberID,
          routineGroupLocalID: routineGroupLocalID
        ) {
          return .pendingBinding
        }
        let mutation = try? bindingRepository.mutation(
          memberID: identity.memberID,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: routineGroupLocalID
        )
        if let mutation {
          let attemptAgeSeconds = mutation.attempt.map {
            Int(Date().timeIntervalSince($0.attemptedAt))
          }
          blockReasonLogger.notice(
            "createRoutineGroup mutation state: \(mutation.state.rawValue, privacy: .public), blockReason: \(mutation.blockReason?.rawValue ?? "nil", privacy: .public), generation: \(mutation.generation, privacy: .public), lastAttemptAgeSeconds: \(attemptAgeSeconds.map(String.init) ?? "nil", privacy: .public)"
          )
        }
        diagnostics.record(
          mutation == nil
            ? .missingGroupBindingNoMutationRecord
            : .missingGroupBindingMutationBlocked
        )
        return .unavailable
      }
      guard bindingValidator.isValidGroupBinding(
        binding,
        routineGroupLocalID: routineGroupLocalID,
        identity: identity
      ) else {
        invalidatePreparedPlans(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: requestedRoutineIDs
        )
        diagnostics.record(.missingGroupBindingInvalidExistingBinding)
        return .unavailable
      }
      groupBinding = binding
    } catch {
      // Keep an existing plan through transient store failures. Playback
      // validates its last known binding before selecting a file.
      return .unavailable
    }

    let response: [ServerRoutineTTSRoutine]
    do {
      response = try await remoteService.fetchRoutineTTS(
        routineGroupID: groupBinding.remoteID,
        identity: identity
      )
    } catch is CancellationError {
      return .unavailable
    } catch {
      diagnostics.record(.remoteFetchFailed)
      return .retryableRemoteRequest
    }

    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return .unavailable
    }

    var candidates: [ForegroundCandidate] = []
    candidates.reserveCapacity(requestedRoutineIDs.count)
    for routineLocalID in requestedRoutineIDs {
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isAudioCacheUsable(for: identity),
            let localStep = initialLocalSteps[routineLocalID] else {
        return .unavailable
      }

      let routineBinding: RoutineServerBinding?
      do {
        routineBinding = try bindingRepository.binding(
          memberID: identity.memberID,
          entityKind: .routine,
          localEntityID: routineLocalID
        )
      } catch {
        // Preserve an existing plan through transient store failures.
        return .unavailable
      }

      guard let routineBinding else {
        invalidatePreparedPlan(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
        let hasPendingBinding: Bool
        do {
          hasPendingBinding = try bindingValidator.hasPendingRoutineBinding(
            memberID: identity.memberID,
            routineGroupLocalID: routineGroupLocalID,
            routineLocalID: routineLocalID
          )
        } catch {
          return .unavailable
        }
        if hasPendingBinding {
          return .pendingBinding
        }
        diagnostics.record(.missingRoutineBinding)
        return .unavailable
      }
      guard let remoteRoutine = response.first(where: {
        $0.routineID == routineBinding.remoteID
      }), Self.matches(remoteRoutine: remoteRoutine, localStep: localStep) else {
        invalidatePreparedPlan(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
        diagnostics.record(.responseUnavailable)
        return .unavailable
      }

      switch resolver.resolve(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        groupBinding: groupBinding,
        routineBinding: routineBinding,
        response: response,
        currentSelectionVersion: currentSelectionVersion(for: identity)
      ) {
      case .pending:
        await persistPendingIntroJob(
          identity: identity,
          localStep: localStep,
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID,
          groupBinding: groupBinding,
          routineBinding: routineBinding
        )
        return .pendingGeneration

      case .unavailable:
        invalidatePreparedPlan(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
        diagnostics.record(.responseUnavailable)
        return .unavailable

      case .playable(let assets):
        candidates.append(ForegroundCandidate(
          localStep: localStep,
          localKey: LocalPlanKey(
            routineGroupLocalID: routineGroupLocalID,
            routineLocalID: routineLocalID
          ),
          routineGroupRemoteID: groupBinding.remoteID,
          routineRemoteID: routineBinding.remoteID,
          assets: assets
        ))
      }
    }

    var cachedCandidates: [(ForegroundCandidate, [RoutineTTSAudioCacheKey])] = []
    cachedCandidates.reserveCapacity(candidates.count)
    do {
      for candidate in candidates {
        guard !Task.isCancelled,
              sessionIdentityProvider?.currentAccountSessionIdentity == identity,
              isAudioCacheUsable(for: identity) else {
          return .unavailable
        }
        let keys = try await cacheKeys(
          for: candidate.assets,
          groupBinding: groupBinding,
          identity: identity
        )
        cachedCandidates.append((candidate, keys))
      }
    } catch is CancellationError {
      return .unavailable
    } catch {
      diagnostics.record(.audioDownloadFailed)
      return .retryableDownload
    }

    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return .unavailable
    }
    for (candidate, keys) in cachedCandidates {
      // 전경에서는 어느 쪽 실패든 결과가 같다 — 지금 들려줄 수 없다.
      guard case .published = publishPreparedPlan(
        candidate: candidate,
        keys: keys,
        identity: identity
      ) else {
        return .unavailable
      }
    }
    return .prepared
  }

  private func cacheKeys(
    for assets: [RoutineTTSResolvedAsset],
    groupBinding: RoutineServerBinding,
    identity: AccountSessionIdentity
  ) async throws -> [RoutineTTSAudioCacheKey] {
    guard let audioCache else {
      throw RoutineTTSAudioCacheError.storageFailure
    }
    let keys = assets.map {
      RoutineTTSAudioCacheKey(
        accountID: String(identity.memberID),
        namespace: serverNamespace.rawValue,
        routineGroupID: groupBinding.remoteID,
        routineID: $0.remoteRoutineID,
        stepID: $0.remoteStepID,
        remoteURL: $0.remoteURL
      )
    }

    for (key, asset) in zip(keys, assets) {
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity,
            isAudioCacheUsable(for: identity) else {
        throw CancellationError()
      }
      _ = try await audioCache.fileURL(for: key) { [weak self, downloader] staging in
        guard !Task.isCancelled,
              await self?.hasCurrentIdentity(identity) == true else {
          throw CancellationError()
        }
        let downloaded = try await downloader.download(
          RoutineTTSAudioDownloadRequest(remoteURL: asset.remoteURL),
          stagingDirectory: staging
        )
        guard !Task.isCancelled,
              await self?.hasCurrentIdentity(identity) == true else {
          throw CancellationError()
        }
        return downloaded
      }
    }
    return keys
  }

  private func persistPendingIntroJob(
    identity: AccountSessionIdentity,
    localStep: RoutineStep,
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    groupBinding: RoutineServerBinding,
    routineBinding: RoutineServerBinding
  ) async {
    guard let prefetchJobStore else { return }
    let previous = try? await prefetchJobStore.allJobs().first(where: {
      $0.memberID == identity.memberID
        && $0.selectionVersion == currentSelectionVersion(for: identity)
        && $0.selectedTTSID == currentSelectedTTSID(for: identity)
        && $0.assetKind == .routineIntro
        && $0.routineGroupLocalID == routineGroupLocalID
        && $0.routineLocalID == routineLocalID
    })
    let attempt = min(
      (previous?.remoteAttemptCount ?? 0) + 1,
      prefetchPollingPolicy.maximumAttempts
    )
    let retryDelay: TimeInterval
    if prefetchPollingPolicy.retryDelays.isEmpty {
      retryDelay = 15 * 60
    } else {
      let delayIndex = min(
        max(0, attempt - 1),
        prefetchPollingPolicy.retryDelays.count - 1
      )
      retryDelay = Self.timeInterval(
        for: prefetchPollingPolicy.retryDelays[delayIndex]
      )
    }
    let job = RoutineTTSPrefetchJob(
      id: previous?.id ?? UUID(),
      memberID: identity.memberID,
      selectionVersion: currentSelectionVersion(for: identity),
      selectedTTSID: currentSelectedTTSID(for: identity),
      assetKind: .routineIntro,
      routineGroupLocalID: routineGroupLocalID,
      routineLocalID: routineLocalID,
      routineFingerprint: RoutineTTSPrefetchJob.fingerprint(
        title: localStep.title,
        type: localStep.type
      ),
      routineGroupRemoteID: groupBinding.remoteID,
      routineRemoteID: routineBinding.remoteID,
      state: attempt >= prefetchPollingPolicy.maximumAttempts
        ? .retryScheduled
        : .pendingRemote,
      assets: previous?.assets ?? [],
      remoteAttemptCount: attempt,
      nextRemoteAttemptAt: prefetchPollingPolicy.now().addingTimeInterval(retryDelay)
    )
    _ = try? await prefetchJobStore.upsert(job)
    preparationStatusCenter?.report(
      attempt >= prefetchPollingPolicy.maximumAttempts
        ? .retryScheduled
        : .preparing,
      component: .routineIntro,
      memberID: identity.memberID,
      selectionVersion: currentSelectionVersion(for: identity),
      selectedTTSID: currentSelectedTTSID(for: identity)
    )
    if attempt >= prefetchPollingPolicy.maximumAttempts {
      RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
    }
  }

  private func shouldDeferRemoteRequest(
    identity: AccountSessionIdentity,
    routineGroupLocalID: UUID
  ) async -> Bool {
    guard let prefetchJobStore,
          let jobs = try? await prefetchJobStore.allJobs() else {
      return false
    }
    let matching = jobs.filter {
      $0.memberID == identity.memberID
        && $0.selectionVersion == currentSelectionVersion(for: identity)
        && $0.selectedTTSID == currentSelectedTTSID(for: identity)
        && $0.assetKind == .routineIntro
        && $0.routineGroupLocalID == routineGroupLocalID
        && ($0.state == .pendingRemote || $0.state == .retryScheduled)
    }
    guard !matching.isEmpty,
          matching.allSatisfy({
            guard let next = $0.nextRemoteAttemptAt else { return false }
            return next > prefetchPollingPolicy.now()
          }) else {
      return false
    }
    RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
    return true
  }

  private static func timeInterval(for duration: Duration) -> TimeInterval {
    let components = duration.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
  }

  private func persistPlayableIntroJobIfSupported(
    identity: AccountSessionIdentity,
    localStep: RoutineStep,
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    groupBinding: RoutineServerBinding,
    routineBinding: RoutineServerBinding,
    assets: [RoutineTTSResolvedAsset]
  ) async -> Bool {
    guard let prefetchJobStore,
          let backgroundTransferManager else {
      return false
    }
    let keys = assets.map {
      RoutineTTSAudioCacheKey(
        accountID: String(identity.memberID),
        namespace: serverNamespace.rawValue,
        routineGroupID: groupBinding.remoteID,
        routineID: $0.remoteRoutineID,
        stepID: $0.remoteStepID,
        remoteURL: $0.remoteURL
      )
    }
    let existing = try? await prefetchJobStore.allJobs().first(where: {
      $0.memberID == identity.memberID
        && $0.selectionVersion == currentSelectionVersion(for: identity)
        && $0.selectedTTSID == currentSelectedTTSID(for: identity)
        && $0.assetKind == .routineIntro
        && $0.routineGroupLocalID == routineGroupLocalID
        && $0.routineLocalID == routineLocalID
    })
    let existingStateByKey = Dictionary(
      uniqueKeysWithValues: (existing?.assets ?? []).map {
        ($0.cacheKey, ($0.id, $0.state))
      }
    )
    let persistedAssets = keys.map { key in
      let existingAsset = existingStateByKey[key]
      return RoutineTTSPrefetchAsset(
        id: existingAsset?.0 ?? UUID(),
        cacheKey: key,
        state: existingAsset?.1 ?? .queued
      )
    }
    let job = RoutineTTSPrefetchJob(
      id: existing?.id ?? UUID(),
      memberID: identity.memberID,
      selectionVersion: currentSelectionVersion(for: identity),
      selectedTTSID: currentSelectedTTSID(for: identity),
      assetKind: .routineIntro,
      routineGroupLocalID: routineGroupLocalID,
      routineLocalID: routineLocalID,
      routineFingerprint: RoutineTTSPrefetchJob.fingerprint(
        title: localStep.title,
        type: localStep.type
      ),
      routineGroupRemoteID: groupBinding.remoteID,
      routineRemoteID: routineBinding.remoteID,
      state: .downloading,
      assets: persistedAssets
    )
    do {
      let storedJob = try await prefetchJobStore.upsert(job)
      preparationStatusCenter?.report(
        .preparing,
        component: .routineIntro,
        memberID: identity.memberID,
        selectionVersion: currentSelectionVersion(for: identity),
        selectedTTSID: currentSelectedTTSID(for: identity)
      )
      await backgroundTransferManager.enqueue(jobID: storedJob.id)
      _ = await restorePreparedPlanFromPersistence(
        identity: identity,
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        routineTitle: localStep.title,
        routineType: localStep.type
      )
    } catch {
      preparationStatusCenter?.report(
        .retryScheduled,
        component: .routineIntro,
        memberID: identity.memberID,
        selectionVersion: currentSelectionVersion(for: identity),
        selectedTTSID: currentSelectedTTSID(for: identity)
      )
    }
    return true
  }

  private func resumePersistedTransfers() {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity else {
      return
    }
    Task { [weak self] in
      await self?.resumePersistedTransfersNow(identity: identity)
    }
  }

  private func resumePersistedTransfersNow(
    identity: AccountSessionIdentity
  ) async {
    guard let backgroundTransferManager,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
      return
    }
    await backgroundTransferManager.resumePendingTransfers(
      memberID: identity.memberID,
      selectionVersion: currentSelectionVersion(for: identity),
      selectedTTSID: currentSelectedTTSID(for: identity)
    )
  }

  private func restorePreparedPlanFromPersistence(
    identity: AccountSessionIdentity,
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    routineTitle: String,
    routineType: RoutineStepType
  ) async -> Bool {
    guard let prefetchJobStore,
          let audioCache,
          let job = try? await prefetchJobStore.allJobs().first(where: {
            $0.memberID == identity.memberID
              && $0.selectionVersion == currentSelectionVersion(for: identity)
              && $0.selectedTTSID == currentSelectedTTSID(for: identity)
              && $0.assetKind == .routineIntro
              && $0.routineGroupLocalID == routineGroupLocalID
              && $0.routineLocalID == routineLocalID
              && $0.state == .completed
          }),
          job.routineFingerprint == RoutineTTSPrefetchJob.fingerprint(
            title: routineTitle,
            type: routineType
          ),
          let groupRemoteID = job.routineGroupRemoteID,
          let routineRemoteID = job.routineRemoteID,
          !job.assets.isEmpty else {
      return false
    }
    let keys = job.assets.map(\.cacheKey)
    for key in keys {
      guard await audioCache.cachedFileURL(for: key, allowStale: true) != nil else {
        return false
      }
    }
    preparedPlans[LocalPlanKey(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalID: routineLocalID
    )] = PreparedPlan(
      identity: identity,
      fingerprint: RoutineTTSLocalFingerprint(
        title: routineTitle,
        type: routineType
      ),
      routineGroupRemoteID: groupRemoteID,
      routineRemoteID: routineRemoteID,
      keys: keys
    )
    return true
  }

  private func publishPreparedPlan(
    candidate: ForegroundCandidate,
    keys: [RoutineTTSAudioCacheKey],
    identity: AccountSessionIdentity
  ) -> PlanPublication {
    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return .unavailable
    }
    do {
      guard let routineRepository,
            let routine = try routineRepository.routine(
              id: candidate.localKey.routineGroupLocalID
            ),
            let currentStep = routine.steps.first(where: {
              $0.id == candidate.localKey.routineLocalID
            }) else {
        return .rejectedStalePlan
      }
      let currentFingerprint = RoutineTTSLocalFingerprint(
        title: currentStep.title,
        type: currentStep.type
      )
      let initialFingerprint = RoutineTTSLocalFingerprint(
        title: candidate.localStep.title,
        type: candidate.localStep.type
      )
      guard currentFingerprint == initialFingerprint else {
        return .rejectedStalePlan
      }
      preparedPlans[candidate.localKey] = PreparedPlan(
        identity: identity,
        fingerprint: currentFingerprint,
        routineGroupRemoteID: candidate.routineGroupRemoteID,
        routineRemoteID: candidate.routineRemoteID,
        keys: keys
      )
      return .published
    } catch {
      // 저장소 읽기 실패는 일시적이다. 재생 직전에 바인딩을 다시 확인하므로
      // 들고 있던 계획을 여기서 버릴 이유가 없다.
      return .unavailable
    }
  }

  private static func uniqueRoutineIDs(_ ids: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return ids.filter { seen.insert($0).inserted }
  }

  private func invalidatePreparedPlans(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) {
    for routineLocalID in Self.uniqueRoutineIDs(routineLocalIDs) {
      invalidatePreparedPlan(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID
      )
    }
  }

  private func invalidatePreparedPlan(
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) {
    preparedPlans[LocalPlanKey(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalID: routineLocalID
    )] = nil
  }

  private func isAudioCacheUsable(for identity: AccountSessionIdentity) -> Bool {
    audioCache != nil && !cacheUnavailableMemberIDs.contains(identity.memberID)
  }

  private func currentSelectionVersion(
    for identity: AccountSessionIdentity
  ) -> Int64? {
    voiceSelectionVersionStore.selectionVersion(
      forMemberID: identity.memberID
    )
  }

  private func currentSelectedTTSID(
    for identity: AccountSessionIdentity
  ) -> Int64? {
    voiceSelectionVersionStore.selectedTTSID(
      forMemberID: identity.memberID
    )
  }

  private func hasCurrentIdentity(_ identity: AccountSessionIdentity) -> Bool {
    sessionIdentityProvider?.currentAccountSessionIdentity == identity
      && isAudioCacheUsable(for: identity)
  }

  private static func matches(
    remoteRoutine: ServerRoutineTTSRoutine,
    localStep: RoutineStep
  ) -> Bool {
    let localTitle = RoutineTTSLocalFingerprint(
      title: localStep.title,
      type: localStep.type
    ).normalizedTitle
    let remoteTitle = remoteRoutine.title
      .precomposedStringWithCanonicalMapping
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let remoteType: RoutineStepType
    switch remoteRoutine.type {
    case .check: remoteType = .confirm
    case .timer: remoteType = .timer
    case .input: remoteType = .input
    }
    return !localTitle.isEmpty && localTitle == remoteTitle && localStep.type == remoteType
  }
}
