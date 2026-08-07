//
//  RoutineTTSLinkPersistenceTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class RoutineTTSLinkPersistenceTests: XCTestCase {
  @MainActor
  func testRepositoryRoundTripPreservesOneToManyAssetManifest() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let localRoutineID = UUID()
    let firstLocalStepID = UUID()
    let secondLocalStepID = UUID()
    let link = makeReadyLink(
      localRoutineID: localRoutineID,
      memberID: 17,
      serverRoutineGroupID: 701,
      assets: [
        RoutineTTSAsset(
          localStepID: firstLocalStepID,
          serverRoutineID: 801,
          serverStepID: 901,
          orderIndex: 0,
          cachedRelativePath: "17/\(localRoutineID)/901.mp3"
        ),
        RoutineTTSAsset(
          localStepID: firstLocalStepID,
          serverRoutineID: 801,
          serverStepID: 902,
          orderIndex: 1,
          cachedRelativePath: "17/\(localRoutineID)/902.mp3"
        ),
        RoutineTTSAsset(
          localStepID: secondLocalStepID,
          serverRoutineID: 802,
          serverStepID: 903,
          orderIndex: 0,
          cachedRelativePath: "17/\(localRoutineID)/903.mp3"
        ),
      ]
    )

    try repository.saveLink(link)

    let fetched = try XCTUnwrap(
      try repository.link(
        localRoutineID: localRoutineID,
        memberID: 17
      )
    )
    XCTAssertEqual(fetched, link)
    XCTAssertEqual(
      fetched.assets.map(\.serverStepID),
      [901, 902, 903]
    )
    XCTAssertEqual(
      fetched.assets.map(\.orderIndex),
      [0, 1, 0]
    )
  }

  @MainActor
  func testRepositoryIsolatesLinksByCurrentMemberAndReplacesOwnerOnUpsert()
    throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let context = container.mainContext
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: context
    )
    let localRoutineID = UUID()
    var link = makeReadyLink(
      localRoutineID: localRoutineID,
      memberID: 11,
      serverRoutineGroupID: 101
    )
    try repository.saveLink(link)

    XCTAssertNil(
      try repository.link(
        localRoutineID: localRoutineID,
        memberID: 12
      )
    )

    link.memberID = 12
    link.serverRoutineGroupID = 102
    link.updatedAt = Date(timeIntervalSince1970: 300)
    try repository.saveLink(link)

    XCTAssertNil(
      try repository.link(
        localRoutineID: localRoutineID,
        memberID: 11
      )
    )
    XCTAssertEqual(
      try repository.link(
        localRoutineID: localRoutineID,
        memberID: 12
      )?.serverRoutineGroupID,
      102
    )
    XCTAssertEqual(
      try context.fetch(
        FetchDescriptor<PersistedRoutineTTSLink>()
      ).count,
      1
    )
  }

  @MainActor
  func testRepositoryRejectsMalformedPersistedManifest() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let context = container.mainContext
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: context
    )
    let localRoutineID = UUID()
    context.insert(
      PersistedRoutineTTSLink(
        localRoutineID: localRoutineID,
        memberID: 21,
        serverRoutineGroupID: 301,
        contentFingerprint: "fingerprint",
        statusRawValue: RoutineTTSLinkStatus.failed.rawValue,
        assetsRawValue: "{not-json}",
        lastFailureCode: "invalid-response",
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
      )
    )
    try context.save()

    XCTAssertThrowsError(
      try repository.link(
        localRoutineID: localRoutineID,
        memberID: 21
      )
    ) {
      XCTAssertEqual(
        $0 as? RoutineTTSLinkRepositoryError,
        .invalidManifest
      )
    }
  }

  @MainActor
  func testRepositoryRejectsSemanticallyInvalidAssetManifest() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let localStepID = UUID()
    let link = RoutineTTSLink(
      localRoutineID: UUID(),
      memberID: 22,
      serverRoutineGroupID: 401,
      contentFingerprint: "fingerprint",
      status: .failed,
      assets: [
        RoutineTTSAsset(
          localStepID: localStepID,
          serverRoutineID: 501,
          serverStepID: 601,
          orderIndex: 0
        ),
        RoutineTTSAsset(
          localStepID: localStepID,
          serverRoutineID: 502,
          serverStepID: 602,
          orderIndex: 1
        ),
      ]
    )

    XCTAssertThrowsError(try repository.saveLink(link)) {
      XCTAssertEqual(
        $0 as? RoutineTTSLinkRepositoryError,
        .invalidLink(
          .inconsistentServerRoutineMapping(
            localStepID: localStepID
          )
        )
      )
    }
  }

  @MainActor
  func testRepositoryRejectsUnsafeCachedRelativePath() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let path = "../outside.mp3"
    let link = makeReadyLink(
      localRoutineID: UUID(),
      memberID: 23,
      serverRoutineGroupID: 402,
      cachedRelativePath: path
    )

    XCTAssertThrowsError(try repository.saveLink(link)) {
      XCTAssertEqual(
        $0 as? RoutineTTSLinkRepositoryError,
        .invalidLink(.invalidCachedRelativePath(path))
      )
    }
  }

  @MainActor
  func testRepositoryDeletesOnlyRequestedMembersLinks() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let firstRoutineID = UUID()
    let secondRoutineID = UUID()
    try repository.saveLink(
      makeReadyLink(
        localRoutineID: firstRoutineID,
        memberID: 31,
        serverRoutineGroupID: 601
      )
    )
    try repository.saveLink(
      makeReadyLink(
        localRoutineID: secondRoutineID,
        memberID: 32,
        serverRoutineGroupID: 602
      )
    )

    XCTAssertEqual(
      try repository.localRoutineIDs(memberID: 31),
      [firstRoutineID]
    )
    XCTAssertEqual(
      try repository.localRoutineIDs(memberID: 32),
      [secondRoutineID]
    )

    try repository.deleteLinks(memberID: 31)

    XCTAssertNil(
      try repository.link(
        localRoutineID: firstRoutineID,
        memberID: 31
      )
    )
    XCTAssertNotNil(
      try repository.link(
        localRoutineID: secondRoutineID,
        memberID: 32
      )
    )
  }

  @MainActor
  func testFreshInstallResetDeletesTTSLinks() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let context = container.mainContext
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: context
    )
    try repository.saveLink(
      makeReadyLink(
        localRoutineID: UUID(),
        memberID: 41,
        serverRoutineGroupID: 801
      )
    )

    try SwiftDataLocalDataResetRepository(
      modelContext: context
    ).resetToFreshInstallState()

    XCTAssertTrue(
      try context.fetch(
        FetchDescriptor<PersistedRoutineTTSLink>()
      ).isEmpty
    )
  }

  @MainActor
  func testDiskBackedV3StoreMigratesToV4WithoutLosingRoutine() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "MoruRoutineTTSMigration-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let storeURL = temporaryDirectory.appendingPathComponent("Moru.store")
    let routine = Routine(
      name: "기존 로컬 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 마시기",
          order: 0
        ),
      ]
    )

    do {
      let schema = Schema(versionedSchema: MoruSchemaV3.self)
      let configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(
        for: schema,
        configurations: [configuration]
      )
      container.mainContext.insert(
        SwiftDataMapper.makePersistedRoutine(from: routine)
      )
      try container.mainContext.save()
    }

    let migratedContainer = try ModelContainer.moruContainer(
      storeURL: storeURL
    )
    let context = migratedContainer.mainContext
    let routineRepository = SwiftDataRoutineRepository(
      modelContext: context
    )

    XCTAssertEqual(
      try routineRepository.routine(id: routine.id)?.name,
      "기존 로컬 루틴"
    )
    XCTAssertTrue(
      try context.fetch(
        FetchDescriptor<PersistedRoutineTTSLink>()
      ).isEmpty
    )
  }

  @MainActor
  private func makeReadyLink(
    localRoutineID: UUID,
    memberID: Int64,
    serverRoutineGroupID: Int64,
    cachedRelativePath: String = "member/routine/step.mp3"
  ) -> RoutineTTSLink {
    makeReadyLink(
      localRoutineID: localRoutineID,
      memberID: memberID,
      serverRoutineGroupID: serverRoutineGroupID,
      assets: [
        RoutineTTSAsset(
          localStepID: UUID(),
          serverRoutineID: serverRoutineGroupID + 100,
          serverStepID: serverRoutineGroupID + 200,
          orderIndex: 0,
          cachedRelativePath: cachedRelativePath
        ),
      ]
    )
  }

  @MainActor
  private func makeReadyLink(
    localRoutineID: UUID,
    memberID: Int64,
    serverRoutineGroupID: Int64,
    assets: [RoutineTTSAsset]
  ) -> RoutineTTSLink {
    RoutineTTSLink(
      localRoutineID: localRoutineID,
      memberID: memberID,
      serverRoutineGroupID: serverRoutineGroupID,
      contentFingerprint: "sha256:test",
      status: .ready,
      assets: assets,
      createdAt: Date(timeIntervalSince1970: 100),
      updatedAt: Date(timeIntervalSince1970: 200)
    )
  }
}
