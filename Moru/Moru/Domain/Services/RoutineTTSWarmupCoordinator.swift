//
//  RoutineTTSWarmupCoordinator.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineTTSWarming: AnyObject {
  func prepare(routineGroupLocalID: UUID, routineLocalIDs: [UUID])
}

@MainActor
final class RoutineTTSWarmupCoordinator: RoutineTTSWarming, RoutineTTSLocalAudioProviding {
  private struct PreparedPlan {
    let identity: AccountSessionIdentity
    let fingerprint: RoutineTTSLocalFingerprint
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

  private let remoteService: any RoutineTTSRemoteServing
  private let bindingRepository: any RoutineSyncRepository
  private let routineRepository: (any RoutineRepository)?
  private let audioCache: RoutineTTSAudioCache
  private let downloader: any RoutineTTSAudioDownloading
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let serverNamespace: RoutineSyncServerNamespace
  private let resolver: RoutineTTSCuePlanResolver
  private weak var playbackSessionInvalidator:
    (any RoutineTTSPlaybackSessionInvalidating)?

  private var preparedPlans: [LocalPlanKey: PreparedPlan] = [:]
  private var operationTask: Task<Void, Never>?
  private var sessionTransitionTask: Task<Void, Never>?
  private var isSceneActive = false
  private var observedIdentity: AccountSessionIdentity?

  init(
    remoteService: any RoutineTTSRemoteServing,
    bindingRepository: any RoutineSyncRepository,
    routineRepository: (any RoutineRepository)? = nil,
    audioCache: RoutineTTSAudioCache,
    downloader: any RoutineTTSAudioDownloading,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    serverNamespace: RoutineSyncServerNamespace = .production,
    resolver: RoutineTTSCuePlanResolver = RoutineTTSCuePlanResolver()
  ) {
    self.remoteService = remoteService
    self.bindingRepository = bindingRepository
    self.routineRepository = routineRepository
    self.audioCache = audioCache
    self.downloader = downloader
    self.sessionIdentityProvider = sessionIdentityProvider
    self.serverNamespace = serverNamespace
    self.resolver = resolver
    observedIdentity = sessionIdentityProvider.currentAccountSessionIdentity
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
    preparedPlans.removeAll()
    let previousTransition = sessionTransitionTask
    sessionTransitionTask = Task { [audioCache, serverNamespace] in
      _ = await previousTransition?.value
      if let previousIdentity {
        try? await audioCache.purge(
          accountID: String(previousIdentity.memberID),
          namespace: serverNamespace.rawValue
        )
      }
    }
    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      guard let self else { return }
      _ = await transition?.value
      guard sessionIdentityProvider?.currentAccountSessionIdentity == currentIdentity,
            isSceneActive else { return }
      guard let currentIdentity, let routineRepository else { return }
      await prepareActiveRoutinesNow(
        identity: currentIdentity,
        routineRepository: routineRepository
      )
    }
  }

  func prepare(routineGroupLocalID: UUID, routineLocalIDs: [UUID]) {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
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

  func localAudioURLs(for request: RoutineTTSLocalAudioRequest) async -> [URL]? {
    let planKey = LocalPlanKey(
      routineGroupLocalID: request.routineGroupLocalID,
      routineLocalID: request.routineLocalID
    )
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          let plan = preparedPlans[planKey],
          plan.identity == identity,
          plan.fingerprint == RoutineTTSLocalFingerprint(
            title: request.routineTitle,
            type: request.routineType
          ),
          !plan.keys.isEmpty else { return nil }

    var urls: [URL] = []
    urls.reserveCapacity(plan.keys.count)
    // A stale byte is usable only while its fresh, identity-gated in-memory
    // manifest survives. Session changes remove the manifest before purge.
    for key in plan.keys {
      guard let url = await audioCache.cachedFileURL(for: key, allowStale: true) else {
        preparedPlans[planKey] = nil
        return nil
      }
      urls.append(url)
    }

    guard sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
      return nil
    }
    return urls
  }

  private func prepareActiveRoutines() {
    guard let identity = sessionIdentityProvider?.currentAccountSessionIdentity,
          let routineRepository else { return }
    let transition = sessionTransitionTask
    replaceOperation { [weak self] in
      _ = await transition?.value
      guard self?.sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
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
    do {
      routines = try routineRepository.fetchActiveRoutines().filter(\.isActive)
    } catch {
      return
    }

    for routine in routines {
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
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
          sessionIdentityProvider?.currentAccountSessionIdentity == identity else { return }

    let initialLocalSteps: [UUID: RoutineStep]
    do {
      guard let routineRepository,
            let routine = try routineRepository.routine(id: routineGroupLocalID) else {
        return
      }
      initialLocalSteps = Dictionary(
        uniqueKeysWithValues: routine.steps
          .filter { routineLocalIDs.contains($0.id) }
          .map { ($0.id, $0) }
      )
    } catch {
      return
    }

    let groupBinding: RoutineServerBinding
    do {
      guard let binding = try bindingRepository.binding(
        memberID: identity.memberID,
        entityKind: .routineGroup,
        localEntityID: routineGroupLocalID
      ), binding.serverNamespace == serverNamespace else { return }
      groupBinding = binding
    } catch {
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
          sessionIdentityProvider?.currentAccountSessionIdentity == identity else { return }

    for routineLocalID in routineLocalIDs {
      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
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
        preparedPlans[localKey] = nil
        continue
      }

      guard case .playable(let assets) = resolver.resolve(
        routineGroupLocalID: routineGroupLocalID,
        routineLocalID: routineLocalID,
        groupBinding: groupBinding,
        routineBinding: routineBinding,
        response: response
      ), let remoteRoutine = response.first(where: {
        $0.routineID == routineBinding?.remoteID
      }), Self.matches(remoteRoutine: remoteRoutine, localStep: localStep) else {
        preparedPlans[localKey] = nil
        continue
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

      do {
        for (key, asset) in zip(keys, assets) {
          guard !Task.isCancelled,
                sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
            return
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
      } catch {
        preparedPlans[localKey] = nil
        guard !Task.isCancelled,
              sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
          return
        }
        continue
      }

      guard !Task.isCancelled,
            sessionIdentityProvider?.currentAccountSessionIdentity == identity else {
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
        preparedPlans[localKey] = nil
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
        keys: keys
      )
    }
  }

  private func hasCurrentIdentity(_ identity: AccountSessionIdentity) -> Bool {
    sessionIdentityProvider?.currentAccountSessionIdentity == identity
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
