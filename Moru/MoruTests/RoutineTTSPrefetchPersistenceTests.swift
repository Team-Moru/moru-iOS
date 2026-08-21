//
//  RoutineTTSPrefetchPersistenceTests.swift
//  MoruTests
//


import Foundation
import XCTest

@testable import Moru

final class RoutineTTSPrefetchPersistenceTests: XCTestCase {
  func testPendingAndDownloadingJobsSurviveStoreRecreation() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("jobs.json")
    let pending = makeJob(state: .pendingRemote)
    let downloading = makeJob(
      state: .downloading,
      assetState: .downloading,
      routineLocalID: UUID()
    )
    do {
      let firstStore = try FileRoutineTTSPrefetchJobStore(fileURL: fileURL)
      _ = try await firstStore.upsert(pending)
      _ = try await firstStore.upsert(downloading)
    }

    let relaunchedStore = try FileRoutineTTSPrefetchJobStore(fileURL: fileURL)
    let restored = try await relaunchedStore.allJobs()

    XCTAssertEqual(Set(restored.map(\.id)), Set([pending.id, downloading.id]))
    XCTAssertTrue(restored.contains { $0.state == .pendingRemote })
    XCTAssertTrue(restored.contains {
      $0.state == .downloading && $0.assets.first?.state == .downloading
    })
  }

  func testStaleCleanupKeepsOnlyExactAccountVersionAndVoice() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("jobs.json")
    let store = try FileRoutineTTSPrefetchJobStore(fileURL: fileURL)
    let current = makeJob(state: .pendingRemote)
    let staleAccount = makeJob(state: .pendingRemote, memberID: 8)
    let staleVersion = makeJob(state: .pendingRemote, selectionVersion: 4)
    let staleVoice = makeJob(state: .pendingRemote, selectedTTSID: 12)
    for job in [current, staleAccount, staleVersion, staleVoice] {
      _ = try await store.upsert(job)
    }

    let removedCount = try await store.removeStaleJobs(
      keepingMemberID: 7,
      selectionVersion: 3,
      selectedTTSID: 11
    )

    XCTAssertEqual(removedCount, 3)
    let relaunchedStore = try FileRoutineTTSPrefetchJobStore(fileURL: fileURL)
    let retained = try await relaunchedStore.allJobs()
    XCTAssertEqual(retained.map(\.id), [current.id])
    XCTAssertEqual(retained.first?.memberID, 7)
    XCTAssertEqual(retained.first?.selectionVersion, 3)
    XCTAssertEqual(retained.first?.selectedTTSID, 11)
  }

  @MainActor
  func testRetryDeadlineDefersOldURLUntilFreshStatusIsDue() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let jobsURL = root.appendingPathComponent("jobs.json")
    let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
    let registry = FakeBackgroundTaskRegistry()
    let initialNow = Date(timeIntervalSince1970: 1_000)
    let deadline = Date(timeIntervalSince1970: 1_060)
    let clock = LockedPrefetchDateClock(initialNow)
    var retryJob = makeJob(state: .retryScheduled)
    retryJob.nextRemoteAttemptAt = deadline
    retryJob.updatedAt = initialNow

    do {
      let store = try FileRoutineTTSPrefetchJobStore(fileURL: jobsURL)
      let cache = try RoutineTTSAudioCache(rootDirectory: cacheRoot)
      _ = try await store.upsert(retryJob)
      let manager = try makeManager(
        store: store,
        cache: cache,
        registry: registry,
        root: root,
        now: { clock.value() }
      )

      await manager.resumePendingTransfers(
        memberID: 7,
        selectionVersion: 3,
        selectedTTSID: 11
      )

      let deferredJobs = try await store.allJobs()
      let deferred = try XCTUnwrap(deferredJobs.first)
      XCTAssertEqual(deferred.state, .retryScheduled)
      XCTAssertEqual(deferred.nextRemoteAttemptAt, deadline)
      XCTAssertEqual(deferred.assets.first?.state, .queued)
      XCTAssertEqual(registry.startCount, 0)
      XCTAssertTrue(registry.activeTaskDescriptions.isEmpty)
    }

    let dueNow = Date(timeIntervalSince1970: 1_061)
    clock.set(dueNow)
    do {
      let relaunchedStore = try FileRoutineTTSPrefetchJobStore(fileURL: jobsURL)
      let relaunchedCache = try RoutineTTSAudioCache(rootDirectory: cacheRoot)
      let relaunchedManager = try makeManager(
        store: relaunchedStore,
        cache: relaunchedCache,
        registry: registry,
        root: root,
        now: { clock.value() }
      )

      await relaunchedManager.resumePendingTransfers(
        memberID: 7,
        selectionVersion: 3,
        selectedTTSID: 11
      )

      let dueJobs = try await relaunchedStore.allJobs()
      let due = try XCTUnwrap(dueJobs.first)
      XCTAssertEqual(due.state, .pendingRemote)
      XCTAssertEqual(due.nextRemoteAttemptAt, dueNow)
      XCTAssertEqual(due.assets.first?.state, .queued)
      XCTAssertEqual(registry.startCount, 0)
      XCTAssertTrue(registry.activeTaskDescriptions.isEmpty)
    }
  }

  @MainActor
  func testRelaunchAndRepeatedResumeStartSameTransferOnlyOnce() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let jobsURL = root.appendingPathComponent("jobs.json")
    let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
    let registry = FakeBackgroundTaskRegistry()
    let job = makeJob(state: .downloading)
    do {
      let store = try FileRoutineTTSPrefetchJobStore(fileURL: jobsURL)
      let cache = try RoutineTTSAudioCache(rootDirectory: cacheRoot)
      _ = try await store.upsert(job)
      let manager = try makeManager(
        store: store,
        cache: cache,
        registry: registry,
        root: root
      )
      await manager.resumePendingTransfers(
        memberID: 7,
        selectionVersion: 3,
        selectedTTSID: 11
      )
      XCTAssertEqual(registry.startCount, 1)
    }

    do {
      let relaunchedStore = try FileRoutineTTSPrefetchJobStore(fileURL: jobsURL)
      let relaunchedCache = try RoutineTTSAudioCache(rootDirectory: cacheRoot)
      let relaunchedManager = try makeManager(
        store: relaunchedStore,
        cache: relaunchedCache,
        registry: registry,
        root: root
      )
      await relaunchedManager.resumePendingTransfers(
        memberID: 7,
        selectionVersion: 3,
        selectedTTSID: 11
      )
      await relaunchedManager.resumePendingTransfers(
        memberID: 7,
        selectionVersion: 3,
        selectedTTSID: 11
      )
    }

    XCTAssertEqual(registry.startCount, 1)
    XCTAssertEqual(registry.activeTaskDescriptions.count, 1)
  }

  @MainActor
  func testStaleAccountVersionAndVoiceJobIsDiscardedAndTaskCancelled() async throws {
    let fixture = try await makeManagerFixture(assetState: .downloading)
    fixture.registry.seed(
      taskDescription: taskDescription(
        jobID: fixture.job.id,
        assetID: try XCTUnwrap(fixture.job.assets.first?.id)
      )
    )

    await fixture.firstManager.resumePendingTransfers(
      memberID: 8,
      selectionVersion: 4,
      selectedTTSID: 12
    )

    let remainingJobs = try await fixture.store.allJobs()
    XCTAssertTrue(remainingJobs.isEmpty)
    XCTAssertEqual(fixture.registry.cancelCount, 1)
  }

  @MainActor
  func testLostSystemTaskReturnsDownloadingJobToFreshRemoteStatus() async throws {
    let fixture = try await makeManagerFixture(assetState: .downloading)

    await fixture.firstManager.resumePendingTransfers(
      memberID: 7,
      selectionVersion: 3,
      selectedTTSID: 11
    )

    let persistedJobs = try await fixture.store.allJobs()
    let restored = try XCTUnwrap(persistedJobs.first)
    XCTAssertEqual(restored.state, .pendingRemote)
    XCTAssertEqual(restored.assets.first?.state, .queued)
    XCTAssertEqual(fixture.registry.startCount, 0)
  }

  @MainActor
  func testValidatedCompletionRegistersCacheAndDurableMapping() async throws {
    let fixture = try await makeManagerFixture(assetState: .downloading)
    let asset = try XCTUnwrap(fixture.job.assets.first)
    fixture.registry.seed(
      taskDescription: taskDescription(
        jobID: fixture.job.id,
        assetID: asset.id
      )
    )
    await fixture.firstManager.resumePendingTransfers(
      memberID: 7,
      selectionVersion: 3,
      selectedTTSID: 11
    )
    let downloaded = fixture.root.appendingPathComponent("download.mp3")
    try Data("validated-audio".utf8).write(to: downloaded)
    let response = try XCTUnwrap(HTTPURLResponse(
      url: asset.cacheKey.remoteURL,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "audio/mpeg"]
    ))

    await fixture.firstManager.completeTransferForTesting(
      jobID: fixture.job.id,
      assetID: asset.id,
      response: response,
      stagedURL: downloaded
    )

    let relaunchedStore = try FileRoutineTTSPrefetchJobStore(
      fileURL: fixture.root.appendingPathComponent("jobs.json")
    )
    let relaunchedCache = try RoutineTTSAudioCache(
      rootDirectory: fixture.root.appendingPathComponent("cache", isDirectory: true)
    )
    let persistedJobs = try await relaunchedStore.allJobs()
    let persisted = try XCTUnwrap(persistedJobs.first)
    let persistedKey = try XCTUnwrap(persisted.assets.first?.cacheKey)
    let cacheHit = await relaunchedCache.cachedFileURL(
      for: persistedKey,
      allowStale: true
    )
    let restoredURL = try XCTUnwrap(cacheHit)
    XCTAssertEqual(try Data(contentsOf: restoredURL), Data("validated-audio".utf8))
    XCTAssertEqual(persisted.state, .completed)
    XCTAssertEqual(persisted.assets.first?.state, .completed)
  }

  @MainActor
  private func makeManagerFixture(
    assetState: RoutineTTSPrefetchAssetState
  ) async throws -> ManagerFixture {
    let root = try temporaryDirectory()
    let store = try FileRoutineTTSPrefetchJobStore(
      fileURL: root.appendingPathComponent("jobs.json")
    )
    let cache = try RoutineTTSAudioCache(
      rootDirectory: root.appendingPathComponent("cache", isDirectory: true)
    )
    let registry = FakeBackgroundTaskRegistry()
    let job = makeJob(
      state: .downloading,
      assetState: assetState
    )
    _ = try await store.upsert(job)
    let manager = try makeManager(
      store: store,
      cache: cache,
      registry: registry,
      root: root
    )
    return ManagerFixture(
      root: root,
      store: store,
      cache: cache,
      registry: registry,
      job: job,
      firstManager: manager
    )
  }

  @MainActor
  private func makeManager(
    store: FileRoutineTTSPrefetchJobStore,
    cache: RoutineTTSAudioCache,
    registry: FakeBackgroundTaskRegistry,
    root: URL,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws -> RoutineTTSBackgroundTransferManager {
    try RoutineTTSBackgroundTransferManager(
      jobStore: store,
      audioCache: cache,
      statusCenter: RoutineTTSPreparationStatusCenter(),
      currentContext: { (7, 3, 11) },
      taskRegistry: registry,
      now: now,
      decodeProbe: RoutineTTSAudioDecodeProbe { _ in },
      stagingRoot: root.appendingPathComponent("staging", isDirectory: true)
    )
  }

  private func makeJob(
    state: RoutineTTSPrefetchJobState,
    assetState: RoutineTTSPrefetchAssetState = .queued,
    routineLocalID: UUID = UUID(),
    memberID: Int64 = 7,
    selectionVersion: Int64? = 3,
    selectedTTSID: Int64? = 11
  ) -> RoutineTTSPrefetchJob {
    let key = RoutineTTSAudioCacheKey(
      accountID: String(memberID),
      namespace: "production",
      routineGroupID: 41,
      routineID: 51,
      stepID: 61,
      remoteURL: URL(
        string: "https://bucket.amazonaws.com/audio.mp3?signature=secret"
      )!
    )
    return RoutineTTSPrefetchJob(
      memberID: memberID,
      selectionVersion: selectionVersion,
      selectedTTSID: selectedTTSID,
      assetKind: .routineIntro,
      routineGroupLocalID: UUID(),
      routineLocalID: routineLocalID,
      routineFingerprint: "fingerprint",
      routineGroupRemoteID: 41,
      routineRemoteID: 51,
      state: state,
      assets: [RoutineTTSPrefetchAsset(cacheKey: key, state: assetState)]
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    return url
  }

  private func taskDescription(jobID: UUID, assetID: UUID) -> String {
    "v1:\(jobID.uuidString):\(assetID.uuidString)"
  }
}

@MainActor
private struct ManagerFixture {
  let root: URL
  let store: FileRoutineTTSPrefetchJobStore
  let cache: RoutineTTSAudioCache
  let registry: FakeBackgroundTaskRegistry
  let job: RoutineTTSPrefetchJob
  let firstManager: RoutineTTSBackgroundTransferManager
}

@MainActor
private final class FakeBackgroundTaskRegistry: RoutineTTSBackgroundTaskRegistry {
  private(set) var activeTaskDescriptions: [String] = []
  private(set) var startCount = 0
  private(set) var cancelCount = 0

  func taskDescriptions() async -> [String] {
    activeTaskDescriptions
  }

  func start(request: URLRequest, taskDescription: String) {
    startCount += 1
    activeTaskDescriptions.append(taskDescription)
  }

  func cancel(taskDescription: String) {
    cancelCount += 1
    activeTaskDescriptions.removeAll { $0 == taskDescription }
  }

  func cancelAll() {
    cancelCount += activeTaskDescriptions.count
    activeTaskDescriptions.removeAll()
  }

  func seed(taskDescription: String) {
    activeTaskDescriptions.append(taskDescription)
  }
}

private final class LockedPrefetchDateClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  func value() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return date
  }

  func set(_ date: Date) {
    lock.lock()
    self.date = date
    lock.unlock()
  }
}
