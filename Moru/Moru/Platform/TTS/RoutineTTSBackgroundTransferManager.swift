//
//  RoutineTTSBackgroundTransferManager.swift
//  Moru
//


import AVFAudio
import BackgroundTasks
import Foundation
import OSLog
import UIKit

@MainActor
protocol RoutineTTSBackgroundTransferManaging: AnyObject {
  func resumePendingTransfers(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) async
  func enqueue(jobID: UUID) async
  func discardAllTransfers() async
}

/// Deterministic seam for persisted-task reconciliation tests. Production
/// leaves this nil and uses the single fixed URLSession below.
@MainActor
protocol RoutineTTSBackgroundTaskRegistry: AnyObject {
  func taskDescriptions() async -> [String]
  func start(request: URLRequest, taskDescription: String)
  func cancel(taskDescription: String)
  func cancelAll()
}

/// Owns the process-wide background URLSession. `taskDescription` contains
/// only opaque UUIDs, allowing iOS tasks to be reconciled with the durable
/// queue after process recreation without putting account data in system logs.
final class RoutineTTSBackgroundTransferManager:
  NSObject,
  RoutineTTSBackgroundTransferManaging,
  URLSessionDownloadDelegate,
  @unchecked Sendable {
  static let refreshIdentifier = "com.teammoru.Moru.routine-tts-refresh"
  static let sessionIdentifier = "com.teammoru.Moru.routine-tts-background-v1"

  nonisolated private struct TaskIdentity: Hashable, Sendable {
    let jobID: UUID
    let assetID: UUID

    var description: String {
      "v1:\(jobID.uuidString):\(assetID.uuidString)"
    }

    init(jobID: UUID, assetID: UUID) {
      self.jobID = jobID
      self.assetID = assetID
    }

    init?(description: String?) {
      guard let description else { return nil }
      let parts = description.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 3,
            parts[0] == "v1",
            let jobID = UUID(uuidString: String(parts[1])),
            let assetID = UUID(uuidString: String(parts[2])) else {
        return nil
      }
      self.jobID = jobID
      self.assetID = assetID
    }
  }

  private let jobStore: any RoutineTTSPrefetchJobStoring
  private let audioCache: RoutineTTSAudioCache
  nonisolated private let policy: RoutineTTSAudioDownloadPolicy
  private let decodeProbe: RoutineTTSAudioDecodeProbe
  nonisolated(unsafe) private let fileManager: FileManager
  nonisolated private let stagingRoot: URL
  private let statusCenter: RoutineTTSPreparationStatusCenter
  private let taskRegistry: (any RoutineTTSBackgroundTaskRegistry)?
  private let now: @Sendable () -> Date
  private let currentContext:
    @MainActor @Sendable () -> (memberID: Int64, selectionVersion: Int64?, ttsID: Int64?)?
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineTTSBackgroundTransfer"
  )
  private let delegateQueue: OperationQueue
  nonisolated private let completionLock = NSLock()
  nonisolated(unsafe) private var pendingDelegateCommits = 0
  nonisolated(unsafe) private var waitsToFinishBackgroundEvents = false
  @MainActor private var pendingResumeContext:
    (memberID: Int64, selectionVersion: Int64?, ttsID: Int64?)?
  @MainActor private var pendingEnqueueJobIDs = Set<UUID>()
  @MainActor private var isReconciling = false
  @MainActor private var localTaskReservations = Set<TaskIdentity>()
  @MainActor private var managerGeneration: UInt = 0
  @MainActor private var activeContext:
    (memberID: Int64, selectionVersion: Int64?, ttsID: Int64?)?
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.sessionIdentifier
    )
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.allowsCellularAccess = true
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpAdditionalHeaders = [:]
    return URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: delegateQueue
    )
  }()

  init(
    jobStore: any RoutineTTSPrefetchJobStoring,
    audioCache: RoutineTTSAudioCache,
    statusCenter: RoutineTTSPreparationStatusCenter,
    currentContext: @escaping @MainActor @Sendable () -> (
      memberID: Int64,
      selectionVersion: Int64?,
      ttsID: Int64?
    )? = { nil },
    taskRegistry: (any RoutineTTSBackgroundTaskRegistry)? = nil,
    now: @escaping @Sendable () -> Date = Date.init,
    policy: RoutineTTSAudioDownloadPolicy = RoutineTTSAudioDownloadPolicy(),
    decodeProbe: RoutineTTSAudioDecodeProbe = .system,
    fileManager: FileManager = .default,
    stagingRoot: URL? = nil
  ) throws {
    self.jobStore = jobStore
    self.audioCache = audioCache
    self.statusCenter = statusCenter
    self.currentContext = currentContext
    self.taskRegistry = taskRegistry
    self.now = now
    self.policy = policy
    self.decodeProbe = decodeProbe
    self.fileManager = fileManager
    self.stagingRoot = try stagingRoot ?? Self.defaultStagingRoot(
      fileManager: fileManager
    )
    delegateQueue = OperationQueue()
    delegateQueue.name = "com.teammoru.Moru.routine-tts-background-delegate"
    delegateQueue.maxConcurrentOperationCount = 1
    super.init()
    try fileManager.createDirectory(
      at: self.stagingRoot,
      withIntermediateDirectories: true
    )
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: self.stagingRoot.path
    )
  }

  @MainActor
  func activateAtLaunch() {
    if taskRegistry == nil {
      _ = session
    }
  }

  @MainActor
  func resumePendingTransfers(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) async {
    if activeContext?.memberID != memberID
        || activeContext?.selectionVersion != selectionVersion
        || activeContext?.ttsID != selectedTTSID {
      managerGeneration &+= 1
      activeContext = (memberID, selectionVersion, selectedTTSID)
    }
    pendingResumeContext = (memberID, selectionVersion, selectedTTSID)
    await drainPendingOperations()
  }

  @MainActor
  private func performResumePendingTransfers(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) async {
    activateAtLaunch()
    let capturedGeneration = managerGeneration
    guard isActiveContext(
      memberID: memberID,
      selectionVersion: selectionVersion,
      selectedTTSID: selectedTTSID
    ) else { return }
    do {
      let removedCount = try await jobStore.removeStaleJobs(
        keepingMemberID: memberID,
        selectionVersion: selectionVersion,
        selectedTTSID: selectedTTSID
      )
      guard capturedGeneration == managerGeneration,
            isActiveContext(
              memberID: memberID,
              selectionVersion: selectionVersion,
              selectedTTSID: selectedTTSID
            ) else { return }
      if removedCount > 0 {
        logger.notice("TTS transfer state: staleJobsDiscarded")
      }

      let jobs = try await jobStore.allJobs()
      let currentJobs = jobs.filter {
        $0.memberID == memberID
          && $0.selectionVersion == selectionVersion
          && $0.selectedTTSID == selectedTTSID
      }
      let retainedTaskIdentities = Set(currentJobs.flatMap { job in
        job.assets.map { TaskIdentity(jobID: job.id, assetID: $0.id) }
      })
      let taskDescriptions = await backgroundTaskDescriptions()
      var existing = Set<TaskIdentity>()
      for description in taskDescriptions {
        guard let identity = TaskIdentity(description: description),
              retainedTaskIdentities.contains(identity) else {
          await cancelBackgroundTask(description: description)
          continue
        }
        existing.insert(identity)
        localTaskReservations.insert(identity)
      }

      for job in currentJobs where job.state != .pendingRemote {
        await reconcile(
          job: job,
          existingTasks: &existing,
          generation: capturedGeneration
        )
      }
      await publishAggregateStatus(
        memberID: memberID,
        selectionVersion: selectionVersion,
        selectedTTSID: selectedTTSID
      )
    } catch {
      logger.error("TTS transfer state: reconciliationFailed")
      for component in [
        RoutineTTSPreparationComponent.routineIntro,
        RoutineTTSPreparationComponent.commonCues,
      ] {
        statusCenter.report(
          .retryScheduled,
          component: component,
          memberID: memberID,
          selectionVersion: selectionVersion,
          selectedTTSID: selectedTTSID
        )
      }
    }
  }

  @MainActor
  func enqueue(jobID: UUID) async {
    pendingEnqueueJobIDs.insert(jobID)
    await drainPendingOperations()
  }

  @MainActor
  private func drainPendingOperations() async {
    guard !isReconciling else { return }
    isReconciling = true
    defer { isReconciling = false }
    while pendingResumeContext != nil || !pendingEnqueueJobIDs.isEmpty {
      if let context = pendingResumeContext {
        pendingResumeContext = nil
        await performResumePendingTransfers(
          memberID: context.memberID,
          selectionVersion: context.selectionVersion,
          selectedTTSID: context.ttsID
        )
        continue
      }
      guard let jobID = pendingEnqueueJobIDs.first else { continue }
      pendingEnqueueJobIDs.remove(jobID)
      await performEnqueue(jobID: jobID)
    }
  }

  @MainActor
  private func performEnqueue(jobID: UUID) async {
    let capturedGeneration = managerGeneration
    do {
      guard let job = try await jobStore.allJobs().first(where: { $0.id == jobID }) else {
        return
      }
      guard capturedGeneration == managerGeneration,
            isCurrent(job: job),
            isActiveContext(
              memberID: job.memberID,
              selectionVersion: job.selectionVersion,
              selectedTTSID: job.selectedTTSID
            ) else {
        return
      }
      let retained = Set(job.assets.map {
        TaskIdentity(jobID: job.id, assetID: $0.id)
      })
      let taskDescriptions = await backgroundTaskDescriptions()
      var existing = Set<TaskIdentity>()
      for description in taskDescriptions {
        guard let identity = TaskIdentity(description: description) else {
          continue
        }
        if identity.jobID == job.id, !retained.contains(identity) {
          await cancelBackgroundTask(description: description)
          localTaskReservations.remove(identity)
          continue
        }
        existing.insert(identity)
      }
      existing.formUnion(localTaskReservations)
      await reconcile(
        job: job,
        existingTasks: &existing,
        generation: capturedGeneration
      )
      await publishAggregateStatus(
        memberID: job.memberID,
        selectionVersion: job.selectionVersion,
        selectedTTSID: job.selectedTTSID
      )
    } catch {
      logger.error("TTS transfer state: enqueueFailed")
    }
  }

  @MainActor
  func discardAllTransfers() async {
    managerGeneration &+= 1
    activeContext = nil
    pendingResumeContext = nil
    pendingEnqueueJobIDs.removeAll()
    await cancelAllBackgroundTasks()
    localTaskReservations.removeAll()
    try? await jobStore.removeAllJobs()
    statusCenter.reset()
    logger.notice("TTS transfer state: allJobsDiscarded")
  }

  @MainActor
  private func reconcile(
    job: RoutineTTSPrefetchJob,
    existingTasks: inout Set<TaskIdentity>,
    generation capturedGeneration: UInt
  ) async {
    var updatedJob = job
    if job.state == .retryScheduled,
       let nextRemoteAttemptAt = job.nextRemoteAttemptAt,
       nextRemoteAttemptAt > now() {
      for asset in job.assets {
        let identity = TaskIdentity(jobID: job.id, assetID: asset.id)
        guard existingTasks.contains(identity) else { continue }
        await cancelBackgroundTask(description: identity.description)
        existingTasks.remove(identity)
        localTaskReservations.remove(identity)
      }
      return
    }
    var needsFreshRemoteStatus = job.state == .retryScheduled
    for asset in updatedJob.assets {
      let identity = TaskIdentity(jobID: job.id, assetID: asset.id)
      let hasCache = await audioCache.cachedFileURL(
        for: asset.cacheKey,
        allowStale: true
      ) != nil
      if asset.state == .completed, !hasCache {
        needsFreshRemoteStatus = true
      }
      if asset.state == .downloading, !existingTasks.contains(identity) {
        needsFreshRemoteStatus = true
      }
    }
    if needsFreshRemoteStatus {
      let descriptions = await backgroundTaskDescriptions()
      for description in descriptions {
        guard let identity = TaskIdentity(description: description),
              identity.jobID == job.id else { continue }
        await cancelBackgroundTask(description: description)
        localTaskReservations.remove(identity)
        existingTasks.remove(identity)
      }
      updatedJob.assets = updatedJob.assets.map {
        RoutineTTSPrefetchAsset(
          id: $0.id,
          cacheKey: $0.cacheKey,
          state: .queued
        )
      }
      updatedJob.state = .pendingRemote
      updatedJob.nextRemoteAttemptAt = now()
      updatedJob.updatedAt = now()
      try? await jobStore.replace(updatedJob)
      return
    }
    var tasksToStart: [(TaskIdentity, URLRequest)] = []
    for index in updatedJob.assets.indices {
      let asset = updatedJob.assets[index]
      let identity = TaskIdentity(jobID: job.id, assetID: asset.id)
      if await audioCache.cachedFileURL(for: asset.cacheKey, allowStale: true) != nil {
        if existingTasks.contains(identity) {
          await cancelBackgroundTask(description: identity.description)
          existingTasks.remove(identity)
          localTaskReservations.remove(identity)
        }
        updatedJob.assets[index].state = .completed
        continue
      }

      if existingTasks.contains(identity)
          || localTaskReservations.contains(identity) {
        updatedJob.assets[index].state = .downloading
        continue
      }
      guard Self.isAllowedDownloadURL(asset.cacheKey.remoteURL, policy: policy) else {
        updatedJob.assets[index].state = .queued
        updatedJob.state = .retryScheduled
        continue
      }

      var request = URLRequest(
        url: asset.cacheKey.remoteURL,
        cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
      )
      request.httpShouldHandleCookies = false
      request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
      request.setValue(nil, forHTTPHeaderField: "Authorization")
      request.setValue(nil, forHTTPHeaderField: "Cookie")
      existingTasks.insert(identity)
      localTaskReservations.insert(identity)
      updatedJob.assets[index].state = .downloading
      tasksToStart.append((identity, request))
    }

    if updatedJob.state != .pendingRemote
        && updatedJob.state != .retryScheduled {
      updatedJob.state = Self.jobState(for: updatedJob.assets)
    }
    updatedJob.updatedAt = now()
    do {
      try await jobStore.replace(updatedJob)
    } catch {
      for (identity, _) in tasksToStart {
        localTaskReservations.remove(identity)
        existingTasks.remove(identity)
      }
      return
    }
    guard capturedGeneration == managerGeneration,
          isCurrent(job: updatedJob),
          (try? await jobStore.allJobs().contains(where: {
            $0.id == updatedJob.id
          })) == true else {
      for (identity, _) in tasksToStart {
        localTaskReservations.remove(identity)
        existingTasks.remove(identity)
      }
      return
    }
    guard capturedGeneration == managerGeneration,
          isCurrent(job: updatedJob) else {
      for (identity, _) in tasksToStart {
        localTaskReservations.remove(identity)
        existingTasks.remove(identity)
      }
      return
    }
    for (identity, request) in tasksToStart {
      startBackgroundTask(request: request, identity: identity)
      logger.notice("TTS transfer state: downloadStarted")
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let identity = TaskIdentity(description: downloadTask.taskDescription) else {
      return
    }
    let response = downloadTask.response as? HTTPURLResponse
    completionLock.withLock {
      pendingDelegateCommits += 1
    }
    let stagedURL = stagingRoot
      .appendingPathComponent(UUID().uuidString, isDirectory: false)
      .appendingPathExtension("mp3")
    do {
      try fileManager.moveItem(at: location, to: stagedURL)
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: stagedURL.path
      )
    } catch {
      Task { @MainActor [weak self] in
        await self?.markTransferForRetry(identity)
        self?.finishDelegateCommit()
      }
      return
    }

    Task { @MainActor [weak self] in
      await self?.commitTransfer(
        identity,
        response: response,
        stagedURL: stagedURL
      )
      self?.finishDelegateCommit()
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard error != nil,
          let identity = TaskIdentity(description: task.taskDescription) else {
      return
    }
    completionLock.withLock {
      pendingDelegateCommits += 1
    }
    Task { @MainActor [weak self] in
      await self?.markTransferForRetry(identity)
      self?.finishDelegateCommit()
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let source = response.url,
          let destination = request.url,
          Self.isAllowedDownloadURL(destination, policy: policy),
          policy.redirectValidator(source, destination) else {
      completionHandler(nil)
      return
    }
    var sanitized = request
    sanitized.httpShouldHandleCookies = false
    sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
    sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
    completionHandler(sanitized)
  }

  nonisolated func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
  ) {
    let shouldFinish = completionLock.withLock { () -> Bool in
      guard pendingDelegateCommits == 0 else {
        waitsToFinishBackgroundEvents = true
        return false
      }
      return true
    }
    guard shouldFinish else { return }
    Task { @MainActor in
      RoutineTTSBackgroundLifecycleBridge.shared.backgroundSessionEventsDidFinish(
        identifier: Self.sessionIdentifier
      )
    }
  }

  @MainActor
  private func commitTransfer(
    _ identity: TaskIdentity,
    response: HTTPURLResponse?,
    stagedURL: URL
  ) async {
    let capturedGeneration = managerGeneration
    defer { try? fileManager.removeItem(at: stagedURL) }
    defer { localTaskReservations.remove(identity) }
    do {
      guard let response,
            response.statusCode == 200,
            let responseURL = response.url,
            Self.isAllowedDownloadURL(responseURL, policy: policy) else {
        throw RoutineTTSAudioDownloadError.invalidResponse
      }
      let mimeType = response.mimeType?.lowercased()
      guard mimeType == "audio/mpeg" || mimeType == "audio/mp3" else {
        throw RoutineTTSAudioDownloadError.unsupportedContentType
      }
      let attributes = try fileManager.attributesOfItem(atPath: stagedURL.path)
      guard let size = attributes[.size] as? NSNumber,
            size.int64Value > 0 else {
        throw RoutineTTSAudioDownloadError.emptyBody
      }
      guard size.int64Value <= policy.maximumBytes else {
        throw RoutineTTSAudioDownloadError.fileTooLarge
      }
      try decodeProbe.validate(fileAt: stagedURL)

      guard var job = try await jobStore.allJobs().first(where: {
        $0.id == identity.jobID
      }), capturedGeneration == managerGeneration,
      let assetIndex = job.assets.firstIndex(where: {
        $0.id == identity.assetID
      }), let context = currentContext(),
      job.memberID == context.memberID,
      job.selectionVersion == context.selectionVersion,
      job.selectedTTSID == context.ttsID,
      policy.redirectValidator(
        job.assets[assetIndex].cacheKey.remoteURL,
        responseURL
      ) else {
        await markTransferNeedsRemoteRefresh(identity)
        return
      }
      let key = job.assets[assetIndex].cacheKey
      _ = try await audioCache.storeDownloadedFile(at: stagedURL, for: key)
      guard capturedGeneration == managerGeneration,
            let contextAfterStore = currentContext(),
            contextAfterStore.memberID == context.memberID,
            contextAfterStore.selectionVersion == context.selectionVersion,
            contextAfterStore.ttsID == context.ttsID else {
        try? await audioCache.removeFile(for: key)
        await markTransferNeedsRemoteRefresh(identity)
        return
      }
      guard let refreshed = try await jobStore.allJobs().first(where: {
        $0.id == identity.jobID
      }), capturedGeneration == managerGeneration,
      refreshed.memberID == context.memberID,
      refreshed.selectionVersion == context.selectionVersion,
      refreshed.selectedTTSID == context.ttsID else {
        try? await audioCache.removeFile(for: key)
        await markTransferNeedsRemoteRefresh(identity)
        return
      }
      job = refreshed
      guard let refreshedIndex = job.assets.firstIndex(where: {
        $0.id == identity.assetID
      }) else {
        try? await audioCache.removeFile(for: key)
        await markTransferNeedsRemoteRefresh(identity)
        return
      }
      job.assets[refreshedIndex].state = .completed
      job.state = Self.jobState(for: job.assets)
      job.updatedAt = now()
      try await jobStore.replace(job)
      let finalContext = currentContext()
      guard capturedGeneration == managerGeneration,
            let finalContext,
            finalContext.memberID == context.memberID,
            finalContext.selectionVersion == context.selectionVersion,
            finalContext.ttsID == context.ttsID else {
        try? await audioCache.removeFile(for: key)
        if let finalContext {
          _ = try? await jobStore.removeStaleJobs(
            keepingMemberID: finalContext.memberID,
            selectionVersion: finalContext.selectionVersion,
            selectedTTSID: finalContext.ttsID
          )
        }
        return
      }
      logger.notice("TTS transfer state: downloadCommitted")
      await publishAggregateStatus(
        memberID: job.memberID,
        selectionVersion: job.selectionVersion,
        selectedTTSID: job.selectedTTSID
      )
    } catch {
      await markTransferForRetry(identity)
    }
  }

  @MainActor
  private func markTransferForRetry(_ identity: TaskIdentity) async {
    do {
      guard var job = try await jobStore.allJobs().first(where: {
        $0.id == identity.jobID
      }), let assetIndex = job.assets.firstIndex(where: {
        $0.id == identity.assetID
      }) else {
        return
      }
      job.assets[assetIndex].state = .queued
      job.state = .retryScheduled
      job.updatedAt = now()
      try await jobStore.replace(job)
      localTaskReservations.remove(identity)
      logger.notice("TTS transfer state: retryScheduled")
      statusCenter.report(
        .retryScheduled,
        component: Self.component(for: job.assetKind),
        memberID: job.memberID,
        selectionVersion: job.selectionVersion,
        selectedTTSID: job.selectedTTSID
      )
      RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
    } catch {
      logger.error("TTS transfer state: retryPersistenceFailed")
    }
  }

  @MainActor
  private func markTransferNeedsRemoteRefresh(
    _ identity: TaskIdentity
  ) async {
    defer { localTaskReservations.remove(identity) }
    guard var job = try? await jobStore.allJobs().first(where: {
      $0.id == identity.jobID
    }), let assetIndex = job.assets.firstIndex(where: {
      $0.id == identity.assetID
    }) else {
      return
    }
    job.assets[assetIndex].state = .queued
    job.state = .pendingRemote
    job.nextRemoteAttemptAt = now()
    job.updatedAt = now()
    try? await jobStore.replace(job)
    RoutineTTSBackgroundLifecycleBridge.shared.scheduleRefresh()
  }

  @MainActor
  private func publishAggregateStatus(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) async {
    guard let jobs = try? await jobStore.allJobs() else { return }
    for component in [
      RoutineTTSPreparationComponent.routineIntro,
      RoutineTTSPreparationComponent.commonCues,
    ] {
      let componentJobs = jobs.filter {
        $0.memberID == memberID
          && $0.selectionVersion == selectionVersion
          && $0.selectedTTSID == selectedTTSID
          && Self.component(for: $0.assetKind) == component
      }
      guard !componentJobs.isEmpty else { continue }
      let state: RoutineTTSPreparationDisplayState
      if componentJobs.allSatisfy({ $0.state == .completed }) {
        state = .ready
      } else if componentJobs.contains(where: { $0.state == .retryScheduled }) {
        state = .retryScheduled
      } else {
        state = .preparing
      }
      statusCenter.report(
        state,
        component: component,
        memberID: memberID,
        selectionVersion: selectionVersion,
        selectedTTSID: selectedTTSID
      )
    }
  }

  private static func jobState(
    for assets: [RoutineTTSPrefetchAsset]
  ) -> RoutineTTSPrefetchJobState {
    guard !assets.isEmpty else { return .pendingRemote }
    if assets.allSatisfy({ $0.state == .completed }) {
      return .completed
    }
    return .downloading
  }

  @MainActor
  private func isCurrent(job: RoutineTTSPrefetchJob) -> Bool {
    guard let context = currentContext() else { return false }
    return job.memberID == context.memberID
      && job.selectionVersion == context.selectionVersion
      && job.selectedTTSID == context.ttsID
  }

  @MainActor
  private func isActiveContext(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) -> Bool {
    guard let activeContext else { return false }
    return activeContext.memberID == memberID
      && activeContext.selectionVersion == selectionVersion
      && activeContext.ttsID == selectedTTSID
  }

  private static func component(
    for assetKind: RoutineTTSAudioCacheKey.AssetKind
  ) -> RoutineTTSPreparationComponent {
    switch assetKind {
    case .routineIntro:
      .routineIntro
    case .commonDone, .commonRemind:
      .commonCues
    }
  }

  nonisolated private static func isAllowedDownloadURL(
    _ url: URL,
    policy: RoutineTTSAudioDownloadPolicy
  ) -> Bool {
    RoutineTTSAudioDownloader.isAllowedHTTPSURL(url)
      && policy.sourceValidator(url)
  }

  private static func defaultStagingRoot(
    fileManager: FileManager
  ) throws -> URL {
    guard let caches = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first else {
      throw RoutineTTSAudioCacheError.storageFailure
    }
    return caches
      .appendingPathComponent("MoruRoutineTTSBackground", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
  }

  @MainActor
  private func backgroundTaskDescriptions() async -> [String] {
    if let taskRegistry {
      return await taskRegistry.taskDescriptions()
    }
    return (await session.allTasks).compactMap(\.taskDescription)
  }

  @MainActor
  private func startBackgroundTask(
    request: URLRequest,
    identity: TaskIdentity
  ) {
    if let taskRegistry {
      taskRegistry.start(
        request: request,
        taskDescription: identity.description
      )
      return
    }
    let task = session.downloadTask(with: request)
    task.taskDescription = identity.description
    task.resume()
  }

  @MainActor
  private func cancelBackgroundTask(description: String) async {
    if let taskRegistry {
      taskRegistry.cancel(taskDescription: description)
      return
    }
    for task in await session.allTasks
    where task.taskDescription == description {
      task.cancel()
    }
  }

  @MainActor
  private func cancelAllBackgroundTasks() async {
    if let taskRegistry {
      taskRegistry.cancelAll()
      return
    }
    let tasks = await session.allTasks
    tasks.forEach { $0.cancel() }
  }

  @MainActor
  func completeTransferForTesting(
    jobID: UUID,
    assetID: UUID,
    response: HTTPURLResponse,
    stagedURL: URL
  ) async {
    await commitTransfer(
      TaskIdentity(jobID: jobID, assetID: assetID),
      response: response,
      stagedURL: stagedURL
    )
  }

  nonisolated private func finishDelegateCommit() {
    let shouldFinish = completionLock.withLock { () -> Bool in
      pendingDelegateCommits = max(0, pendingDelegateCommits - 1)
      guard pendingDelegateCommits == 0, waitsToFinishBackgroundEvents else {
        return false
      }
      waitsToFinishBackgroundEvents = false
      return true
    }
    guard shouldFinish else { return }
    Task { @MainActor in
      RoutineTTSBackgroundLifecycleBridge.shared.backgroundSessionEventsDidFinish(
        identifier: Self.sessionIdentifier
      )
    }
  }
}

/// Buffers iOS callbacks that can arrive before the dependency graph is ready.
/// The background-session completion is called only after URLSession reports
/// that all launch events have been delivered.
@MainActor
final class RoutineTTSBackgroundLifecycleBridge {
  static let shared = RoutineTTSBackgroundLifecycleBridge()

  private weak var transferManager: RoutineTTSBackgroundTransferManager?
  private var resumeHandler: (@MainActor () async -> Void)?
  private var pendingSessionCompletion: (() -> Void)?
  private var pendingSessionIdentifier: String?
  private var refreshTask: BGAppRefreshTask?
  private var refreshOperation: Task<Void, Never>?
  private var didRegister = false

  private init() {}

  func register() {
    guard !didRegister else { return }
    didRegister = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: RoutineTTSBackgroundTransferManager.refreshIdentifier,
      using: nil
    ) { task in
      guard let task = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      Task { @MainActor in
        self.handle(task)
      }
    }
  }

  func configure(
    transferManager: RoutineTTSBackgroundTransferManager,
    resumeHandler: @escaping @MainActor () async -> Void
  ) {
    self.transferManager = transferManager
    self.resumeHandler = resumeHandler
    transferManager.activateAtLaunch()
    if let refreshTask, refreshOperation == nil {
      startRefreshOperation(for: refreshTask)
    }
  }

  func handleEventsForBackgroundURLSession(
    identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == RoutineTTSBackgroundTransferManager.sessionIdentifier else {
      completionHandler()
      return
    }
    pendingSessionIdentifier = identifier
    pendingSessionCompletion = completionHandler
    transferManager?.activateAtLaunch()
  }

  func backgroundSessionEventsDidFinish(identifier: String) {
    guard pendingSessionIdentifier == identifier else { return }
    let completion = pendingSessionCompletion
    pendingSessionIdentifier = nil
    pendingSessionCompletion = nil
    completion?()
    Task {
      await resumeHandler?()
    }
  }

  func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(
      identifier: RoutineTTSBackgroundTransferManager.refreshIdentifier
    )
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  private func handle(_ task: BGAppRefreshTask) {
    guard refreshTask == nil else {
      task.setTaskCompleted(success: false)
      return
    }
    refreshTask = task
    scheduleRefresh()
    task.expirationHandler = {
      Task { @MainActor in
        self.expireRefreshTask(task)
      }
    }
    guard resumeHandler != nil else {
      // A cold BG launch can deliver this before AppRouter finishes building
      // the dependency graph. Keep it bounded by the system expiration and
      // let configure() start the persisted-queue resume once ready.
      return
    }
    startRefreshOperation(for: task)
  }

  private func startRefreshOperation(for task: BGAppRefreshTask) {
    guard refreshTask === task,
          refreshOperation == nil,
          let resumeHandler else { return }
    let operation = Task { @MainActor in
      await resumeHandler()
      guard !Task.isCancelled, refreshTask === task else { return }
      task.setTaskCompleted(success: true)
      refreshTask = nil
      refreshOperation = nil
    }
    refreshOperation = operation
  }

  private func expireRefreshTask(_ task: BGAppRefreshTask) {
    guard refreshTask === task else { return }
    refreshOperation?.cancel()
    task.setTaskCompleted(success: false)
    refreshTask = nil
    refreshOperation = nil
  }
}
