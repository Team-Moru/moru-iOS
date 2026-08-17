//
//  RoutineTTSWarmupCoordinator.swift
//  Moru
//

import Foundation
import OSLog

/// A bounded retry window used only when a user is about to hear a
/// server-generated routine. Background warming intentionally remains a
/// single request so foregrounding many routines cannot amplify traffic.
nonisolated struct RoutineTTSForegroundPollingPolicy: Equatable, Sendable {
  let maximumAttempts: Int
  let retryDelay: Duration

  init(
    maximumAttempts: Int = 6,
    retryDelay: Duration = .seconds(1)
  ) {
    precondition(maximumAttempts > 0)
    self.maximumAttempts = maximumAttempts
    self.retryDelay = retryDelay
  }
}

/// The result of the bounded foreground wait that precedes a server-only
/// routine cue. Keeping the result explicit prevents callers from treating a
/// missing or still-generating cue as a successfully completed silent cue.
nonisolated enum RoutineTTSForegroundPreparationStatus: Equatable, Sendable {
  case prepared
  case retryablePending
  case unavailable
  case cancelled
}

/// Events are intentionally identifier- and URL-free so they can be read from
/// a TestFlight device console without disclosing account or routine content.
nonisolated enum RoutineTTSDiagnosticEvent: String, Sendable {
  case cachePlanMissing
  case missingGroupBinding
  case missingRoutineBinding
  case remoteFetchFailed
  case responseUnavailable
  case waitingForBinding
  case waitingForGeneration
  case foregroundPrepared
  case foregroundRetryExhausted
  case audioDownloadFailed
  case voiceCacheInvalidated
  case cachePurgeFailed
  case customCueUnavailable
  case serverCueUnavailable
}

nonisolated struct RoutineTTSDiagnostics: Sendable {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineTTS"
  )

  func record(_ event: RoutineTTSDiagnosticEvent) {
    logger.notice(
      "Routine TTS: \(event.rawValue, privacy: .public)"
    )
  }
}

@MainActor
protocol RoutineTTSWarming: AnyObject {
  func prepare(routineGroupLocalID: UUID, routineLocalIDs: [UUID])
  /// Indicates whether this step is synced already or has a pending synced
  /// creation on the current account. A step without that intent remains a
  /// local cue instead of waiting for server audio.
  func expectsServerGeneratedIntro(
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) -> Bool
  func prepareAndWait(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) async -> RoutineTTSForegroundPreparationStatus
}

@MainActor
protocol RoutineTTSVoiceSelectionVersionStoring: AnyObject {
  func selectionVersion(forMemberID memberID: Int64) -> Int64?
  func setSelectionVersion(_ version: Int64, forMemberID memberID: Int64)
  func removeSelectionVersion(forMemberID memberID: Int64)
}

extension RoutineTTSWarming {
  func expectsServerGeneratedIntro(
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) -> Bool {
    false
  }

  /// Keeps lightweight test and preview doubles source-compatible while the
  /// production coordinator supplies the foreground readiness wait.
  func prepareAndWait(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) async -> RoutineTTSForegroundPreparationStatus {
    prepare(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalIDs: routineLocalIDs
    )
    return .prepared
  }
}

@MainActor
final class RoutineTTSWarmupCoordinator: RoutineTTSWarming, RoutineTTSLocalAudioProviding {
  private struct PreparedPlan {
    let identity: AccountSessionIdentity
    let fingerprint: RoutineTTSLocalFingerprint
    let routineGroupRemoteID: Int64
    let routineRemoteID: Int64
    let keys: [RoutineTTSAudioCacheKey]
  }

  private struct CurrentVoiceSelection {
    let identity: AccountSessionIdentity
    let version: Int64
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

  private enum ForegroundPreparationResult {
    case prepared
    case pendingBinding
    case pendingGeneration
    case unavailable
  }

  private struct ForegroundCandidate {
    let localStep: RoutineStep
    let localKey: LocalPlanKey
    let routineGroupRemoteID: Int64
    let routineRemoteID: Int64
    let assets: [RoutineTTSResolvedAsset]
  }

  private enum PreparedPlanBindingValidation {
    case valid
    case invalid
    case unavailable
  }

  private let remoteService: any RoutineTTSRemoteServing
  private let bindingRepository: any RoutineSyncRepository
  private let routineRepository: (any RoutineRepository)?
  private let audioCache: RoutineTTSAudioCache
  private let downloader: any RoutineTTSAudioDownloading
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let serverNamespace: RoutineSyncServerNamespace
  private let resolver: RoutineTTSCuePlanResolver
  private let foregroundPollingPolicy: RoutineTTSForegroundPollingPolicy
  private let diagnostics: RoutineTTSDiagnostics
  private let voiceSelectionVersionStore: any RoutineTTSVoiceSelectionVersionStoring
  private weak var playbackSessionInvalidator:
    (any RoutineTTSPlaybackSessionInvalidating)?

  private var preparedPlans: [LocalPlanKey: PreparedPlan] = [:]
  private var operationTask: Task<Void, Never>?
  private var sessionTransitionTask: Task<Void, Never>?
  private var isSceneActive = false
  private var observedIdentity: AccountSessionIdentity?
  /// Restored only from a version previously received from this member's
  /// successful PATCH response on this device.
  private var currentVoiceSelection: CurrentVoiceSelection?
  /// If a purge fails, normalized cache keys can still resolve old bytes.
  /// Keep the affected account muted until a later purge succeeds instead of
  /// risking the newly selected voice playing stale audio.
  private var cacheUnavailableMemberIDs = Set<Int64>()

  init(
    remoteService: any RoutineTTSRemoteServing,
    bindingRepository: any RoutineSyncRepository,
    routineRepository: (any RoutineRepository)? = nil,
    audioCache: RoutineTTSAudioCache,
    downloader: any RoutineTTSAudioDownloading,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    serverNamespace: RoutineSyncServerNamespace = .production,
    resolver: RoutineTTSCuePlanResolver = RoutineTTSCuePlanResolver(),
    foregroundPollingPolicy: RoutineTTSForegroundPollingPolicy =
      RoutineTTSForegroundPollingPolicy(),
    diagnostics: RoutineTTSDiagnostics = RoutineTTSDiagnostics(),
    voiceSelectionVersionStore: any RoutineTTSVoiceSelectionVersionStoring
  ) {
    self.remoteService = remoteService
    self.bindingRepository = bindingRepository
    self.routineRepository = routineRepository
    self.audioCache = audioCache
    self.downloader = downloader
    self.sessionIdentityProvider = sessionIdentityProvider
    self.serverNamespace = serverNamespace
    self.resolver = resolver
    self.foregroundPollingPolicy = foregroundPollingPolicy
    self.diagnostics = diagnostics
    self.voiceSelectionVersionStore = voiceSelectionVersionStore
    let identity = sessionIdentityProvider.currentAccountSessionIdentity
    observedIdentity = identity
    currentVoiceSelection = restoredVoiceSelection(for: identity)
  }

  func setSceneActive(_ isActive: Bool) {
    isSceneActive = isActive
    guard isActive else {
      operationTask?.cancel()
      operationTask = nil
      return
    }
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
    currentVoiceSelection = restoredVoiceSelection(for: currentIdentity)
    preparedPlans.removeAll()
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
    selectionVersion: Int64? = nil
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
      currentVoiceSelection = CurrentVoiceSelection(
        identity: identity,
        version: selectionVersion
      )
    } else {
      voiceSelectionVersionStore.removeSelectionVersion(forMemberID: memberID)
      currentVoiceSelection = nil
    }
    preparedPlans.removeAll()
    cacheUnavailableMemberIDs.insert(memberID)
    let previousTransition = sessionTransitionTask
    sessionTransitionTask = Task { [weak self, audioCache, diagnostics, serverNamespace] in
      _ = await previousTransition?.value
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
        return try hasServerSyncIntent(
          memberID: identity.memberID,
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
      }
      guard isValidGroupBinding(
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
        return try hasServerSyncIntent(
          memberID: identity.memberID,
          routineGroupLocalID: routineGroupLocalID,
          routineLocalID: routineLocalID
        )
      }
      guard isValidRoutineBinding(
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

    // A first cue has higher priority than an opportunistic active-routine
    // sweep. The cancelled sweep checks cancellation before changing a plan.
    operationTask?.cancel()
    operationTask = nil

    let transition = sessionTransitionTask
    _ = await transition?.value
    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return Task.isCancelled ? .cancelled : .unavailable
    }

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
          diagnostics.record(.foregroundRetryExhausted)
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
          diagnostics.record(.foregroundRetryExhausted)
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
      }
    }

    return .retryablePending
  }

  func localAudioURLs(for request: RoutineTTSLocalAudioRequest) async -> [URL]? {
    let planKey = LocalPlanKey(
      routineGroupLocalID: request.routineGroupLocalID,
      routineLocalID: request.routineLocalID
    )
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          isAudioCacheUsable(for: identity),
          let plan = preparedPlans[planKey],
          plan.identity == identity,
          plan.fingerprint == RoutineTTSLocalFingerprint(
            title: request.routineTitle,
            type: request.routineType
          ),
          !plan.keys.isEmpty else {
      diagnostics.record(.cachePlanMissing)
      return nil
    }

    switch validateCurrentBinding(
      for: plan,
      planKey: planKey,
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
  }

  private func replaceOperation(
    _ operation: @escaping @MainActor () async -> Void
  ) {
    let previous = operationTask
    previous?.cancel()
    operationTask = Task {
      _ = await previous?.value
      guard !Task.isCancelled else { return }
      await operation()
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
      ), isValidGroupBinding(
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
    do {
      response = try await remoteService.fetchRoutineTTS(
        routineGroupID: groupBinding.remoteID,
        identity: identity
      )
    } catch {
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
        // Preserve a complete prior plan while a replacement generation is
        // still pending. A complete response replaces it atomically below.
        continue
      case .unavailable:
        preparedPlans[localKey] = nil
        diagnostics.record(.responseUnavailable)
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
      let currentLocalStep: RoutineStep
      do {
        guard let routine = try routineRepository?.routine(id: routineGroupLocalID),
              let step = routine.steps.first(where: { $0.id == routineLocalID }) else {
          preparedPlans[localKey] = nil
          continue
        }
        currentLocalStep = step
      } catch {
        // A failed local-store read does not prove that the existing plan is
        // invalid; localAudioURLs will revalidate the binding before use.
        continue
      }
      guard RoutineTTSLocalFingerprint(
        title: currentLocalStep.title,
        type: currentLocalStep.type
      ) == RoutineTTSLocalFingerprint(
        title: localStep.title,
        type: localStep.type
      ) else {
        preparedPlans[localKey] = nil
        continue
      }
      preparedPlans[localKey] = PreparedPlan(
        identity: identity,
        fingerprint: RoutineTTSLocalFingerprint(
          title: currentLocalStep.title,
          type: currentLocalStep.type
        ),
        routineGroupRemoteID: groupBinding.remoteID,
        routineRemoteID: routineBinding.remoteID,
        keys: keys
      )
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
        if try hasPendingGroupBinding(
          memberID: identity.memberID,
          routineGroupLocalID: routineGroupLocalID
        ) {
          return .pendingBinding
        }
        diagnostics.record(.missingGroupBinding)
        return .unavailable
      }
      guard isValidGroupBinding(
        binding,
        routineGroupLocalID: routineGroupLocalID,
        identity: identity
      ) else {
        invalidatePreparedPlans(
          routineGroupLocalID: routineGroupLocalID,
          routineLocalIDs: requestedRoutineIDs
        )
        diagnostics.record(.missingGroupBinding)
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
      return .unavailable
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
          hasPendingBinding = try hasPendingRoutineBinding(
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
      return .unavailable
    }

    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return .unavailable
    }
    for (candidate, keys) in cachedCandidates {
      guard publishPreparedPlan(
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

  private func publishPreparedPlan(
    candidate: ForegroundCandidate,
    keys: [RoutineTTSAudioCacheKey],
    identity: AccountSessionIdentity
  ) -> Bool {
    guard !Task.isCancelled,
          sessionIdentityProvider?.currentAccountSessionIdentity == identity,
          isAudioCacheUsable(for: identity) else {
      return false
    }
    do {
      guard let routineRepository,
            let routine = try routineRepository.routine(
              id: candidate.localKey.routineGroupLocalID
            ),
            let currentStep = routine.steps.first(where: {
              $0.id == candidate.localKey.routineLocalID
            }) else {
        return false
      }
      let currentFingerprint = RoutineTTSLocalFingerprint(
        title: currentStep.title,
        type: currentStep.type
      )
      let initialFingerprint = RoutineTTSLocalFingerprint(
        title: candidate.localStep.title,
        type: candidate.localStep.type
      )
      guard currentFingerprint == initialFingerprint else { return false }
      preparedPlans[candidate.localKey] = PreparedPlan(
        identity: identity,
        fingerprint: currentFingerprint,
        routineGroupRemoteID: candidate.routineGroupRemoteID,
        routineRemoteID: candidate.routineRemoteID,
        keys: keys
      )
      return true
    } catch {
      return false
    }
  }

  private func hasPendingGroupBinding(
    memberID: Int64,
    routineGroupLocalID: UUID
  ) throws -> Bool {
    guard let mutation = try bindingRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: routineGroupLocalID
    ) else {
      return false
    }
    return Self.isBindingDeliveryPending(mutation.state)
  }

  private func hasServerSyncIntent(
    memberID: Int64,
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) throws -> Bool {
    if try bindingRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: routineGroupLocalID
    ) != nil {
      return true
    }
    if try bindingRepository.mutation(
      memberID: memberID,
      operation: .addRoutine,
      entityKind: .routine,
      localEntityID: routineLocalID
    ) != nil {
      return true
    }
    return try bindingRepository.binding(
      memberID: memberID,
      entityKind: .routine,
      localEntityID: routineLocalID
    ) != nil
  }

  private func hasPendingRoutineBinding(
    memberID: Int64,
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) throws -> Bool {
    if try hasPendingGroupBinding(
      memberID: memberID,
      routineGroupLocalID: routineGroupLocalID
    ) {
      return true
    }
    guard let mutation = try bindingRepository.mutation(
      memberID: memberID,
      operation: .addRoutine,
      entityKind: .routine,
      localEntityID: routineLocalID
    ) else {
      return false
    }
    return Self.isBindingDeliveryPending(mutation.state)
  }

  private static func uniqueRoutineIDs(_ ids: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return ids.filter { seen.insert($0).inserted }
  }

  private static func isBindingDeliveryPending(
    _ state: RoutineSyncMutationState
  ) -> Bool {
    switch state {
    // Newly saved groups start waiting for runtime contract admission, then
    // become queued. Both states can gain a server binding during the same
    // bounded first-cue window, so neither should fall through silently.
    case .waitingForServerContract, .queued, .attempting:
      true
    case .needsReconciliation, .blocked:
      false
    }
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
    !cacheUnavailableMemberIDs.contains(identity.memberID)
  }

  private func currentSelectionVersion(
    for identity: AccountSessionIdentity
  ) -> Int64? {
    guard currentVoiceSelection?.identity == identity else { return nil }
    return currentVoiceSelection?.version
  }

  private func restoredVoiceSelection(
    for identity: AccountSessionIdentity?
  ) -> CurrentVoiceSelection? {
    guard let identity,
          let version = voiceSelectionVersionStore.selectionVersion(
            forMemberID: identity.memberID
          ) else {
      return nil
    }
    return CurrentVoiceSelection(identity: identity, version: version)
  }

  private func validateCurrentBinding(
    for plan: PreparedPlan,
    planKey: LocalPlanKey,
    identity: AccountSessionIdentity
  ) -> PreparedPlanBindingValidation {
    do {
      guard let groupBinding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routineGroup,
        localEntityID: planKey.routineGroupLocalID
      ), let routineBinding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routine,
        localEntityID: planKey.routineLocalID
      ) else {
        return .invalid
      }
      guard isValidGroupBinding(
        groupBinding,
        routineGroupLocalID: planKey.routineGroupLocalID,
        identity: identity
      ), groupBinding.remoteID == plan.routineGroupRemoteID,
      isValidRoutineBinding(
        routineBinding,
        routineGroupLocalID: planKey.routineGroupLocalID,
        routineLocalID: planKey.routineLocalID,
        groupBinding: groupBinding,
        identity: identity
      ), routineBinding.remoteID == plan.routineRemoteID else {
        return .invalid
      }
      return .valid
    } catch {
      return .unavailable
    }
  }

  private func isValidGroupBinding(
    _ binding: RoutineServerBinding,
    routineGroupLocalID: UUID,
    identity: AccountSessionIdentity
  ) -> Bool {
    binding.entityKind == .routineGroup
      && binding.localEntityID == routineGroupLocalID
      && binding.remoteID > 0
      && binding.memberID == identity.memberID
      && binding.serverNamespace == serverNamespace
  }

  private func isValidRoutineBinding(
    _ binding: RoutineServerBinding,
    routineGroupLocalID: UUID,
    routineLocalID: UUID,
    groupBinding: RoutineServerBinding,
    identity: AccountSessionIdentity
  ) -> Bool {
    binding.entityKind == .routine
      && binding.localEntityID == routineLocalID
      && binding.remoteID > 0
      && binding.memberID == identity.memberID
      && binding.serverNamespace == serverNamespace
      && binding.parentEntityKind == .routineGroup
      && binding.parentLocalEntityID == routineGroupLocalID
      && binding.memberID == groupBinding.memberID
      && binding.serverNamespace == groupBinding.serverNamespace
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
