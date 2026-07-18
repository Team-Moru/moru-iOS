//
//  LocalResetCoordinatorTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

@MainActor
final class LocalResetCoordinatorTests: XCTestCase {
  func testNormalResetCancelsSealedInventoryBeforeDeletingAndCompletes() async throws {
    let fixture = makeFixture(inventory: [uuid(2), uuid(1), uuid(2)])
    defer { removeFixture(fixture) }

    let operationID = try await fixture.coordinator.reset()

    XCTAssertEqual(
      fixture.log.events,
      ["freeze", "inventory", "cancel", "delete", "clear", "thaw"]
    )
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(1), uuid(2)]])
    XCTAssertEqual(fixture.mutator.cancelledTokens, fixture.mutator.freezeTokens)
    XCTAssertEqual(fixture.mutator.thawedTokens, fixture.mutator.freezeTokens)
    XCTAssertEqual(fixture.repository.deleteCallCount, 1)
    XCTAssertEqual(fixture.clearSpy.callCount, 1)
    XCTAssertEqual(fixture.clearSpy.operationIDs, [operationID])
    XCTAssertEqual(try fixture.journalStore.load()?.phase, .completed)
    XCTAssertEqual(try fixture.journalStore.load()?.sealedScheduleIDs, [uuid(1), uuid(2)])
    XCTAssertEqual(try fixture.journalStore.currentGeneration(), 2)
  }
  func testFreshJournalStartsAtOneAndFirstResetAdvancesToTwo() throws {
    let fixture = makeJournalFixture()
    defer { removeJournalFixture(fixture) }

    XCTAssertEqual(try fixture.store.currentGeneration(), 1)
    let entry = try fixture.store.begin(operationID: uuid(12), at: fixture.date)
    XCTAssertEqual(entry.generation, 2)
    XCTAssertEqual(try fixture.store.currentGeneration(), 2)
  }

  func testGenerationOverflowIsRejectedBeforeReplacingCompletedJournal() throws {
    let fixture = makeJournalFixture()
    defer { removeJournalFixture(fixture) }
    try writeJournal(
      LocalResetJournalEntry(
        operationID: uuid(10),
        revision: 1,
        generation: .max,
        phase: .completed,
        createdAt: fixture.date,
        updatedAt: fixture.date
      ),
      to: fixture.fileURL
    )

    XCTAssertThrowsError(
      try fixture.store.begin(operationID: uuid(11), at: fixture.date)
    ) { error in
      XCTAssertEqual(error as? LocalResetJournalStoreError, .generationOverflow)
    }
    XCTAssertEqual(try fixture.store.load()?.generation, .max)
  }

  func testRevisionOverflowIsRejectedBeforeReplacingCompletedJournal() throws {
    let fixture = makeJournalFixture()
    defer { removeJournalFixture(fixture) }
    try writeJournal(
      LocalResetJournalEntry(
        operationID: uuid(10),
        revision: .max,
        generation: 1,
        phase: .completed,
        createdAt: fixture.date,
        updatedAt: fixture.date
      ),
      to: fixture.fileURL
    )

    XCTAssertThrowsError(
      try fixture.store.begin(operationID: uuid(11), at: fixture.date)
    ) { error in
      XCTAssertEqual(error as? LocalResetJournalStoreError, .revisionOverflow)
    }
    XCTAssertEqual(try fixture.store.load()?.revision, .max)
  }

  func testRetryAfterCrashBeforeSealRegathersInventory() async throws {
    let fixture = makeFixture(inventory: [uuid(3)])
    defer { removeFixture(fixture) }
    let operationID = uuid(20)
    _ = try fixture.journalStore.begin(operationID: operationID, at: fixture.date)
    _ = try fixture.journalStore.advance(
      operationID: operationID,
      to: .gathering,
      at: fixture.date
    )

    try await fixture.coordinator.reset()

    XCTAssertEqual(fixture.repository.inventoryCallCount, 1)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(3)]])
    XCTAssertEqual(try fixture.journalStore.load()?.phase, .completed)
  }
  func testPreSealFailureRegathersOnRetry() async throws {
    let fixture = makeFixture(inventory: [uuid(3)])
    defer { removeFixture(fixture) }
    fixture.repository.failInventoryCount = 1

    do {
      try await fixture.coordinator.reset()
      XCTFail("Expected schedule inventory to fail.")
    } catch let error as LocalResetCoordinatorError {
      guard case .inventory = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    XCTAssertEqual(try fixture.journalStore.load()?.resumePhase, .gathering)
    XCTAssertEqual(fixture.repository.inventoryCallCount, 1)
    XCTAssertTrue(fixture.mutator.cancelledScheduleIDs.isEmpty)

    try await fixture.coordinator.reset()

    XCTAssertEqual(fixture.repository.inventoryCallCount, 2)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(3)]])
  }

  func testRetryAfterSealReusesExactInventoryWithoutRegathering() async throws {
    let fixture = makeFixture(inventory: [uuid(99)])
    defer { removeFixture(fixture) }
    let operationID = uuid(21)
    _ = try fixture.journalStore.begin(operationID: operationID, at: fixture.date)
    _ = try fixture.journalStore.advance(
      operationID: operationID,
      to: .gathering,
      at: fixture.date
    )
    _ = try fixture.journalStore.seal(
      operationID: operationID,
      scheduleIDs: [uuid(5), uuid(4), uuid(5)],
      at: fixture.date
    )

    try await fixture.coordinator.reset()

    XCTAssertEqual(fixture.repository.inventoryCallCount, 0)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(4), uuid(5)]])
    XCTAssertEqual(try fixture.journalStore.load()?.sealedScheduleIDs, [uuid(4), uuid(5)])
  }

  func testCancellationFailurePersistsRetryAndDoesNotDeleteBeforeRetry() async throws {
    let fixture = makeFixture(inventory: [uuid(6)])
    defer { removeFixture(fixture) }
    fixture.mutator.failCancellationCount = 1

    do {
      try await fixture.coordinator.reset()
      XCTFail("Expected notification cancellation to fail.")
    } catch let error as LocalResetCoordinatorError {
      guard case .cancellation = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    let retry = try XCTUnwrap(try fixture.journalStore.load())
    XCTAssertEqual(retry.phase, .retryRequired)
    XCTAssertEqual(retry.resumePhase, .cancelling)
    XCTAssertEqual(fixture.repository.deleteCallCount, 0)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(6)]])

    try await fixture.coordinator.reset()

    XCTAssertEqual(fixture.repository.inventoryCallCount, 1)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(6)], [uuid(6)]])
    XCTAssertEqual(fixture.repository.deleteCallCount, 1)
    XCTAssertEqual(try fixture.journalStore.load()?.phase, .completed)
  }

  func testDeleteFailureResumesAtDeleteWithoutRepeatingCancellation() async throws {
    let fixture = makeFixture(inventory: [uuid(7)])
    defer { removeFixture(fixture) }
    fixture.repository.failDeleteCount = 1

    do {
      try await fixture.coordinator.reset()
      XCTFail("Expected local data deletion to fail.")
    } catch let error as LocalResetCoordinatorError {
      guard case .deletion = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    XCTAssertEqual(try fixture.journalStore.load()?.resumePhase, .swiftDataDeleting)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(7)]])
    XCTAssertEqual(fixture.repository.deleteCallCount, 1)

    try await fixture.coordinator.reset()

    XCTAssertEqual(fixture.repository.inventoryCallCount, 1)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(7)]])
    XCTAssertEqual(fixture.repository.deleteCallCount, 2)
    XCTAssertEqual(fixture.clearSpy.callCount, 1)
  }

  func testClearFailureResumesAtClearWithoutRepeatingDelete() async throws {
    let fixture = makeFixture(inventory: [uuid(8)])
    defer { removeFixture(fixture) }
    fixture.clearSpy.failClearCount = 1

    do {
      try await fixture.coordinator.reset()
      XCTFail("Expected coordinator clear to fail.")
    } catch let error as LocalResetCoordinatorError {
      guard case .coordinatorClear = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    XCTAssertEqual(try fixture.journalStore.load()?.resumePhase, .coordinatorClearing)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(8)]])
    XCTAssertEqual(fixture.repository.deleteCallCount, 1)
    XCTAssertEqual(fixture.clearSpy.callCount, 1)

    try await fixture.coordinator.reset()

    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(8)]])
    XCTAssertEqual(fixture.repository.deleteCallCount, 1)
    XCTAssertEqual(fixture.clearSpy.callCount, 2)
    XCTAssertEqual(fixture.clearSpy.operationIDs, [uuid(100), uuid(100)])
    XCTAssertEqual(try fixture.journalStore.load()?.phase, .completed)
  }

  func testDuplicateConcurrentResetSharesOneNonterminalOperation() async throws {
    let fixture = makeFixture(inventory: [uuid(9)])
    defer { removeFixture(fixture) }
    fixture.mutator.pauseCancellation = true

    let firstReset = Task { try await fixture.coordinator.reset() }
    while fixture.mutator.cancelledScheduleIDs.isEmpty {
      await Task.yield()
    }
    let secondReset = Task { try await fixture.coordinator.reset() }
    await Task.yield()

    XCTAssertEqual(fixture.repository.inventoryCallCount, 1)
    XCTAssertEqual(fixture.mutator.cancelledScheduleIDs, [[uuid(9)]])
    XCTAssertEqual(fixture.mutator.freezeTokens.count, 1)
    XCTAssertTrue(fixture.mutator.thawedTokens.isEmpty)

    fixture.mutator.finishCancellation()
    _ = try await firstReset.value
    _ = try await secondReset.value

    XCTAssertEqual(fixture.repository.deleteCallCount, 1)
    XCTAssertEqual(fixture.clearSpy.callCount, 1)
    XCTAssertEqual(fixture.mutator.thawedTokens, fixture.mutator.freezeTokens)
  }
  func testRevisionOverflowPreflightPreventsDestructiveResetSideEffects() async throws {
    for phase in [
      LocalResetJournalPhase.sealed,
      .cancelling,
      .swiftDataDeleting,
      .coordinatorClearing
    ] {
      try await assertRevisionOverflowPreventsDestructiveResetSideEffects(for: phase)
    }
  }

  func testNewJournalDirectorySynchronizesParentBeforeWritingAndChildAfterReplace() throws {
    let synchronizer = JournalSynchronizerSpy()
    let fixture = makeJournalFixture(synchronizer: synchronizer)
    defer { removeJournalFixture(fixture) }

    let entry = try fixture.store.begin(operationID: uuid(50), at: fixture.date)
    _ = try fixture.store.advance(
      operationID: entry.operationID,
      to: .gathering,
      at: fixture.date
    )

    XCTAssertEqual(
      try XCTUnwrap(synchronizer.calls.first),
      JournalSynchronizationCall(
        url: fixture.directoryURL.deletingLastPathComponent(),
        isDirectory: true
      )
    )
    XCTAssertEqual(synchronizer.calls.count, 5)
    XCTAssertFalse(synchronizer.calls[1].isDirectory)
    XCTAssertFalse(synchronizer.calls[3].isDirectory)
    XCTAssertEqual(
      try XCTUnwrap(synchronizer.calls.last),
      JournalSynchronizationCall(url: fixture.directoryURL, isDirectory: true)
    )
  }

  func testNewJournalDirectoryParentSynchronizationFailurePreventsWriting() throws {
    let synchronizer = JournalSynchronizerSpy()
    synchronizer.failOnNextSynchronization = true
    let fixture = makeJournalFixture(synchronizer: synchronizer)
    defer { removeJournalFixture(fixture) }

    XCTAssertThrowsError(try fixture.store.begin(operationID: uuid(51), at: fixture.date)) {
      error in
      guard case .writeFailed = error as? LocalResetJournalStoreError else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    XCTAssertEqual(
      synchronizer.calls,
      [
        JournalSynchronizationCall(
          url: fixture.directoryURL.deletingLastPathComponent(),
          isDirectory: true
        )
      ]
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  }

  private func assertRevisionOverflowPreventsDestructiveResetSideEffects(
    for phase: LocalResetJournalPhase
  ) async throws {
    let fixture = makeFixture(inventory: [uuid(60)])
    defer { removeFixture(fixture) }
    let operationID = uuid(61)
    try writeJournal(
      LocalResetJournalEntry(
        operationID: operationID,
        revision: .max,
        generation: 2,
        phase: phase,
        sealedScheduleIDs: [uuid(60)],
        createdAt: fixture.date,
        updatedAt: fixture.date
      ),
      to: fixture.journalFileURL
    )

    do {
      try await fixture.coordinator.reset()
      XCTFail("Expected revision overflow before \(phase.rawValue).")
    } catch let error as LocalResetCoordinatorError {
      guard case .journal(.revisionOverflow) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    XCTAssertEqual(fixture.log.events, ["freeze", "thaw"])
    XCTAssertTrue(fixture.mutator.cancelledScheduleIDs.isEmpty)
    XCTAssertEqual(fixture.repository.deleteCallCount, 0)
    XCTAssertEqual(fixture.clearSpy.callCount, 0)
  }


  func testCorruptJournalIsRejected() throws {
    let fixture = makeJournalFixture()
    defer { removeJournalFixture(fixture) }
    try FileManager.default.createDirectory(
      at: fixture.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not-a-journal".utf8).write(to: fixture.fileURL)

    XCTAssertThrowsError(try fixture.store.load()) { error in
      guard case .corrupt = error as? LocalResetJournalStoreError else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testSwiftDataRepositoryInventoriesRoutineAndPlatformIDsAndDeletesAllModels() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_000)
    let routineID = uuid(30)
    let routineScheduleID = uuid(31)
    let platformScheduleID = uuid(32)
    let step = PersistedRoutineStep(
      id: uuid(33),
      presetItemID: nil,
      typeRawValue: RoutineStepType.confirm.rawValue,
      title: "Wake",
      instruction: "Wake up",
      order: 0,
      estimatedSeconds: nil,
      isRequired: true
    )
    let schedule = PersistedAlarmSchedule(
      id: routineScheduleID,
      hour: 7,
      minute: 0,
      weekdaysRawValue: "[2]",
      soundName: "moru-default",
      isEnabled: true,
      includeWeather: false,
      includeFortune: false
    )
    let routine = PersistedRoutine(
      id: routineID,
      name: "Morning",
      summary: "Morning routine",
      goalTagsRawValue: "[]",
      steps: [step],
      alarmSchedule: schedule,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
    let run = PersistedRoutineRun(
      id: uuid(34),
      routineID: routineID,
      routineName: "Morning",
      startedAt: now,
      completedAt: nil,
      results: [
        PersistedRoutineStepResult(
          id: uuid(35),
          stepID: step.id,
          stepTitle: step.title,
          stepTypeRawValue: RoutineStepType.confirm.rawValue,
          completedAt: nil,
          skipped: false,
          inputText: nil,
          transcript: nil,
          durationSeconds: nil
        )
      ],
      plannedSteps: [
        PersistedRoutineStepSnapshot(
          id: uuid(36),
          stepID: step.id,
          stepTitle: step.title,
          stepTypeRawValue: RoutineStepType.confirm.rawValue,
          stepOrder: 0,
          estimatedSeconds: nil,
          isRequired: true
        )
      ],
      endedEarly: false,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
    context.insert(routine)
    context.insert(run)
    context.insert(PersistedLocalProfile(
      id: uuid(37),
      displayName: "Moru",
      selectedVoiceID: VoiceProfile.moru.id,
      createdAt: now,
      updatedAt: now
    ))
    context.insert(PersistedScheduledAlarmStartObservation(
      id: uuid(38),
      occurrenceID: "occurrence-38",
      rootOccurrenceID: "root-38",
      parentOccurrenceID: nil,
      routineID: routineID,
      scheduleID: routineScheduleID,
      actionObservedAt: now,
      scheduledFireAt: now,
      resetGeneration: 1,
      sourceRawValue: ScheduledAlarmObservationSource.alarmKitOccurrenceActionV1.rawValue,
      immutableFingerprint: String(repeating: "a", count: 64),
      timeZoneIdentifier: "Asia/Seoul",
      utcOffsetSeconds: 32_400,
      localGregorianDayKey: "2026-07-18",
      localGregorianDayOrdinal: 199,
      localMinute: 420,
      receivedAt: now
    ))
    context.insert(PersistedHomeWeatherSnapshot(
      id: uuid(39),
      conditionRawValue: HomeWeatherCondition.clear.rawValue,
      temperatureCelsius: 20,
      latitudeE4: 0,
      longitudeE4: 0,
      fetchedAt: now,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    ))
    context.insert(PersistedLocalSettings(id: uuid(40), profileID: uuid(37)))
    context.insert(PersistedAlarmRootChainState(
      id: uuid(41),
      rootOccurrenceID: "root-41",
      routineID: routineID,
      scheduleID: routineScheduleID,
      resetGeneration: 1,
      rootFingerprint: String(repeating: "b", count: 64),
      earliestObservedOccurrenceID: nil,
      earliestObservedAt: nil,
      latestObservedOccurrenceID: nil,
      latestObservedAt: nil,
      terminalOccurrenceID: nil,
      terminalAt: nil,
      updatedAt: now
    ))
    context.insert(PersistedAlarmPlatformState(
      id: uuid(42),
      scheduleID: platformScheduleID,
      routineID: routineID,
      desiredScheduleFingerprint: String(repeating: "c", count: 64),
      platformRequestID: uuid(43),
      stateRawValue: AlarmPlatformState.configured.rawValue,
      updatedAt: now,
      lastErrorCode: nil
    ))
    try context.save()

    let repository = SwiftDataLocalResetRepository(modelContext: context)
    let expectedScheduleIDs = [routineScheduleID, platformScheduleID].sorted {
      $0.uuidString.lowercased().utf8.lexicographicallyPrecedes(
        $1.uuidString.lowercased().utf8
      )
    }
    XCTAssertEqual(try repository.inventoryScheduleIDs(), expectedScheduleIDs)

    try repository.deleteAll()

    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedRoutine>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedRoutineStep>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedAlarmSchedule>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedRoutineRun>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedRoutineStepResult>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedRoutineStepSnapshot>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedLocalProfile>()).isEmpty)
    XCTAssertTrue(
      try context.fetch(
        FetchDescriptor<PersistedScheduledAlarmStartObservation>()
      ).isEmpty
    )
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedLocalSettings>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedAlarmRootChainState>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedAlarmPlatformState>()).isEmpty)
  }
  func testAggregatePlatformFetchRejectsDuplicateScheduleIDs() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let scheduleID = uuid(70)
    let repository = SwiftDataAlarmPlatformStateRepository(modelContext: context)

    context.insert(
      PersistedAlarmPlatformState(
        id: uuid(71),
        scheduleID: scheduleID,
        routineID: uuid(72),
        desiredScheduleFingerprint: String(repeating: "a", count: 64),
        platformRequestID: uuid(73),
        stateRawValue: AlarmPlatformState.configured.rawValue,
        updatedAt: Date(timeIntervalSince1970: 1_000),
        lastErrorCode: nil
      )
    )
    context.insert(
      PersistedAlarmPlatformState(
        id: uuid(74),
        scheduleID: scheduleID,
        routineID: uuid(75),
        desiredScheduleFingerprint: String(repeating: "b", count: 64),
        platformRequestID: uuid(76),
        stateRawValue: AlarmPlatformState.configured.rawValue,
        updatedAt: Date(timeIntervalSince1970: 1_001),
        lastErrorCode: nil
      )
    )

    XCTAssertThrowsError(try repository.fetchAll()) { error in
      XCTAssertEqual(
        error as? AlarmPlatformStateRepositoryError,
        .duplicateSchedule(scheduleID)
      )
    }
  }
  func testPointFetchAndSaveRejectDuplicatePlatformRowsWithoutOverwrite() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let scheduleID = uuid(77)
    let repository = SwiftDataAlarmPlatformStateRepository(modelContext: context)

    for index in 0..<2 {
      context.insert(
        PersistedAlarmPlatformState(
          id: uuid(UInt8(78 + index)),
          scheduleID: scheduleID,
          routineID: uuid(UInt8(80 + index)),
          desiredScheduleFingerprint: String(repeating: "c", count: 64),
          platformRequestID: uuid(UInt8(82 + index)),
          stateRawValue: AlarmPlatformState.configured.rawValue,
          updatedAt: Date(timeIntervalSince1970: 2_000 + Double(index)),
          lastErrorCode: nil
        )
      )
    }

    XCTAssertThrowsError(try repository.fetch(scheduleID: scheduleID)) { error in
      XCTAssertEqual(
        error as? AlarmPlatformStateRepositoryError,
        .duplicateSchedule(scheduleID)
      )
    }

    let incoming = AlarmPlatformSnapshot(
      id: uuid(84),
      scheduleID: scheduleID,
      routineID: uuid(85),
      desiredScheduleFingerprint: String(repeating: "d", count: 64),
      platformRequestID: uuid(86),
      state: .configured,
      updatedAt: Date(timeIntervalSince1970: 2_100),
      lastErrorCode: nil
    )
    XCTAssertThrowsError(try repository.save(incoming)) { error in
      XCTAssertEqual(
        error as? AlarmPlatformStateRepositoryError,
        .duplicateSchedule(scheduleID)
      )
    }

    let persistedRows = try context.fetch(
      FetchDescriptor<PersistedAlarmPlatformState>()
    )
    XCTAssertEqual(persistedRows.count, 2)
  }

  func testPlatformSaveRejectsConflictingIdentityAndRoutineOwnership() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let scheduleID = uuid(87)
    let persistedID = uuid(88)
    let routineID = uuid(89)
    let repository = SwiftDataAlarmPlatformStateRepository(modelContext: context)
    context.insert(
      PersistedAlarmPlatformState(
        id: persistedID,
        scheduleID: scheduleID,
        routineID: routineID,
        desiredScheduleFingerprint: String(repeating: "e", count: 64),
        platformRequestID: uuid(90),
        stateRawValue: AlarmPlatformState.configured.rawValue,
        updatedAt: Date(timeIntervalSince1970: 2_200),
        lastErrorCode: nil
      )
    )
    try context.save()

    let conflictingID = AlarmPlatformSnapshot(
      id: uuid(91),
      scheduleID: scheduleID,
      routineID: routineID,
      desiredScheduleFingerprint: String(repeating: "f", count: 64),
      platformRequestID: uuid(92),
      state: .configured,
      updatedAt: Date(timeIntervalSince1970: 2_300),
      lastErrorCode: nil
    )
    XCTAssertThrowsError(try repository.save(conflictingID)) { error in
      XCTAssertEqual(
        error as? AlarmPlatformStateRepositoryError,
        .duplicateSchedule(scheduleID)
      )
    }

    let conflictingRoutine = AlarmPlatformSnapshot(
      id: persistedID,
      scheduleID: scheduleID,
      routineID: uuid(93),
      desiredScheduleFingerprint: String(repeating: "f", count: 64),
      platformRequestID: uuid(94),
      state: .configured,
      updatedAt: Date(timeIntervalSince1970: 2_400),
      lastErrorCode: nil
    )
    XCTAssertThrowsError(try repository.save(conflictingRoutine)) { error in
      XCTAssertEqual(
        error as? AlarmPlatformStateRepositoryError,
        .duplicateSchedule(scheduleID)
      )
    }

    let persisted = try XCTUnwrap(
      context.fetch(FetchDescriptor<PersistedAlarmPlatformState>()).first
    )
    XCTAssertEqual(persisted.id, persistedID)
    XCTAssertEqual(persisted.routineID, routineID)
    XCTAssertEqual(persisted.desiredScheduleFingerprint, String(repeating: "e", count: 64))
  }

  private func makeFixture(inventory: [UUID]) -> ResetFixture {
    let journal = makeJournalFixture()
    let log = ResetEventLog()
    let mutator = ResetAlarmMutator(log: log)
    let repository = ResetDataRepositorySpy(log: log, inventory: inventory)
    let clearSpy = ResetClearSpy(log: log)
    let coordinator = LocalResetCoordinator(
      alarmMutator: mutator,
      resetRepository: repository,
      journalStore: journal.store,
      now: { journal.date },
      makeUUID: { Self.uuid(100) },
      clearCoordinator: { operationID in
        try await clearSpy.clear(operationID: operationID)
      }
    )
    return ResetFixture(
      journalStore: journal.store,
      journalFileURL: journal.fileURL,
      journalDirectoryURL: journal.directoryURL,
      date: journal.date,
      log: log,
      mutator: mutator,
      repository: repository,
      clearSpy: clearSpy,
      coordinator: coordinator
    )
  }

  private func removeFixture(_ fixture: ResetFixture) {
    try? FileManager.default.removeItem(at: fixture.journalDirectoryURL)
  }

  private func makeJournalFixture(
    synchronizer: (any LocalResetJournalSynchronizing)? = nil
  ) -> JournalFixture {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "LocalResetCoordinatorTests-\(UUID().uuidString)",
      isDirectory: true
    )
    let fileURL = directoryURL.appendingPathComponent("journal.json", isDirectory: false)
    let store: LocalResetJournalStore
    if let synchronizer {
      store = LocalResetJournalStore(fileURL: fileURL, synchronizer: synchronizer)
    } else {
      store = LocalResetJournalStore(fileURL: fileURL)
    }
    return JournalFixture(
      store: store,
      directoryURL: directoryURL,
      fileURL: fileURL,
      date: Date(timeIntervalSince1970: 1_000)
    )
  }

  private func removeJournalFixture(_ fixture: JournalFixture) {
    try? FileManager.default.removeItem(at: fixture.directoryURL)
  }

  private func writeJournal(_ entry: LocalResetJournalEntry, to fileURL: URL) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(entry).write(to: fileURL)
  }

  private static func uuid(_ value: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", Int(value)))!
  }

  private func uuid(_ value: UInt8) -> UUID {
    Self.uuid(value)
  }
}

@MainActor
private final class ResetEventLog {
  private(set) var events: [String] = []

  func append(_ event: String) {
    events.append(event)
  }
}

@MainActor
private final class ResetAlarmMutator: AlarmScheduleMutating {
  private let log: ResetEventLog
  private var cancellationContinuation: CheckedContinuation<Void, Never>?
  private(set) var freezeTokens: [AlarmMutationFreezeToken] = []
  private(set) var cancelledScheduleIDs: [[UUID]] = []
  private(set) var cancelledTokens: [AlarmMutationFreezeToken] = []
  private(set) var thawedTokens: [AlarmMutationFreezeToken] = []
  var failCancellationCount = 0
  var pauseCancellation = false

  init(log: ResetEventLog) {
    self.log = log
  }

  func freezeAndDrain() async throws -> AlarmMutationFreezeToken {
    log.append("freeze")
    let token = AlarmMutationFreezeToken(id: UUID())
    freezeTokens.append(token)
    return token
  }

  func commit(
    routines: [Routine],
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try localCommit()
  }

  func delete(
    routineID: UUID,
    scheduleID: UUID?,
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try localCommit()
  }

  func reconcile(routines: [Routine]) async throws {}

  func cancelAll(
    scheduleIDs: [UUID],
    using token: AlarmMutationFreezeToken
  ) async throws {
    log.append("cancel")
    cancelledScheduleIDs.append(scheduleIDs)
    cancelledTokens.append(token)
    if failCancellationCount > 0 {
      failCancellationCount -= 1
      throw ResetCoordinatorTestError.expectedFailure
    }
    if pauseCancellation {
      await withCheckedContinuation { continuation in
        cancellationContinuation = continuation
      }
    }
  }

  func thaw(_ token: AlarmMutationFreezeToken) {
    log.append("thaw")
    thawedTokens.append(token)
  }

  func permissionState() async -> AlarmNotificationPermissionState {
    .authorized
  }

  func finishCancellation() {
    cancellationContinuation?.resume()
    cancellationContinuation = nil
    pauseCancellation = false
  }
}

@MainActor
private final class ResetDataRepositorySpy: LocalResetDataRepository {
  private let log: ResetEventLog
  private let inventory: [UUID]
  private(set) var inventoryCallCount = 0
  private(set) var deleteCallCount = 0
  var failInventoryCount = 0
  var failDeleteCount = 0

  init(log: ResetEventLog, inventory: [UUID]) {
    self.log = log
    self.inventory = inventory
  }

  func inventoryScheduleIDs() throws -> [UUID] {
    log.append("inventory")
    inventoryCallCount += 1
    if failInventoryCount > 0 {
      failInventoryCount -= 1
      throw ResetCoordinatorTestError.expectedFailure
    }
    return inventory
  }

  func deleteAll() throws {
    log.append("delete")
    deleteCallCount += 1
    if failDeleteCount > 0 {
      failDeleteCount -= 1
      throw ResetCoordinatorTestError.expectedFailure
    }
  }
}

@MainActor
private final class ResetClearSpy {
  private let log: ResetEventLog
  private(set) var callCount = 0
  private(set) var operationIDs: [UUID] = []
  var failClearCount = 0

  init(log: ResetEventLog) {
    self.log = log
  }

  func clear(operationID: UUID) async throws {
    log.append("clear")
    callCount += 1
    operationIDs.append(operationID)
    if failClearCount > 0 {
      failClearCount -= 1
      throw ResetCoordinatorTestError.expectedFailure
    }
  }
}

private enum ResetCoordinatorTestError: Error {
  case expectedFailure
}
private struct JournalSynchronizationCall: Equatable {
  let url: URL
  let isDirectory: Bool
}

private final class JournalSynchronizerSpy: LocalResetJournalSynchronizing {
  private(set) var calls: [JournalSynchronizationCall] = []
  var failOnNextSynchronization = false

  func synchronize(at url: URL, isDirectory: Bool) throws {
    calls.append(JournalSynchronizationCall(url: url, isDirectory: isDirectory))
    if failOnNextSynchronization {
      failOnNextSynchronization = false
      throw LocalResetJournalStoreError.writeFailed("injected synchronization failure")
    }
  }
}

private struct JournalFixture {
  let store: LocalResetJournalStore
  let directoryURL: URL
  let fileURL: URL
  let date: Date
}

@MainActor
private struct ResetFixture {
  let journalStore: LocalResetJournalStore
  let journalFileURL: URL
  let journalDirectoryURL: URL
  let date: Date
  let log: ResetEventLog
  let mutator: ResetAlarmMutator
  let repository: ResetDataRepositorySpy
  let clearSpy: ResetClearSpy
  let coordinator: LocalResetCoordinator
}
