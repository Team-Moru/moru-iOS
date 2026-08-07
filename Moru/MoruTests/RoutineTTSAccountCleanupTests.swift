//
//  RoutineTTSAccountCleanupTests.swift
//  MoruTests
//

import SwiftData
import XCTest

@testable import Moru

@MainActor
final class RoutineTTSAccountCleanupTests: XCTestCase {
  func testWithdrawalRemovesOnlyThatMembersLinksAndGeneratedAudio()
    async throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let cacheDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: cacheDirectory)
    }
    let fileStore = RoutineTTSAudioFileStore(
      rootDirectory: cacheDirectory
    )
    let withdrawnRoutineID = UUID()
    let retainedRoutineID = UUID()
    let withdrawnStepID = UUID()
    let retainedStepID = UUID()
    let withdrawnPath = try fileStore.store(
      Data([1]),
      localRoutineID: withdrawnRoutineID,
      localStepID: withdrawnStepID,
      serverStepID: 30
    )
    let retainedPath = try fileStore.store(
      Data([2]),
      localRoutineID: retainedRoutineID,
      localStepID: retainedStepID,
      serverStepID: 40
    )
    try repository.saveLink(
      readyLink(
        routineID: withdrawnRoutineID,
        stepID: withdrawnStepID,
        memberID: 7,
        serverGroupID: 10,
        serverRoutineID: 20,
        serverStepID: 30,
        path: withdrawnPath
      )
    )
    try repository.saveLink(
      readyLink(
        routineID: retainedRoutineID,
        stepID: retainedStepID,
        memberID: 8,
        serverGroupID: 11,
        serverRoutineID: 21,
        serverStepID: 40,
        path: retainedPath
      )
    )
    let cleaner = RoutineTTSAccountScopedDataCleaner(
      linkRepository: repository,
      audioFileStore: fileStore
    )

    try await cleaner.removeAccountScopedData(memberID: 7)

    XCTAssertNil(
      try repository.link(
        localRoutineID: withdrawnRoutineID,
        memberID: 7
      )
    )
    XCTAssertNotNil(
      try repository.link(
        localRoutineID: retainedRoutineID,
        memberID: 8
      )
    )
    XCTAssertNil(fileStore.cachedAudioURL(relativePath: withdrawnPath))
    XCTAssertNotNil(
      fileStore.cachedAudioURL(relativePath: retainedPath)
    )
  }

  func testWithdrawalRemovesCorruptLinksAndTheirGeneratedAudio()
    async throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let context = container.mainContext
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: context
    )
    let cacheDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: cacheDirectory)
    }
    let fileStore = RoutineTTSAudioFileStore(
      rootDirectory: cacheDirectory
    )
    let invalidStatusRoutineID = UUID()
    let invalidAssetsRoutineID = UUID()
    let invalidStatusPath = try fileStore.store(
      Data([1]),
      localRoutineID: invalidStatusRoutineID,
      localStepID: UUID(),
      serverStepID: 30
    )
    let invalidAssetsPath = try fileStore.store(
      Data([2]),
      localRoutineID: invalidAssetsRoutineID,
      localStepID: UUID(),
      serverStepID: 40
    )
    let now = Date()
    context.insert(
      PersistedRoutineTTSLink(
        localRoutineID: invalidStatusRoutineID,
        memberID: 7,
        serverRoutineGroupID: 10,
        contentFingerprint: "invalid-status",
        statusRawValue: "not-a-status",
        assetsRawValue: "[]",
        lastFailureCode: nil,
        createdAt: now,
        updatedAt: now
      )
    )
    context.insert(
      PersistedRoutineTTSLink(
        localRoutineID: invalidAssetsRoutineID,
        memberID: 7,
        serverRoutineGroupID: 11,
        contentFingerprint: "invalid-assets",
        statusRawValue: RoutineTTSLinkStatus.ready.rawValue,
        assetsRawValue: "{not-json",
        lastFailureCode: nil,
        createdAt: now,
        updatedAt: now
      )
    )
    try context.save()
    XCTAssertThrowsError(
      try repository.link(
        localRoutineID: invalidStatusRoutineID,
        memberID: 7
      )
    )
    XCTAssertThrowsError(
      try repository.link(
        localRoutineID: invalidAssetsRoutineID,
        memberID: 7
      )
    )
    let cleaner = RoutineTTSAccountScopedDataCleaner(
      linkRepository: repository,
      audioFileStore: fileStore
    )

    try await cleaner.removeAccountScopedData(memberID: 7)

    XCTAssertNil(fileStore.cachedAudioURL(relativePath: invalidStatusPath))
    XCTAssertNil(fileStore.cachedAudioURL(relativePath: invalidAssetsPath))
    XCTAssertTrue(
      try context.fetch(
        FetchDescriptor<PersistedRoutineTTSLink>()
      ).isEmpty
    )
  }

  func testWithdrawalContinuesAfterFileRemovalFailureAndDeletesLinks()
    async throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let failingRoutineID = try XCTUnwrap(
      UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    )
    let successfulRoutineID = try XCTUnwrap(
      UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
    )
    try repository.saveLink(
      readyLink(
        routineID: failingRoutineID,
        stepID: UUID(),
        memberID: 7,
        serverGroupID: 10,
        serverRoutineID: 20,
        serverStepID: 30,
        path: "first/30.mp3"
      )
    )
    try repository.saveLink(
      readyLink(
        routineID: successfulRoutineID,
        stepID: UUID(),
        memberID: 7,
        serverGroupID: 11,
        serverRoutineID: 21,
        serverStepID: 40,
        path: "second/40.mp3"
      )
    )
    var attemptedRoutineIDs: [UUID] = []
    let cleaner = RoutineTTSAccountScopedDataCleaner(
      linkRepository: repository,
      removeAudioAssets: { localRoutineID in
        attemptedRoutineIDs.append(localRoutineID)
        if localRoutineID == failingRoutineID {
          throw RoutineTTSAccountCleanupTestError.fileRemovalFailed
        }
      }
    )

    do {
      try await cleaner.removeAccountScopedData(memberID: 7)
      XCTFail("Expected the first file removal error.")
    } catch {
      XCTAssertEqual(
        error as? RoutineTTSAccountCleanupTestError,
        .fileRemovalFailed
      )
    }

    XCTAssertEqual(
      attemptedRoutineIDs,
      [failingRoutineID, successfulRoutineID]
    )
    XCTAssertTrue(
      try repository.localRoutineIDs(memberID: 7).isEmpty
    )
  }

  func testInvalidMemberIDCannotDeleteAccountData() async throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let cleaner = RoutineTTSAccountScopedDataCleaner(
      linkRepository: SwiftDataRoutineTTSLinkRepository(
        modelContext: container.mainContext
      ),
      audioFileStore: RoutineTTSAudioFileStore(
        rootDirectory: FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
      )
    )

    do {
      try await cleaner.removeAccountScopedData(memberID: 0)
      XCTFail("Expected an invalid member ID.")
    } catch let error as RoutineTTSAccountCleanupError {
      XCTAssertEqual(error, .invalidMemberID)
    }
  }

  func testWithdrawalCancelsPreparationBeforeReadingLinks()
    async throws {
    let recorder = RoutineTTSAccountCleanupEventRecorder()
    let repository = RecordingRoutineTTSLinkRepository(
      recorder: recorder
    )
    let scheduler = RecordingRoutineTTSPreparationScheduler(
      recorder: recorder
    )
    let cleaner = RoutineTTSAccountScopedDataCleaner(
      linkRepository: repository,
      removeAudioAssets: { _ in },
      preparationScheduler: scheduler
    )

    try await cleaner.removeAccountScopedData(memberID: 7)

    XCTAssertEqual(
      recorder.events,
      ["cancel preparations", "read links", "delete links"]
    )
  }

  private func readyLink(
    routineID: UUID,
    stepID: UUID,
    memberID: Int64,
    serverGroupID: Int64,
    serverRoutineID: Int64,
    serverStepID: Int64,
    path: String
  ) -> RoutineTTSLink {
    RoutineTTSLink(
      localRoutineID: routineID,
      memberID: memberID,
      serverRoutineGroupID: serverGroupID,
      contentFingerprint: "fingerprint-\(routineID)",
      status: .ready,
      assets: [
        RoutineTTSAsset(
          localStepID: stepID,
          serverRoutineID: serverRoutineID,
          serverStepID: serverStepID,
          orderIndex: 0,
          cachedRelativePath: path
        ),
      ]
    )
  }
}

private enum RoutineTTSAccountCleanupTestError: Error, Equatable {
  case fileRemovalFailed
}

@MainActor
private final class RoutineTTSAccountCleanupEventRecorder {
  var events: [String] = []
}

@MainActor
private final class RecordingRoutineTTSPreparationScheduler:
  RoutineTTSPreparationScheduling {
  private let recorder: RoutineTTSAccountCleanupEventRecorder

  init(recorder: RoutineTTSAccountCleanupEventRecorder) {
    self.recorder = recorder
  }

  func routineDidSave(_: Routine) {}

  func routineDidDelete(localRoutineID _: UUID) {}

  func cancelAllPreparations() {
    recorder.events.append("cancel preparations")
  }
}

@MainActor
private final class RecordingRoutineTTSLinkRepository:
  RoutineTTSLinkRepository {
  private let recorder: RoutineTTSAccountCleanupEventRecorder

  init(recorder: RoutineTTSAccountCleanupEventRecorder) {
    self.recorder = recorder
  }

  func link(
    localRoutineID _: UUID,
    memberID _: Int64
  ) throws -> RoutineTTSLink? {
    nil
  }

  func localRoutineIDs(memberID _: Int64) throws -> [UUID] {
    recorder.events.append("read links")
    return []
  }

  func saveLink(_: RoutineTTSLink) throws {}

  func deleteLink(localRoutineID _: UUID) throws {}

  func deleteLinks(memberID _: Int64) throws {
    recorder.events.append("delete links")
  }

  func deleteAllLinks() throws {}
}
