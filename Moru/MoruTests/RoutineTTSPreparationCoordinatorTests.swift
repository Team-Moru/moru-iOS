//
//  RoutineTTSPreparationCoordinatorTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest

@testable import Moru

@MainActor
final class RoutineTTSPreparationCoordinatorTests: XCTestCase {
  func testHappyPathCreatesOncePollsImmediatelyAndCachesReady()
    async throws {
    let fixture = try makeFixture(
      fetchEvents: [.pending, .completed]
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let link = try XCTUnwrap(fixture.link())
    let remoteSnapshot = await fixture.remote.snapshot()
    let sleeperSnapshot = await fixture.sleeper.snapshot()
    let downloadCount = await fixture.downloader.callCount()

    XCTAssertEqual(link.status, .ready)
    XCTAssertEqual(link.assets.count, 1)
    XCTAssertNotNil(link.assets.first?.cachedRelativePath)
    XCTAssertEqual(remoteSnapshot.createCount, 1)
    XCTAssertEqual(remoteSnapshot.fetchCount, 2)
    XCTAssertEqual(sleeperSnapshot.count, 1)
    XCTAssertEqual(downloadCount, 1)
    XCTAssertNotNil(
      fixture.audioFileStore.cachedAudioURL(
        relativePath: try XCTUnwrap(
          link.assets.first?.cachedRelativePath
        )
      )
    )
  }

  func testMissingExpectedIDsRetriesBeforeCompleting()
    async throws {
    let fixture = try makeFixture(
      fetchEvents: [.missing, .completed]
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let remoteSnapshot = await fixture.remote.snapshot()
    let sleeperSnapshot = await fixture.sleeper.snapshot()
    XCTAssertEqual(fixture.link()?.status, .ready)
    XCTAssertEqual(remoteSnapshot.fetchCount, 2)
    XCTAssertEqual(sleeperSnapshot.count, 1)
  }

  func testPendingTimesOutAfterImmediateFetchAndFifteenRetries()
    async throws {
    let fixture = try makeFixture(
      fetchEvents: Array(repeating: .pending, count: 16)
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let link = try XCTUnwrap(fixture.link())
    let remoteSnapshot = await fixture.remote.snapshot()
    let sleeperSnapshot = await fixture.sleeper.snapshot()
    XCTAssertEqual(link.status, .failed)
    XCTAssertEqual(link.lastFailureCode, "polling-timeout")
    XCTAssertEqual(remoteSnapshot.createCount, 1)
    XCTAssertEqual(remoteSnapshot.fetchCount, 16)
    XCTAssertEqual(sleeperSnapshot.count, 15)
  }

  func testOnlyRetryableGETErrorsAreRetriedAndPOSTIsNeverRetried()
    async throws {
    let retryableFixture = try makeFixture(
      fetchEvents: [
        .error(
          .transport(
            code: URLError.networkConnectionLost.rawValue,
            message: "lost"
          )
        ),
        .completed,
      ]
    )
    defer { retryableFixture.cleanUp() }

    retryableFixture.coordinator.routineDidSave(
      retryableFixture.routine
    )
    await retryableFixture.coordinator.waitForPreparation(
      localRoutineID: retryableFixture.routine.id
    )

    let retryableSnapshot = await retryableFixture.remote.snapshot()
    XCTAssertEqual(retryableFixture.link()?.status, .ready)
    XCTAssertEqual(retryableSnapshot.createCount, 1)
    XCTAssertEqual(retryableSnapshot.fetchCount, 2)

    let nonretryableFixture = try makeFixture(
      fetchEvents: [
        .error(.decoding("bad manifest")),
        .completed,
      ]
    )
    defer { nonretryableFixture.cleanUp() }

    nonretryableFixture.coordinator.routineDidSave(
      nonretryableFixture.routine
    )
    await nonretryableFixture.coordinator.waitForPreparation(
      localRoutineID: nonretryableFixture.routine.id
    )

    let nonretryableSnapshot =
      await nonretryableFixture.remote.snapshot()
    XCTAssertEqual(nonretryableFixture.link()?.status, .failed)
    XCTAssertEqual(nonretryableSnapshot.createCount, 1)
    XCTAssertEqual(nonretryableSnapshot.fetchCount, 1)

    let postFailureFixture = try makeFixture(
      fetchEvents: [.completed],
      createError: .transport(code: -1, message: "post failed")
    )
    defer { postFailureFixture.cleanUp() }

    postFailureFixture.coordinator.routineDidSave(
      postFailureFixture.routine
    )
    await postFailureFixture.coordinator.waitForPreparation(
      localRoutineID: postFailureFixture.routine.id
    )

    let postFailureSnapshot =
      await postFailureFixture.remote.snapshot()
    XCTAssertEqual(postFailureFixture.link()?.status, .failed)
    XCTAssertEqual(postFailureSnapshot.createCount, 1)
    XCTAssertEqual(postFailureSnapshot.fetchCount, 0)
  }

  func testFailedUnknownAndExtraIdentifiersFailImmediately()
    async throws {
    let cases: [
      (PreparationFetchEvent, String)
    ] = [
      (.failed, "generation-failed"),
      (.unknown, "unknown-status"),
      (.extraIdentifier, "invalid-manifest"),
    ]

    for (event, expectedCode) in cases {
      let fixture = try makeFixture(fetchEvents: [event])
      fixture.coordinator.routineDidSave(fixture.routine)
      await fixture.coordinator.waitForPreparation(
        localRoutineID: fixture.routine.id
      )

      let link = try XCTUnwrap(fixture.link())
      let remoteSnapshot = await fixture.remote.snapshot()
      XCTAssertEqual(link.status, .failed)
      XCTAssertEqual(link.lastFailureCode, expectedCode)
      XCTAssertEqual(remoteSnapshot.fetchCount, 1)
      fixture.cleanUp()
    }
  }

  func testPartialDownloadFailureRemovesAllRoutineCache()
    async throws {
    let fixture = try makeFixture(
      fetchEvents: [.completed],
      serverStepCount: 2,
      failOnDownloadCall: 2
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let link = try XCTUnwrap(fixture.link())
    let downloadCount = await fixture.downloader.callCount()
    let firstPath = RoutineTTSAudioFileStore.relativePath(
      localRoutineID: fixture.routine.id,
      localStepID: fixture.localStepID,
      serverStepID: 501
    )

    XCTAssertEqual(link.status, .failed)
    XCTAssertEqual(link.lastFailureCode, "audio-download-failed")
    XCTAssertTrue(
      link.assets.allSatisfy {
        $0.cachedRelativePath == nil
      }
    )
    XCTAssertEqual(downloadCount, 2)
    XCTAssertNil(
      fixture.audioFileStore.cachedAudioURL(
        relativePath: firstPath
      )
    )
  }

  func testSignedOutSaveInvalidatesLinkAndCacheWithoutServerCall()
    async throws {
    let fixture = try makeFixture(fetchEvents: [.completed])
    defer { fixture.cleanUp() }
    let plan = try RoutineTTSProvisioningRequestFactory.makePlan(
      for: fixture.routine
    )
    let path = try fixture.audioFileStore.store(
      Data([1, 2, 3]),
      localRoutineID: fixture.routine.id,
      localStepID: fixture.localStepID,
      serverStepID: 501
    )
    try fixture.linkRepository.saveLink(
      readyLink(
        fixture: fixture,
        fingerprint: plan.contentFingerprint,
        cachedRelativePath: path
      )
    )
    fixture.memberProvider.memberID = nil

    fixture.coordinator.routineDidSave(fixture.routine)

    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertNil(
      try fixture.linkRepository.link(
        localRoutineID: fixture.routine.id,
        memberID: fixture.memberID
      )
    )
    XCTAssertNil(
      fixture.audioFileStore.cachedAudioURL(relativePath: path)
    )
    XCTAssertEqual(remoteSnapshot.createCount, 0)
    XCTAssertEqual(remoteSnapshot.fetchCount, 0)
  }

  func testReadyLinkWithEvictedFileResumesGETWithoutAnotherPOST()
    async throws {
    let fixture = try makeFixture(fetchEvents: [.completed])
    defer { fixture.cleanUp() }
    let plan = try RoutineTTSProvisioningRequestFactory.makePlan(
      for: fixture.routine
    )
    let missingPath = RoutineTTSAudioFileStore.relativePath(
      localRoutineID: fixture.routine.id,
      localStepID: fixture.localStepID,
      serverStepID: 501
    )
    try fixture.linkRepository.saveLink(
      readyLink(
        fixture: fixture,
        fingerprint: plan.contentFingerprint,
        cachedRelativePath: missingPath
      )
    )

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let link = try XCTUnwrap(fixture.link())
    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertEqual(link.status, .ready)
    XCTAssertEqual(remoteSnapshot.createCount, 0)
    XCTAssertEqual(remoteSnapshot.fetchCount, 1)
    XCTAssertNotNil(
      fixture.audioFileStore.cachedAudioURL(
        relativePath: missingPath
      )
    )
  }

  func testReadyLinkWithCompleteCacheDoesNoNetworkWork()
    async throws {
    let fixture = try makeFixture(fetchEvents: [.completed])
    defer { fixture.cleanUp() }
    let plan = try RoutineTTSProvisioningRequestFactory.makePlan(
      for: fixture.routine
    )
    let path = try fixture.audioFileStore.store(
      Data([1, 2, 3]),
      localRoutineID: fixture.routine.id,
      localStepID: fixture.localStepID,
      serverStepID: 501
    )
    try fixture.linkRepository.saveLink(
      readyLink(
        fixture: fixture,
        fingerprint: plan.contentFingerprint,
        cachedRelativePath: path
      )
    )

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let link = try XCTUnwrap(fixture.link())
    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertEqual(link.status, .ready)
    XCTAssertEqual(remoteSnapshot.createCount, 0)
    XCTAssertEqual(remoteSnapshot.fetchCount, 0)
    XCTAssertNotNil(
      fixture.audioFileStore.cachedAudioURL(relativePath: path)
    )
  }

  func testEditDeletesOldGroupBestEffortThenCreatesOnce()
    async throws {
    let fixture = try makeFixture(fetchEvents: [.completed])
    defer { fixture.cleanUp() }
    try fixture.linkRepository.saveLink(
      RoutineTTSLink(
        localRoutineID: fixture.routine.id,
        memberID: fixture.memberID,
        serverRoutineGroupID: 99,
        contentFingerprint: "old-fingerprint",
        status: .failed,
        assets: [
          RoutineTTSAsset(
            localStepID: fixture.localStepID,
            serverRoutineID: 88,
            serverStepID: 77,
            orderIndex: 0
          ),
        ],
        lastFailureCode: "old-failure"
      )
    )

    fixture.coordinator.routineDidSave(fixture.routine)
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertEqual(fixture.link()?.status, .ready)
    XCTAssertEqual(remoteSnapshot.deletedRoutineGroupIDs, [99])
    XCTAssertEqual(remoteSnapshot.createCount, 1)
  }

  func testDeleteCancelsAndRemovesLocalStateThenDeletesOldGroup()
    async throws {
    let fixture = try makeFixture(fetchEvents: [.completed])
    defer { fixture.cleanUp() }
    let plan = try RoutineTTSProvisioningRequestFactory.makePlan(
      for: fixture.routine
    )
    let path = try fixture.audioFileStore.store(
      Data([1]),
      localRoutineID: fixture.routine.id,
      localStepID: fixture.localStepID,
      serverStepID: 501
    )
    try fixture.linkRepository.saveLink(
      readyLink(
        fixture: fixture,
        fingerprint: plan.contentFingerprint,
        cachedRelativePath: path
      )
    )
    fixture.routineRepository.routines = []

    fixture.coordinator.routineDidDelete(
      localRoutineID: fixture.routine.id
    )
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertNil(
      try fixture.linkRepository.link(
        localRoutineID: fixture.routine.id,
        memberID: fixture.memberID
      )
    )
    XCTAssertNil(
      fixture.audioFileStore.cachedAudioURL(relativePath: path)
    )
    XCTAssertEqual(
      remoteSnapshot.deletedRoutineGroupIDs,
      [fixture.routineGroupID]
    )
  }

  func testAccountChangeAfterPOSTPreventsStaleCommitAndCleansGroup()
    async throws {
    let gate = PreparationAsyncGate()
    let fixture = try makeFixture(
      fetchEvents: [.completed],
      creationGate: gate
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    for _ in 0..<1_000 {
      let snapshot = await fixture.remote.snapshot()
      if snapshot.createCount == 1 {
        break
      }
      await Task.yield()
    }
    fixture.memberProvider.memberID = nil
    await gate.open()
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertEqual(remoteSnapshot.fetchCount, 0)
    XCTAssertEqual(
      remoteSnapshot.deletedRoutineGroupIDs,
      [fixture.routineGroupID]
    )
    XCTAssertNil(
      try fixture.linkRepository.link(
        localRoutineID: fixture.routine.id,
        memberID: fixture.memberID
      )
    )
  }

  func testAccountChangeWhilePOSTThrowsRemovesCreatingLink()
    async throws {
    let gate = PreparationAsyncGate()
    let fixture = try makeFixture(
      fetchEvents: [.completed],
      createError: .transport(
        code: -1,
        message: "POST failed"
      ),
      creationGate: gate
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    for _ in 0..<1_000 {
      let snapshot = await fixture.remote.snapshot()
      if snapshot.createCount == 1 {
        break
      }
      await Task.yield()
    }
    fixture.memberProvider.memberID = nil
    await gate.open()
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )

    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertEqual(remoteSnapshot.fetchCount, 0)
    XCTAssertTrue(remoteSnapshot.deletedRoutineGroupIDs.isEmpty)
    XCTAssertNil(
      try fixture.linkRepository.link(
        localRoutineID: fixture.routine.id,
        memberID: fixture.memberID
      )
    )
  }

  func testCancelAllPreventsInFlightPOSTFromCommitting()
    async throws {
    let gate = PreparationAsyncGate()
    let fixture = try makeFixture(
      fetchEvents: [.completed],
      creationGate: gate
    )
    defer { fixture.cleanUp() }

    fixture.coordinator.routineDidSave(fixture.routine)
    for _ in 0..<1_000 {
      let snapshot = await fixture.remote.snapshot()
      if snapshot.createCount == 1 {
        break
      }
      await Task.yield()
    }

    fixture.coordinator.cancelAllPreparations()
    await fixture.coordinator.waitForPreparation(
      localRoutineID: fixture.routine.id
    )
    await gate.open()

    for _ in 0..<1_000 {
      let snapshot = await fixture.remote.snapshot()
      if snapshot.deletedRoutineGroupIDs
        == [fixture.routineGroupID] {
        break
      }
      await Task.yield()
    }

    let remoteSnapshot = await fixture.remote.snapshot()
    XCTAssertEqual(remoteSnapshot.createCount, 1)
    XCTAssertEqual(remoteSnapshot.fetchCount, 0)
    XCTAssertEqual(
      remoteSnapshot.deletedRoutineGroupIDs,
      [fixture.routineGroupID]
    )
    XCTAssertNotEqual(fixture.link()?.status, .ready)
  }

  private func makeFixture(
    fetchEvents: [PreparationFetchEvent],
    serverStepCount: Int = 1,
    failOnDownloadCall: Int? = nil,
    createError: APIError? = nil,
    creationGate: PreparationAsyncGate? = nil
  ) throws -> PreparationFixture {
    try PreparationFixture(
      fetchEvents: fetchEvents,
      serverStepCount: serverStepCount,
      failOnDownloadCall: failOnDownloadCall,
      createError: createError,
      creationGate: creationGate
    )
  }

  private func readyLink(
    fixture: PreparationFixture,
    fingerprint: String,
    cachedRelativePath: String
  ) -> RoutineTTSLink {
    RoutineTTSLink(
      localRoutineID: fixture.routine.id,
      memberID: fixture.memberID,
      serverRoutineGroupID: fixture.routineGroupID,
      contentFingerprint: fingerprint,
      status: .ready,
      assets: [
        RoutineTTSAsset(
          localStepID: fixture.localStepID,
          serverRoutineID: 401,
          serverStepID: 501,
          orderIndex: 0,
          cachedRelativePath: cachedRelativePath
        ),
      ]
    )
  }
}

private enum PreparationFetchEvent: Sendable {
  case pending
  case completed
  case missing
  case failed
  case unknown
  case extraIdentifier
  case error(APIError)
}

@MainActor
private final class PreparationFixture {
  let memberID: Int64 = 17
  let routineGroupID: Int64 = 301
  let localStepID = UUID()
  let routine: Routine
  let modelContainer: ModelContainer
  let routineRepository: PreparationRoutineRepository
  let linkRepository: SwiftDataRoutineTTSLinkRepository
  let memberProvider: PreparationMemberProvider
  let remote: PreparationRemoteSpy
  let downloader: PreparationDownloaderSpy
  let sleeper = PreparationSleeperSpy()
  let audioFileStore: RoutineTTSAudioFileStore
  let coordinator: DefaultRoutineTTSPreparationCoordinator
  let temporaryDirectory: URL

  init(
    fetchEvents: [PreparationFetchEvent],
    serverStepCount: Int,
    failOnDownloadCall: Int?,
    createError: APIError?,
    creationGate: PreparationAsyncGate?
  ) throws {
    routine = Routine(
      name: "아침",
      steps: [
        RoutineStep(
          id: localStepID,
          type: .confirm,
          title: "물 마시기",
          order: 0,
          estimatedSeconds: 60
        ),
      ]
    )
    modelContainer = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    routineRepository = PreparationRoutineRepository(
      routines: [routine]
    )
    linkRepository = SwiftDataRoutineTTSLinkRepository(
      modelContext: modelContainer.mainContext
    )
    memberProvider = PreparationMemberProvider(memberID: memberID)
    remote = PreparationRemoteSpy(
      routineGroupID: routineGroupID,
      serverStepCount: serverStepCount,
      fetchEvents: fetchEvents,
      createError: createError,
      creationGate: creationGate
    )
    downloader = PreparationDownloaderSpy(
      failOnCall: failOnDownloadCall
    )
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "MoruPreparation-\(UUID().uuidString)",
        isDirectory: true
      )
    audioFileStore = RoutineTTSAudioFileStore(
      rootDirectory: temporaryDirectory
    )
    coordinator = DefaultRoutineTTSPreparationCoordinator(
      routineRepository: routineRepository,
      linkRepository: linkRepository,
      remoteService: remote,
      signedInMemberProvider: memberProvider,
      audioDownloader: downloader,
      audioFileStore: audioFileStore,
      sleeper: { [sleeper] duration in
        try await sleeper.sleep(duration)
      }
    )
  }

  func link() -> RoutineTTSLink? {
    try? linkRepository.link(
      localRoutineID: routine.id,
      memberID: memberID
    )
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }
}

@MainActor
private final class PreparationRoutineRepository: RoutineRepository {
  var routines: [Routine]

  init(routines: [Routine]) {
    self.routines = routines
  }

  func fetchRoutines() throws -> [Routine] {
    routines
  }

  func fetchActiveRoutines() throws -> [Routine] {
    routines.filter(\.isActive)
  }

  func routine(id: UUID) throws -> Routine? {
    routines.first { $0.id == id }
  }

  func saveRoutine(_ routine: Routine) throws {
    try saveRoutines([routine])
  }

  func saveRoutines(_ routines: [Routine]) throws {
    for routine in routines {
      if let index = self.routines.firstIndex(
        where: { $0.id == routine.id }
      ) {
        self.routines[index] = routine
      } else {
        self.routines.append(routine)
      }
    }
  }

  func updateRoutineActivation(
    id: UUID,
    isActive: Bool
  ) throws {
    guard let index = routines.firstIndex(
      where: { $0.id == id }
    ) else {
      return
    }
    routines[index].isActive = isActive
  }

  func deleteRoutine(id: UUID) throws {
    routines.removeAll { $0.id == id }
  }
}

@MainActor
private final class PreparationMemberProvider: SignedInMemberProviding {
  var memberID: Int64?

  init(memberID: Int64?) {
    self.memberID = memberID
  }

  var signedInMemberID: Int64? {
    memberID
  }
}

private actor PreparationRemoteSpy:
  AccountRoutineTTSRemoteServing {
  struct Snapshot: Sendable {
    let createCount: Int
    let fetchCount: Int
    let deletedRoutineGroupIDs: [Int64]
  }

  private let routineGroupID: Int64
  private let serverStepCount: Int
  private var fetchEvents: [PreparationFetchEvent]
  private let createError: APIError?
  private let creationGate: PreparationAsyncGate?
  private var createCount = 0
  private var fetchCount = 0
  private var deletedRoutineGroupIDs: [Int64] = []

  init(
    routineGroupID: Int64,
    serverStepCount: Int,
    fetchEvents: [PreparationFetchEvent],
    createError: APIError?,
    creationGate: PreparationAsyncGate?
  ) {
    self.routineGroupID = routineGroupID
    self.serverStepCount = serverStepCount
    self.fetchEvents = fetchEvents
    self.createError = createError
    self.creationGate = creationGate
  }

  func createRoutineGroup(
    _ request: ServerRoutineGroupCreationRequest,
    memberID _: Int64
  ) async throws -> ServerRoutineGroupCreationResult {
    createCount += 1
    if let creationGate {
      await creationGate.wait()
    }
    if let createError {
      throw createError
    }

    return ServerRoutineGroupCreationResult(
      localRoutineID: request.localRoutineID,
      routineGroupID: routineGroupID,
      routines: request.routines.enumerated().map { index, routine in
        ServerCreatedRoutine(
          localStepID: routine.localStepID,
          routineID: Int64(401 + index),
          title: routine.title,
          type: routine.type,
          durationSeconds: routine.durationSeconds,
          steps: (0..<serverStepCount).map { stepIndex in
            ServerCreatedRoutineStep(
              stepID: Int64(501 + (index * 100) + stepIndex),
              content: "step \(stepIndex)",
              orderIndex: stepIndex
            )
          }
        )
      }
    )
  }

  func deleteRoutineGroup(
    routineGroupID: Int64,
    memberID _: Int64
  ) async throws -> ServerRoutineGroupDeletionResult {
    deletedRoutineGroupIDs.append(routineGroupID)
    return ServerRoutineGroupDeletionResult(
      requestedRoutineGroupID: routineGroupID,
      serverAcknowledgedRoutineID: routineGroupID
    )
  }

  func fetchRoutineTTS(
    routineGroupID: Int64,
    memberID _: Int64
  ) async throws -> ServerRoutineTTSManifest {
    fetchCount += 1
    guard !fetchEvents.isEmpty else {
      throw APIError.invalidRequest("No scripted fetch response.")
    }
    let event = fetchEvents.removeFirst()
    if case .error(let error) = event {
      throw error
    }

    if case .missing = event {
      return ServerRoutineTTSManifest(
        routineGroupID: routineGroupID,
        routines: []
      )
    }

    let status: ServerRoutineTTSStatus
    switch event {
    case .pending:
      status = .pending
    case .completed, .extraIdentifier:
      status = .completed
    case .failed:
      status = .failed
    case .unknown:
      status = .unknown("PROCESSING")
    case .missing, .error:
      status = .pending
    }

    var routines = [
      ServerRoutineTTSItem(
        routineID: 401,
        title: "물 마시기",
        type: .check,
        steps: (0..<serverStepCount).map { stepIndex in
          ServerRoutineTTSStep(
            stepID: Int64(501 + stepIndex),
            content: "step \(stepIndex)",
            synthesizedIntro: nil,
            status: status,
            audioURL: status == .completed
              ? URL(
                string: "https://cdn.example.com/\(501 + stepIndex).mp3"
              )
              : nil
          )
        }
      ),
    ]
    if case .extraIdentifier = event {
      routines.append(
        ServerRoutineTTSItem(
          routineID: 999,
          title: "extra",
          type: .check,
          steps: [
            ServerRoutineTTSStep(
              stepID: 999,
              content: nil,
              synthesizedIntro: nil,
              status: .completed,
              audioURL: URL(
                string: "https://cdn.example.com/999.mp3"
              )
            ),
          ]
        )
      )
    }
    return ServerRoutineTTSManifest(
      routineGroupID: routineGroupID,
      routines: routines
    )
  }

  func snapshot() -> Snapshot {
    Snapshot(
      createCount: createCount,
      fetchCount: fetchCount,
      deletedRoutineGroupIDs: deletedRoutineGroupIDs
    )
  }
}

private actor PreparationDownloaderSpy:
  RoutineTTSAudioDownloading {
  private let failOnCall: Int?
  private var calls = 0

  init(failOnCall: Int?) {
    self.failOnCall = failOnCall
  }

  func downloadAudio(from _: URL) async throws -> Data {
    calls += 1
    if calls == failOnCall {
      throw RoutineTTSAudioDownloadError.httpStatus(500)
    }
    return Data([1, 2, 3])
  }

  func callCount() -> Int {
    calls
  }
}

private actor PreparationSleeperSpy {
  struct Snapshot: Sendable {
    let count: Int
  }

  private var durations: [Duration] = []

  func sleep(_ duration: Duration) async throws {
    durations.append(duration)
  }

  func snapshot() -> Snapshot {
    Snapshot(count: durations.count)
  }
}

private actor PreparationAsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pendingWaiters = waiters
    waiters.removeAll()
    pendingWaiters.forEach { $0.resume() }
  }
}
