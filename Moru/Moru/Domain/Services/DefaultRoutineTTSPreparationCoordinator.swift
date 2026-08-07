//
//  DefaultRoutineTTSPreparationCoordinator.swift
//  Moru
//

import Foundation

@MainActor
final class DefaultRoutineTTSPreparationCoordinator:
  RoutineTTSPreparationScheduling {
  typealias Sleeper =
    @MainActor @Sendable (Duration) async throws -> Void

  private struct OperationContext {
    let localRoutineID: UUID
    let memberID: Int64
    let plan: RoutineTTSProvisioningPlan
    let generationID: UUID
  }

  private enum StartMode {
    case create(oldRoutineGroupID: Int64?)
    case resume(RoutineTTSLink)
  }

  private struct ResolvedAsset {
    let asset: RoutineTTSAsset
    let audioURL: URL
  }

  private enum ManifestOutcome {
    case retry
    case completed([ResolvedAsset])
  }

  private enum PipelineError: Error {
    case invalidCreation
    case invalidManifest
    case generationFailed
    case unknownStatus
    case timeout
    case fetchFailed
    case downloadFailed

    var failureCode: String {
      switch self {
      case .invalidCreation:
        "invalid-creation"
      case .invalidManifest:
        "invalid-manifest"
      case .generationFailed:
        "generation-failed"
      case .unknownStatus:
        "unknown-status"
      case .timeout:
        "polling-timeout"
      case .fetchFailed:
        "manifest-fetch-failed"
      case .downloadFailed:
        "audio-download-failed"
      }
    }
  }

  private let routineRepository: any RoutineRepository
  private let linkRepository: any RoutineTTSLinkRepository
  private let remoteService: any AccountRoutineTTSRemoteServing
  private weak var signedInMemberProvider:
    (any SignedInMemberProviding)?
  private let audioDownloader: any RoutineTTSAudioDownloading
  private let audioFileStore: RoutineTTSAudioFileStore
  private let maximumPollingRetryCount: Int
  private let pollingInterval: Duration
  private let sleeper: Sleeper

  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var generationIDs: [UUID: UUID] = [:]

  init(
    routineRepository: any RoutineRepository,
    linkRepository: any RoutineTTSLinkRepository,
    remoteService: any AccountRoutineTTSRemoteServing,
    signedInMemberProvider: (any SignedInMemberProviding)?,
    audioDownloader: any RoutineTTSAudioDownloading,
    audioFileStore: RoutineTTSAudioFileStore,
    maximumPollingRetryCount: Int = 15,
    pollingInterval: Duration = .seconds(2),
    sleeper: @escaping Sleeper = { duration in
      try await Task.sleep(for: duration)
    }
  ) {
    self.routineRepository = routineRepository
    self.linkRepository = linkRepository
    self.remoteService = remoteService
    self.signedInMemberProvider = signedInMemberProvider
    self.audioDownloader = audioDownloader
    self.audioFileStore = audioFileStore
    self.maximumPollingRetryCount = max(
      0,
      maximumPollingRetryCount
    )
    self.pollingInterval = pollingInterval
    self.sleeper = sleeper
  }

  func routineDidSave(_ routine: Routine) {
    guard let memberID = signedInMemberProvider?.signedInMemberID,
          memberID > 0 else {
      cancelAndInvalidate(localRoutineID: routine.id)
      return
    }

    guard let callbackPlan = try? RoutineTTSProvisioningRequestFactory
      .makePlan(for: routine) else {
      cancelAndInvalidate(localRoutineID: routine.id)
      return
    }

    guard currentFingerprint(localRoutineID: routine.id)
      == callbackPlan.contentFingerprint else {
      return
    }

    let generationID = beginGeneration(
      localRoutineID: routine.id
    )
    let existingLink = try? linkRepository.link(
      localRoutineID: routine.id,
      memberID: memberID
    )

    if let existingLink,
       existingLink.contentFingerprint
        == callbackPlan.contentFingerprint {
      switch existingLink.status {
      case .ready:
        guard !existingLink.assets.isEmpty,
              existingLink.assets.allSatisfy({ asset in
                guard let path = asset.cachedRelativePath else {
                  return false
                }
                return audioFileStore.cachedAudioURL(
                  relativePath: path
                ) != nil
              }) else {
          try? audioFileStore.removeAssets(
            localRoutineID: routine.id
          )
          var resumableLink = existingLink
          resumableLink.status = .generating
          resumableLink.assets = resumableLink.assets.map { asset in
            var uncachedAsset = asset
            uncachedAsset.cachedRelativePath = nil
            return uncachedAsset
          }
          resumableLink.updatedAt = Date()

          do {
            try linkRepository.saveLink(resumableLink)
            start(
              OperationContext(
                localRoutineID: routine.id,
                memberID: memberID,
                plan: callbackPlan,
                generationID: generationID
              ),
              mode: .resume(resumableLink)
            )
          } catch {
            invalidateLocal(localRoutineID: routine.id)
          }
          return
        }
        return
      case .generating:
        start(
          OperationContext(
            localRoutineID: routine.id,
            memberID: memberID,
            plan: callbackPlan,
            generationID: generationID
          ),
          mode: .resume(existingLink)
        )
        return
      case .creating, .failed, .stale:
        break
      }
    }

    let oldRoutineGroupID = existingLink?.serverRoutineGroupID
    invalidateLocal(localRoutineID: routine.id)
    start(
      OperationContext(
        localRoutineID: routine.id,
        memberID: memberID,
        plan: callbackPlan,
        generationID: generationID
      ),
      mode: .create(oldRoutineGroupID: oldRoutineGroupID)
    )
  }

  func routineDidDelete(localRoutineID: UUID) {
    let memberID = signedInMemberProvider?.signedInMemberID
    let oldRoutineGroupID = memberID.flatMap { memberID in
      try? linkRepository.link(
        localRoutineID: localRoutineID,
        memberID: memberID
      )?.serverRoutineGroupID
    } ?? nil
    let generationID = beginGeneration(
      localRoutineID: localRoutineID
    )

    invalidateLocal(localRoutineID: localRoutineID)

    guard let memberID,
          memberID > 0,
          let oldRoutineGroupID else {
      return
    }

    let task = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      _ = try? await self.remoteService.deleteRoutineGroup(
        routineGroupID: oldRoutineGroupID,
        memberID: memberID
      )
      self.finish(
        localRoutineID: localRoutineID,
        generationID: generationID
      )
    }
    tasks[localRoutineID] = task
  }

  func cancelAllPreparations() {
    tasks.values.forEach { $0.cancel() }
    tasks.removeAll()
    generationIDs.removeAll()
  }

  func waitForPreparation(localRoutineID: UUID) async {
    while let task = tasks[localRoutineID] {
      await task.value
    }
  }

  private func start(
    _ context: OperationContext,
    mode: StartMode
  ) {
    let task = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      await self.execute(context, mode: mode)
      if self.generationIDs[context.localRoutineID]
          == context.generationID,
         !self.isCurrent(context) {
        self.invalidateLocal(
          localRoutineID: context.localRoutineID
        )
      }
      self.finish(
        localRoutineID: context.localRoutineID,
        generationID: context.generationID
      )
    }
    tasks[context.localRoutineID] = task
  }

  private func execute(
    _ context: OperationContext,
    mode: StartMode
  ) async {
    switch mode {
    case .create(let oldRoutineGroupID):
      await createAndPrepare(
        context,
        oldRoutineGroupID: oldRoutineGroupID
      )
    case .resume(let link):
      await pollAndCache(context, startingLink: link)
    }
  }

  private func createAndPrepare(
    _ context: OperationContext,
    oldRoutineGroupID: Int64?
  ) async {
    if let oldRoutineGroupID {
      _ = try? await remoteService.deleteRoutineGroup(
        routineGroupID: oldRoutineGroupID,
        memberID: context.memberID
      )
      guard isCurrent(context) else {
        return
      }
    }

    guard isCurrent(context) else {
      return
    }

    var stateLink = RoutineTTSLink(
      localRoutineID: context.localRoutineID,
      memberID: context.memberID,
      contentFingerprint: context.plan.contentFingerprint,
      status: .creating
    )

    do {
      try linkRepository.saveLink(stateLink)
    } catch {
      markFailed(
        context,
        startingLink: stateLink,
        failureCode: "link-save-failed"
      )
      return
    }

    let creation: ServerRoutineGroupCreationResult
    do {
      creation = try await remoteService.createRoutineGroup(
        context.plan.request,
        memberID: context.memberID
      )
    } catch is CancellationError {
      return
    } catch {
      guard isCurrent(context) else {
        if generationIDs[context.localRoutineID]
          == context.generationID {
          invalidateLocal(localRoutineID: context.localRoutineID)
        }
        return
      }
      markFailed(
        context,
        startingLink: stateLink,
        failureCode: "creation-request-failed"
      )
      return
    }

    guard isCurrent(context) else {
      if creation.routineGroupID > 0 {
        _ = try? await remoteService.deleteRoutineGroup(
          routineGroupID: creation.routineGroupID,
          memberID: context.memberID
        )
      }
      if generationIDs[context.localRoutineID]
        == context.generationID {
        invalidateLocal(localRoutineID: context.localRoutineID)
      }
      return
    }

    if creation.routineGroupID > 0 {
      stateLink.serverRoutineGroupID = creation.routineGroupID
    }

    do {
      stateLink = try makeGeneratingLink(
        context: context,
        creation: creation,
        createdAt: stateLink.createdAt
      )
      try linkRepository.saveLink(stateLink)
    } catch {
      markFailed(
        context,
        startingLink: stateLink,
        failureCode: PipelineError.invalidCreation.failureCode
      )
      return
    }

    await pollAndCache(context, startingLink: stateLink)
  }

  private func pollAndCache(
    _ context: OperationContext,
    startingLink: RoutineTTSLink
  ) async {
    var remainingRetries = maximumPollingRetryCount
    var stateLink = startingLink

    while isCurrent(context) {
      do {
        let manifest = try await remoteService.fetchRoutineTTS(
          routineGroupID: try requiredRoutineGroupID(stateLink),
          memberID: context.memberID
        )
        guard isCurrent(context) else {
          return
        }

        switch try inspect(
          manifest,
          expectedLink: stateLink
        ) {
        case .retry:
          guard remainingRetries > 0 else {
            throw PipelineError.timeout
          }
          remainingRetries -= 1
          try await sleeper(pollingInterval)
          guard isCurrent(context) else {
            return
          }
        case .completed(let resolvedAssets):
          stateLink = try await cache(
            resolvedAssets,
            context: context,
            startingLink: stateLink
          )
          guard isCurrent(context) else {
            return
          }
          stateLink.status = .ready
          stateLink.lastFailureCode = nil
          stateLink.updatedAt = Date()
          try linkRepository.saveLink(stateLink)
          return
        }
      } catch is CancellationError {
        return
      } catch let error as PipelineError {
        markFailed(
          context,
          startingLink: stateLink,
          failureCode: error.failureCode
        )
        return
      } catch {
        guard isCurrent(context) else {
          return
        }
        guard isRetryableFetchError(error),
              remainingRetries > 0 else {
          markFailed(
            context,
            startingLink: stateLink,
            failureCode: PipelineError.fetchFailed.failureCode
          )
          return
        }

        remainingRetries -= 1
        do {
          try await sleeper(pollingInterval)
        } catch {
          return
        }
        guard isCurrent(context) else {
          return
        }
      }
    }
  }

  private func makeGeneratingLink(
    context: OperationContext,
    creation: ServerRoutineGroupCreationResult,
    createdAt: Date
  ) throws -> RoutineTTSLink {
    guard creation.localRoutineID == context.localRoutineID,
          creation.routineGroupID > 0,
          creation.routines.count
            == context.plan.request.routines.count else {
      throw PipelineError.invalidCreation
    }

    let expectedByLocalStepID = Dictionary(
      uniqueKeysWithValues: context.plan.request.routines.map {
        ($0.localStepID, $0)
      }
    )
    var seenLocalStepIDs = Set<UUID>()
    var seenRoutineIDs = Set<Int64>()
    var seenStepIDs = Set<Int64>()
    var assets: [RoutineTTSAsset] = []

    for createdRoutine in creation.routines {
      guard let expected = expectedByLocalStepID[
        createdRoutine.localStepID
      ],
      seenLocalStepIDs.insert(createdRoutine.localStepID).inserted,
      createdRoutine.routineID > 0,
      seenRoutineIDs.insert(createdRoutine.routineID).inserted,
      createdRoutine.title == expected.title,
      createdRoutine.type == expected.type,
      createdRoutine.durationSeconds == expected.durationSeconds,
      !createdRoutine.steps.isEmpty else {
        throw PipelineError.invalidCreation
      }

      var seenOrderIndices = Set<Int>()
      for step in createdRoutine.steps {
        guard step.stepID > 0,
              seenStepIDs.insert(step.stepID).inserted,
              step.orderIndex >= 0,
              seenOrderIndices.insert(step.orderIndex).inserted else {
          throw PipelineError.invalidCreation
        }

        assets.append(
          RoutineTTSAsset(
            localStepID: createdRoutine.localStepID,
            serverRoutineID: createdRoutine.routineID,
            serverStepID: step.stepID,
            orderIndex: step.orderIndex
          )
        )
      }
    }

    guard seenLocalStepIDs == Set(expectedByLocalStepID.keys),
          !assets.isEmpty else {
      throw PipelineError.invalidCreation
    }

    return RoutineTTSLink(
      localRoutineID: context.localRoutineID,
      memberID: context.memberID,
      serverRoutineGroupID: creation.routineGroupID,
      contentFingerprint: context.plan.contentFingerprint,
      status: .generating,
      assets: assets,
      createdAt: createdAt,
      updatedAt: Date()
    )
  }

  private func requiredRoutineGroupID(
    _ link: RoutineTTSLink
  ) throws -> Int64 {
    guard let routineGroupID = link.serverRoutineGroupID,
          routineGroupID > 0 else {
      throw PipelineError.invalidManifest
    }
    return routineGroupID
  }

  private func inspect(
    _ manifest: ServerRoutineTTSManifest,
    expectedLink: RoutineTTSLink
  ) throws -> ManifestOutcome {
    guard manifest.routineGroupID
      == expectedLink.serverRoutineGroupID else {
      throw PipelineError.invalidManifest
    }

    let expectedByRoutineID = Dictionary(
      grouping: expectedLink.assets,
      by: \.serverRoutineID
    )
    var seenRoutineIDs = Set<Int64>()
    var seenStepIDs = Set<Int64>()
    var hasPending = false
    var resolvedByStepID: [Int64: ResolvedAsset] = [:]

    for routine in manifest.routines {
      guard let expectedAssets = expectedByRoutineID[
        routine.routineID
      ],
      seenRoutineIDs.insert(routine.routineID).inserted else {
        throw PipelineError.invalidManifest
      }

      let expectedByStepID = Dictionary(
        uniqueKeysWithValues: expectedAssets.map {
          ($0.serverStepID, $0)
        }
      )
      for step in routine.steps {
        guard let expectedAsset = expectedByStepID[step.stepID],
              seenStepIDs.insert(step.stepID).inserted else {
          throw PipelineError.invalidManifest
        }

        switch step.status {
        case .pending:
          hasPending = true
        case .completed:
          guard let audioURL = step.audioURL else {
            throw PipelineError.invalidManifest
          }
          resolvedByStepID[step.stepID] = ResolvedAsset(
            asset: expectedAsset,
            audioURL: audioURL
          )
        case .failed:
          throw PipelineError.generationFailed
        case .unknown:
          throw PipelineError.unknownStatus
        }
      }
    }

    let expectedRoutineIDs = Set(expectedByRoutineID.keys)
    let expectedStepIDs = Set(
      expectedLink.assets.map(\.serverStepID)
    )
    guard seenRoutineIDs == expectedRoutineIDs,
          seenStepIDs == expectedStepIDs,
          !hasPending else {
      return .retry
    }

    let resolvedAssets = try expectedLink.assets.map { asset in
      guard let resolved = resolvedByStepID[asset.serverStepID] else {
        throw PipelineError.invalidManifest
      }
      return resolved
    }
    return .completed(resolvedAssets)
  }

  private func cache(
    _ resolvedAssets: [ResolvedAsset],
    context: OperationContext,
    startingLink: RoutineTTSLink
  ) async throws -> RoutineTTSLink {
    var pathsByStepID: [Int64: String] = [:]

    do {
      for resolved in resolvedAssets {
        let data = try await audioDownloader.downloadAudio(
          from: resolved.audioURL
        )
        guard isCurrent(context) else {
          throw CancellationError()
        }
        pathsByStepID[resolved.asset.serverStepID] =
          try audioFileStore.store(
            data,
            localRoutineID: context.localRoutineID,
            localStepID: resolved.asset.localStepID,
            serverStepID: resolved.asset.serverStepID
          )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PipelineError.downloadFailed
    }

    var link = startingLink
    link.assets = try link.assets.map { asset in
      guard let path = pathsByStepID[asset.serverStepID] else {
        throw PipelineError.downloadFailed
      }
      var cachedAsset = asset
      cachedAsset.cachedRelativePath = path
      return cachedAsset
    }
    return link
  }

  private func markFailed(
    _ context: OperationContext,
    startingLink: RoutineTTSLink,
    failureCode: String
  ) {
    guard isCurrent(context) else {
      return
    }

    try? audioFileStore.removeAssets(
      localRoutineID: context.localRoutineID
    )
    var failedLink = startingLink
    failedLink.memberID = context.memberID
    failedLink.contentFingerprint =
      context.plan.contentFingerprint
    failedLink.status = .failed
    failedLink.assets = failedLink.assets.map { asset in
      var uncachedAsset = asset
      uncachedAsset.cachedRelativePath = nil
      return uncachedAsset
    }
    failedLink.lastFailureCode = failureCode
    failedLink.updatedAt = Date()
    try? linkRepository.saveLink(failedLink)
  }

  private func currentFingerprint(
    localRoutineID: UUID
  ) -> String? {
    guard let routine = try? routineRepository.routine(
      id: localRoutineID
    ) else {
      return nil
    }
    return try? RoutineTTSProvisioningRequestFactory
      .makePlan(for: routine)
      .contentFingerprint
  }

  private func isCurrent(_ context: OperationContext) -> Bool {
    guard !Task.isCancelled,
          generationIDs[context.localRoutineID]
            == context.generationID,
          signedInMemberProvider?.signedInMemberID
            == context.memberID,
          currentFingerprint(localRoutineID: context.localRoutineID)
            == context.plan.contentFingerprint else {
      return false
    }
    return true
  }

  private func isRetryableFetchError(_ error: Error) -> Bool {
    guard let apiError = error as? APIError else {
      return false
    }
    return apiError.isRetryable
  }

  @discardableResult
  private func beginGeneration(
    localRoutineID: UUID
  ) -> UUID {
    tasks[localRoutineID]?.cancel()
    tasks[localRoutineID] = nil
    let generationID = UUID()
    generationIDs[localRoutineID] = generationID
    return generationID
  }

  private func cancelAndInvalidate(localRoutineID: UUID) {
    _ = beginGeneration(localRoutineID: localRoutineID)
    invalidateLocal(localRoutineID: localRoutineID)
  }

  private func invalidateLocal(localRoutineID: UUID) {
    try? audioFileStore.removeAssets(
      localRoutineID: localRoutineID
    )
    try? linkRepository.deleteLink(
      localRoutineID: localRoutineID
    )
  }

  private func finish(
    localRoutineID: UUID,
    generationID: UUID
  ) {
    guard generationIDs[localRoutineID] == generationID else {
      return
    }
    tasks[localRoutineID] = nil
  }
}
