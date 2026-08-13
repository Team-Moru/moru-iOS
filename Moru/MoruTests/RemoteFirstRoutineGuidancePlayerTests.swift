//
//  RemoteFirstRoutineGuidancePlayerTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

@MainActor
final class RemoteFirstRoutineGuidancePlayerTests: XCTestCase {
  func testResolverRequiresMatchingParentAndEveryRemoteAssetPlayable() {
    let groupID = UUID()
    let routineID = UUID()
    let group = binding(kind: .routineGroup, localID: groupID, remoteID: 41)
    let child = binding(
      kind: .routine,
      localID: routineID,
      remoteID: 51,
      parentID: groupID
    )
    let response = [remoteRoutine(id: 51, stepIDs: [71, 72])]

    XCTAssertEqual(
      RoutineTTSCuePlanResolver().resolve(
        routineGroupLocalID: groupID,
        routineLocalID: routineID,
        groupBinding: group,
        routineBinding: child,
        response: response
      ),
      .playable([
        asset(routineID: 51, stepID: 71),
        asset(routineID: 51, stepID: 72),
      ])
    )

    let wrongParent = binding(
      kind: .routine,
      localID: routineID,
      remoteID: 51,
      parentID: UUID()
    )
    XCTAssertEqual(
      RoutineTTSCuePlanResolver().resolve(
        routineGroupLocalID: groupID,
        routineLocalID: routineID,
        groupBinding: group,
        routineBinding: wrongParent,
        response: response
      ),
      .unavailable
    )

    let partial = [remoteRoutine(id: 51, stepIDs: [71], includePending: true)]
    XCTAssertEqual(
      RoutineTTSCuePlanResolver().resolve(
        routineGroupLocalID: groupID,
        routineLocalID: routineID,
        groupBinding: group,
        routineBinding: child,
        response: partial
      ),
      .unavailable
    )
  }

  func testIntroUsesEveryPreparedLocalAssetInOrder() async {
    let groupID = UUID()
    let routineID = UUID()
    let first = URL(fileURLWithPath: "/tmp/first.mp3")
    let second = URL(fileURLWithPath: "/tmp/second.mp3")
    let bundled = GuidancePlayerRecorder()
    let remote = LocalSequencePlayerRecorder(result: .completed)
    let provider = LocalAudioProviderStub(urls: [first, second])
    let player = RemoteFirstRoutineGuidancePlayer(
      bundledPlayer: bundled,
      remotePlayer: remote,
      localAudioProvider: provider
    )

    let result = await player.play(RoutineGuidanceCueRequest(
      routineGroupLocalID: groupID,
      routineLocalID: routineID,
      routineTitle: "루틴",
      routineType: .confirm,
      fallbackItemID: "ENERGY-02",
      voiceCode: "Aoede",
      kind: .intro
    ))

    XCTAssertEqual(result, .completed)
    XCTAssertEqual(remote.sequences, [[first, second]])
    XCTAssertTrue(bundled.calls.isEmpty)
  }

  func testRemoteCancellationNeverFallsBackAfterStarting() async {
    let bundled = GuidancePlayerRecorder()
    let remote = LocalSequencePlayerRecorder(result: .cancelled)
    let provider = LocalAudioProviderStub(
      urls: [URL(fileURLWithPath: "/tmp/intro.mp3")]
    )
    let player = RemoteFirstRoutineGuidancePlayer(
      bundledPlayer: bundled,
      remotePlayer: remote,
      localAudioProvider: provider
    )

    let result = await player.play(remoteRequest(kind: .intro))

    XCTAssertEqual(result, .cancelled)
    XCTAssertTrue(bundled.calls.isEmpty)
  }

  func testCacheMissDoneAndLegacyPreviewUseBundleOnly() async {
    let bundled = GuidancePlayerRecorder()
    let remote = LocalSequencePlayerRecorder(result: .completed)
    let player = RemoteFirstRoutineGuidancePlayer(
      bundledPlayer: bundled,
      remotePlayer: remote,
      localAudioProvider: LocalAudioProviderStub(urls: nil)
    )

    let introResult = await player.play(remoteRequest(kind: .intro))
    let doneResult = await player.play(remoteRequest(kind: .done))
    let previewResult = await player.play(
      itemID: "ENERGY-02",
      voiceCode: "Kore",
      kind: .intro
    )
    XCTAssertEqual(introResult, .completed)
    XCTAssertEqual(doneResult, .completed)
    XCTAssertEqual(previewResult, .completed)

    XCTAssertEqual(bundled.calls.map(\.kind), [.intro, .done, .intro])
    XCTAssertTrue(remote.sequences.isEmpty)
  }

  func testLegacyBundlePlaybackStopsRemoteAndWaitsBeforeStarting() async {
    let remote = BlockingLocalSequencePlayer()
    let bundled = OverlapDetectingGuidancePlayer(remotePlayer: remote)
    let player = RemoteFirstRoutineGuidancePlayer(
      bundledPlayer: bundled,
      remotePlayer: remote,
      localAudioProvider: LocalAudioProviderStub(
        urls: [URL(fileURLWithPath: "/tmp/intro.mp3")]
      )
    )
    let remoteTask = Task { await player.play(remoteRequest(kind: .intro)) }
    await remote.waitUntilStarted()

    let previewResult = await player.play(
      itemID: "ENERGY-02",
      voiceCode: "Kore",
      kind: .intro
    )

    XCTAssertEqual(previewResult, .completed)
    let remoteResult = await remoteTask.value
    XCTAssertEqual(remoteResult, .cancelled)
    XCTAssertFalse(bundled.observedRemoteOverlap)
    XCTAssertEqual(remote.stopAndWaitCallCount, 1)
  }

  func testSessionChangeStopsAlreadyStartedRemoteAccountAudio() async throws {
    let fixture = try await makeWarmupFixture(response: [])
    let remote = BlockingLocalSequencePlayer()
    let player = RemoteFirstRoutineGuidancePlayer(
      bundledPlayer: GuidancePlayerRecorder(),
      remotePlayer: remote,
      localAudioProvider: LocalAudioProviderStub(
        urls: [URL(fileURLWithPath: "/tmp/intro.mp3")]
      )
    )
    fixture.coordinator.setPlaybackSessionInvalidator(player)
    let playTask = Task { await player.play(remoteRequest(kind: .intro)) }
    await remote.waitUntilStarted()

    fixture.identityProvider.currentAccountSessionIdentity = nil
    fixture.coordinator.accountSessionDidChange()

    let playResult = await playTask.value
    XCTAssertEqual(playResult, .cancelled)
    XCTAssertEqual(remote.stopCallCount, 1)
  }

  func testCancelledLookupCannotResumeIntoOldStepBundleFallback() async {
    let provider = SuspendedLocalAudioProvider()
    let bundled = GuidancePlayerRecorder()
    let player = RemoteFirstRoutineGuidancePlayer(
      bundledPlayer: bundled,
      remotePlayer: LocalSequencePlayerRecorder(result: .failedToStart),
      localAudioProvider: provider
    )
    let task = Task { await player.play(remoteRequest(kind: .intro)) }
    await provider.waitUntilRequested()

    task.cancel()
    provider.resume(with: nil)

    let result = await task.value
    XCTAssertEqual(result, .cancelled)
    XCTAssertTrue(bundled.calls.isEmpty)
  }

  func testCustomStepCanRequestRemoteIntroWithoutBundleItem() async {
    let player = ContextGuidanceRecorder()
    let coordinator = RoutineGuidanceCoordinator(
      player: player,
      routineGroupLocalID: UUID()
    )
    let custom = RoutineStep(type: .confirm, title: "커스텀", order: 0)

    coordinator.stepDidStart(custom)
    for _ in 0..<10 { await Task.yield() }

    XCTAssertEqual(player.requests.count, 1)
    XCTAssertEqual(player.requests.first?.routineLocalID, custom.id)
    XCTAssertNil(player.requests.first?.fallbackItemID)
  }

  func testWarmupJoinsBindingsAndPublishesOnlyCompleteCachedSequence() async throws {
    let fixture = try await makeWarmupFixture(response: [remoteRoutine(id: 51, stepIDs: [71, 72])])
    try await fixture.seedCachedFiles(stepIDs: [71, 72])

    fixture.coordinator.prepare(
      routineGroupLocalID: fixture.groupID,
      routineLocalIDs: [fixture.routineID]
    )
    let urls = await waitForLocalURLs(fixture)
    let remoteCallCount = await fixture.remote.callCount

    XCTAssertEqual(urls?.count, 2)
    XCTAssertEqual(remoteCallCount, 1)
  }

  func testWarmupRejectsPendingOrIncompleteSequenceWithoutPartialPlan() async throws {
    let response = [remoteRoutine(id: 51, stepIDs: [71], includePending: true)]
    let fixture = try await makeWarmupFixture(response: response)
    try await fixture.seedCachedFiles(stepIDs: [71])

    fixture.coordinator.prepare(
      routineGroupLocalID: fixture.groupID,
      routineLocalIDs: [fixture.routineID]
    )
    for _ in 0..<30 { await Task.yield() }
    let urls = await fixture.coordinator.localAudioURLs(
      for: RoutineTTSLocalAudioRequest(
        routineGroupLocalID: fixture.groupID,
        routineLocalID: fixture.routineID,
        routineTitle: "루틴",
        routineType: .confirm
      )
    )

    XCTAssertNil(urls)
  }

  func testWarmupRejectsRemoteTitleMismatch() async throws {
    let fixture = try await makeWarmupFixture(
      response: [remoteRoutine(id: 51, stepIDs: [71], title: "이전 제목")]
    )
    try await fixture.seedCachedFiles(stepIDs: [71])

    fixture.coordinator.prepare(
      routineGroupLocalID: fixture.groupID,
      routineLocalIDs: [fixture.routineID]
    )
    for _ in 0..<30 { await Task.yield() }

    let urls = await fixture.coordinator.localAudioURLs(for: fixture.localRequest())
    XCTAssertNil(urls)
  }

  func testPreparedPlanRejectsCurrentStepAfterLocalTitleEdit() async throws {
    let fixture = try await makeWarmupFixture(
      response: [remoteRoutine(id: 51, stepIDs: [71])]
    )
    try await fixture.seedCachedFiles(stepIDs: [71])
    fixture.coordinator.prepare(
      routineGroupLocalID: fixture.groupID,
      routineLocalIDs: [fixture.routineID]
    )
    let warmedURLs = await waitForLocalURLs(fixture)
    XCTAssertNotNil(warmedURLs)

    fixture.routineRepository.routines[0].steps[0].title = "수정된 제목"

    let editedURLs = await fixture.coordinator.localAudioURLs(
      for: fixture.localRequest(title: "수정된 제목")
    )
    XCTAssertNil(editedURLs)
  }

  func testSceneActivationScansActiveRoutineAndWarmsIt() async throws {
    let groupID = UUID()
    let routineID = UUID()
    let routine = Routine(
      id: groupID,
      name: "활성 루틴",
      steps: [RoutineStep(id: routineID, type: .confirm, title: "루틴", order: 0)]
    )
    let fixture = try await makeWarmupFixture(
      groupID: groupID,
      routineID: routineID,
      response: [remoteRoutine(id: 51, stepIDs: [71])],
      routines: [routine]
    )
    try await fixture.seedCachedFiles(stepIDs: [71])

    fixture.coordinator.setSceneActive(true)
    let urls = await waitForLocalURLs(fixture)

    XCTAssertEqual(urls?.count, 1)
    XCTAssertEqual(fixture.routineRepository.fetchActiveCallCount, 1)
  }

  func testSameMemberSessionChangeRejectsDeferredResponseAndPurgesOldCache() async throws {
    let fixture = try await makeWarmupFixture(
      response: [remoteRoutine(id: 51, stepIDs: [71])]
    )
    try await fixture.seedCachedFiles(stepIDs: [71])
    await fixture.remote.suspendNextResponse()
    fixture.coordinator.prepare(
      routineGroupLocalID: fixture.groupID,
      routineLocalIDs: [fixture.routineID]
    )
    for _ in 0..<100 {
      if await fixture.remote.callCount > 0 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }

    fixture.identityProvider.currentAccountSessionIdentity = AccountSessionIdentity(
      memberID: 7,
      sessionID: UUID()
    )
    fixture.coordinator.accountSessionDidChange()
    await fixture.remote.resumeResponse()
    try? await Task.sleep(for: .milliseconds(100))

    let urls = await fixture.coordinator.localAudioURLs(
      for: RoutineTTSLocalAudioRequest(
        routineGroupLocalID: fixture.groupID,
        routineLocalID: fixture.routineID,
        routineTitle: "루틴",
        routineType: .confirm
      )
    )
    let oldCachedURL = await fixture.cache.cachedFileURL(
      for: fixture.cacheKey(stepID: 71),
      allowStale: true
    )
    XCTAssertNil(urls)
    XCTAssertNil(oldCachedURL)
  }

  func testSessionPurgeStopsWarmupBeforeStartingSecondOldAccountDownload() async throws {
    let downloader = SuspendedWarmupDownloader()
    let fixture = try await makeWarmupFixture(
      response: [remoteRoutine(id: 51, stepIDs: [71, 72])],
      downloader: downloader
    )
    fixture.coordinator.prepare(
      routineGroupLocalID: fixture.groupID,
      routineLocalIDs: [fixture.routineID]
    )
    await downloader.waitUntilFirstDownloadStarts()

    fixture.identityProvider.currentAccountSessionIdentity = nil
    fixture.coordinator.accountSessionDidChange()
    await downloader.resumeFirstDownload()
    for _ in 0..<100 {
      if await downloader.callCount == 1,
         (try? FileManager.default.contentsOfDirectory(
           at: fixture.root,
           includingPropertiesForKeys: nil
         ).isEmpty) == true { break }
      try? await Task.sleep(for: .milliseconds(5))
    }

    let downloadCallCount = await downloader.callCount
    XCTAssertEqual(downloadCallCount, 1)
    let cachedFirst = await fixture.cache.cachedFileURL(
      for: fixture.cacheKey(stepID: 71),
      allowStale: true
    )
    let cachedSecond = await fixture.cache.cachedFileURL(
      for: fixture.cacheKey(stepID: 72),
      allowStale: true
    )
    XCTAssertNil(cachedFirst)
    XCTAssertNil(cachedSecond)
  }

  private func remoteRequest(kind: RoutineAudioCueKind) -> RoutineGuidanceCueRequest {
    RoutineGuidanceCueRequest(
      routineGroupLocalID: UUID(),
      routineLocalID: UUID(),
      routineTitle: "루틴",
      routineType: .confirm,
      fallbackItemID: "ENERGY-02",
      voiceCode: "Aoede",
      kind: kind
    )
  }

  private func binding(
    kind: RoutineSyncEntityKind,
    localID: UUID,
    remoteID: Int64,
    parentID: UUID? = nil
  ) -> RoutineServerBinding {
    RoutineServerBinding(
      id: UUID(),
      serverNamespace: .production,
      memberID: 7,
      entityKind: kind,
      localEntityID: localID,
      remoteID: remoteID,
      remoteRevision: nil,
      parentEntityKind: parentID == nil ? nil : .routineGroup,
      parentLocalEntityID: parentID,
      createdAt: .distantPast,
      updatedAt: .distantPast
    )
  }

  private func remoteRoutine(
    id: Int64,
    stepIDs: [Int64],
    includePending: Bool = false,
    title: String = "루틴"
  ) -> ServerRoutineTTSRoutine {
    var steps = stepIDs.map { stepID in
      ServerRoutineTTSStep(
        stepID: stepID,
        content: "안내",
        introText: "안내",
        status: .completed,
        audioURL: URL(string: "https://audio.example.com/\(stepID).mp3")!
      )
    }
    if includePending {
      steps.append(ServerRoutineTTSStep(
        stepID: 99,
        content: "대기",
        introText: nil,
        status: .pending,
        audioURL: nil
      ))
    }
    return ServerRoutineTTSRoutine(
      routineID: id,
      title: title,
      type: .check,
      steps: steps
    )
  }

  private func asset(routineID: Int64, stepID: Int64) -> RoutineTTSResolvedAsset {
    RoutineTTSResolvedAsset(
      remoteRoutineID: routineID,
      remoteStepID: stepID,
      remoteURL: URL(string: "https://audio.example.com/\(stepID).mp3")!
    )
  }

  private func makeWarmupFixture(
    groupID: UUID = UUID(),
    routineID: UUID = UUID(),
    response: [ServerRoutineTTSRoutine],
    routines: [Routine] = [],
    downloader: any RoutineTTSAudioDownloading = RoutineTTSAudioDownloader()
  ) async throws -> WarmupFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let bindings = SwiftDataRoutineSyncRepository(modelContainer: container)
    _ = try bindings.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: routineID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      memberID: 7,
      at: .distantPast
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cache = try RoutineTTSAudioCache(rootDirectory: root)
    let identity = MutableIdentityProvider(
      identity: AccountSessionIdentity(memberID: 7, sessionID: UUID())
    )
    let remote = WarmupRemoteStub(response: response)
    let resolvedRoutines = routines.isEmpty ? [Routine(
      id: groupID,
      name: "루틴 그룹",
      steps: [RoutineStep(
        id: routineID,
        type: .confirm,
        title: "루틴",
        order: 0
      )]
    )] : routines
    let routineRepository = WarmupRoutineRepository(routines: resolvedRoutines)
    let coordinator = RoutineTTSWarmupCoordinator(
      remoteService: remote,
      bindingRepository: bindings,
      routineRepository: routineRepository,
      audioCache: cache,
      downloader: downloader,
      sessionIdentityProvider: identity
    )
    return WarmupFixture(
      groupID: groupID,
      routineID: routineID,
      coordinator: coordinator,
      cache: cache,
      remote: remote,
      identityProvider: identity,
      routineRepository: routineRepository,
      root: root
    )
  }

  private func waitForLocalURLs(_ fixture: WarmupFixture) async -> [URL]? {
    for _ in 0..<100 {
      if let urls = await fixture.coordinator.localAudioURLs(
        for: RoutineTTSLocalAudioRequest(
          routineGroupLocalID: fixture.groupID,
          routineLocalID: fixture.routineID,
          routineTitle: "루틴",
          routineType: .confirm
        )
      ) { return urls }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }
}

@MainActor
private struct WarmupFixture {
  let groupID: UUID
  let routineID: UUID
  let coordinator: RoutineTTSWarmupCoordinator
  let cache: RoutineTTSAudioCache
  let remote: WarmupRemoteStub
  let identityProvider: MutableIdentityProvider
  let routineRepository: WarmupRoutineRepository
  let root: URL

  func seedCachedFiles(stepIDs: [Int64]) async throws {
    let source = root.appendingPathComponent("seed.mp3")
    try Data([1, 2, 3]).write(to: source)
    for stepID in stepIDs {
      _ = try await cache.storeDownloadedFile(
        at: source,
        for: cacheKey(stepID: stepID)
      )
    }
  }

  func cacheKey(stepID: Int64) -> RoutineTTSAudioCacheKey {
    RoutineTTSAudioCacheKey(
      accountID: "7",
      namespace: RoutineSyncServerNamespace.production.rawValue,
      routineGroupID: 41,
      routineID: 51,
      stepID: stepID,
      remoteURL: URL(string: "https://audio.example.com/\(stepID).mp3")!
    )
  }

  func localRequest(
    title: String = "루틴",
    type: RoutineStepType = .confirm
  ) -> RoutineTTSLocalAudioRequest {
    RoutineTTSLocalAudioRequest(
      routineGroupLocalID: groupID,
      routineLocalID: routineID,
      routineTitle: title,
      routineType: type
    )
  }
}

private actor WarmupRemoteStub: RoutineTTSRemoteServing {
  let response: [ServerRoutineTTSRoutine]
  private(set) var callCount = 0
  private var shouldSuspend = false
  private var continuation: CheckedContinuation<[ServerRoutineTTSRoutine], Never>?
  init(response: [ServerRoutineTTSRoutine]) { self.response = response }
  func suspendNextResponse() { shouldSuspend = true }
  func resumeResponse() {
    continuation?.resume(returning: response)
    continuation = nil
    shouldSuspend = false
  }
  func fetchRoutineTTS(
    routineGroupID: Int64,
    identity: AccountSessionIdentity
  ) async throws -> [ServerRoutineTTSRoutine] {
    callCount += 1
    if shouldSuspend {
      return await withCheckedContinuation { continuation = $0 }
    }
    return response
  }
}

private actor SuspendedWarmupDownloader: RoutineTTSAudioDownloading {
  private(set) var callCount = 0
  private var continuation: CheckedContinuation<Void, Never>?

  func download(
    _ request: RoutineTTSAudioDownloadRequest,
    stagingDirectory: URL
  ) async throws -> RoutineTTSAudioDownloadedFile {
    callCount += 1
    let file = stagingDirectory.appendingPathComponent("stream.partial")
    try Data("audio".utf8).write(
      to: file,
      options: .completeFileProtectionUnlessOpen
    )
    if callCount == 1 {
      await withCheckedContinuation { continuation = $0 }
    }
    return RoutineTTSAudioDownloadedFile(fileURL: file, byteCount: 5)
  }

  func waitUntilFirstDownloadStarts() async {
    while callCount == 0 { await Task.yield() }
  }

  func resumeFirstDownload() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class MutableIdentityProvider: CurrentAccountSessionIdentityProviding {
  var currentAccountSessionIdentity: AccountSessionIdentity?
  init(identity: AccountSessionIdentity?) { currentAccountSessionIdentity = identity }
}

@MainActor
private final class WarmupRoutineRepository: RoutineRepository {
  var routines: [Routine]
  private(set) var fetchActiveCallCount = 0
  init(routines: [Routine]) { self.routines = routines }
  func fetchRoutines() throws -> [Routine] { routines }
  func fetchActiveRoutines() throws -> [Routine] {
    fetchActiveCallCount += 1
    return routines.filter(\.isActive)
  }
  func routine(id: UUID) throws -> Routine? { routines.first { $0.id == id } }
  func saveRoutine(_ routine: Routine) throws { routines.append(routine) }
  func saveRoutines(_ routines: [Routine]) throws { self.routines = routines }
  func updateRoutineActivation(id: UUID, isActive: Bool) throws {}
  func deleteRoutine(id: UUID) throws { routines.removeAll { $0.id == id } }
}

@MainActor
private final class LocalAudioProviderStub: RoutineTTSLocalAudioProviding {
  let urls: [URL]?
  init(urls: [URL]?) { self.urls = urls }
  func localAudioURLs(for request: RoutineTTSLocalAudioRequest) async -> [URL]? { urls }
}

@MainActor
private final class LocalSequencePlayerRecorder: RoutineLocalAudioSequencePlaying {
  let result: RoutineLocalAudioPlaybackResult
  private(set) var sequences: [[URL]] = []
  init(result: RoutineLocalAudioPlaybackResult) { self.result = result }
  func playLocalAudioSequence(_ urls: [URL]) async -> RoutineLocalAudioPlaybackResult {
    sequences.append(urls)
    return result
  }
  func stop() {}
  func stopAndWaitUntilIdle() async {}
  func resumeAfterSpeechInput() {}
}

@MainActor
private final class BlockingLocalSequencePlayer: RoutineLocalAudioSequencePlaying {
  private var continuation: CheckedContinuation<RoutineLocalAudioPlaybackResult, Never>?
  private(set) var isPlaying = false
  private(set) var stopCallCount = 0
  private(set) var stopAndWaitCallCount = 0

  func playLocalAudioSequence(_ urls: [URL]) async -> RoutineLocalAudioPlaybackResult {
    isPlaying = true
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    while !isPlaying { await Task.yield() }
  }

  func stop() {
    stopCallCount += 1
    isPlaying = false
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: .cancelled)
  }

  func stopLocalAudioSequenceAndWaitUntilIdle() async {
    stopAndWaitCallCount += 1
    stop()
    await Task.yield()
  }

  func stopAndWaitUntilIdle() async { stop() }
  func resumeAfterSpeechInput() {}
}

@MainActor
private final class SuspendedLocalAudioProvider: RoutineTTSLocalAudioProviding {
  private var continuation: CheckedContinuation<[URL]?, Never>?
  private(set) var wasRequested = false

  func localAudioURLs(for request: RoutineTTSLocalAudioRequest) async -> [URL]? {
    wasRequested = true
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilRequested() async {
    while !wasRequested { await Task.yield() }
  }

  func resume(with urls: [URL]?) {
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: urls)
  }
}

private struct RecordedGuidanceCall: Equatable {
  let itemID: String
  let voiceCode: String
  let kind: RoutineAudioCueKind
}

@MainActor
private final class GuidancePlayerRecorder: RoutineGuidancePlaying {
  private(set) var calls: [RecordedGuidanceCall] = []
  func play(itemID: String, voiceCode: String, kind: RoutineAudioCueKind) async
    -> GuidancePlaybackResult {
    calls.append(RecordedGuidanceCall(itemID: itemID, voiceCode: voiceCode, kind: kind))
    return .completed
  }
  func stop() {}
  func stopAndWaitUntilIdle() async {}
  func resumeAfterSpeechInput() {}
}

@MainActor
private final class OverlapDetectingGuidancePlayer: RoutineGuidancePlaying {
  private let remotePlayer: BlockingLocalSequencePlayer
  private(set) var observedRemoteOverlap = false

  init(remotePlayer: BlockingLocalSequencePlayer) {
    self.remotePlayer = remotePlayer
  }

  func play(itemID: String, voiceCode: String, kind: RoutineAudioCueKind) async
    -> GuidancePlaybackResult {
    observedRemoteOverlap = remotePlayer.isPlaying
    return .completed
  }

  func stop() {}
  func stopAndWaitUntilIdle() async {}
  func resumeAfterSpeechInput() {}
}

@MainActor
private final class ContextGuidanceRecorder: RoutineGuidancePlaying {
  private(set) var requests: [RoutineGuidanceCueRequest] = []
  func play(itemID: String, voiceCode: String, kind: RoutineAudioCueKind) async
    -> GuidancePlaybackResult { .completed }
  func play(_ request: RoutineGuidanceCueRequest) async -> GuidancePlaybackResult {
    requests.append(request)
    return .completed
  }
  func stop() {}
  func stopAndWaitUntilIdle() async {}
  func resumeAfterSpeechInput() {}
}
