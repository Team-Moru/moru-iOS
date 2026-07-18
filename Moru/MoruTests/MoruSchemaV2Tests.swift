//
//  MoruSchemaV2Tests.swift
//  MoruTests
//
//  Created by Codex on 7/18/26.
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class MoruSchemaV2Tests: XCTestCase {
  @MainActor
  func testV2ContainsEveryUnchangedV1ModelIdentity() {
    let v1ModelIDs = Set(MoruSchemaV1.models.map { ObjectIdentifier($0) })
    let v2ModelIDs = Set(MoruSchemaV2.models.map { ObjectIdentifier($0) })

    XCTAssertEqual(v1ModelIDs.count, 7)
    XCTAssertTrue(v1ModelIDs.isSubset(of: v2ModelIDs))
    XCTAssertEqual(v2ModelIDs.count, 12)
  }

  @MainActor
  func testDiskBackedV1MigrationPreservesFactsAndCreatesOnlyProfileSettings() throws {
    let storeURL = makeStoreURL()
    defer { removeStore(at: storeURL) }

    let fixture = try createV1Store(at: storeURL, includeProfile: true)

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let context = container.mainContext
      try assertV1Facts(in: context, fixture: fixture)
      let settings = try context.fetch(FetchDescriptor<PersistedLocalSettings>())

      XCTAssertEqual(settings.count, 1)
      XCTAssertEqual(settings.first?.id, fixture.profileID)
      XCTAssertEqual(settings.first?.profileID, fixture.profileID)
      XCTAssertEqual(
        settings.first?.voiceMigrationStateRawValue,
        VoiceMigrationState.unresolved.rawValue
      )
      XCTAssertNil(settings.first?.voiceMigrationOriginalVoiceID)
      XCTAssertNil(settings.first?.voiceMigrationResolvedVoiceID)
      XCTAssertNil(settings.first?.voiceMigrationUpdatedAt)
      XCTAssertEqual(
        settings.first?.schemaMigrationMarkerRawValue,
        SchemaMigrationMarker.v2Unresolved.rawValue
      )
      try assertNoV2Facts(in: context)
    }

    do {
      let reopened = try ModelContainer.moruContainer(storeURL: storeURL)
      let context = reopened.mainContext
      try assertV1Facts(in: context, fixture: fixture)
      let settings = try context.fetch(FetchDescriptor<PersistedLocalSettings>())

      XCTAssertEqual(settings.count, 1)
      XCTAssertEqual(settings.first?.id, fixture.profileID)
      XCTAssertEqual(settings.first?.profileID, fixture.profileID)
      try assertNoV2Facts(in: context)
    }
  }

  @MainActor
  func testDiskBackedMigrationWithNoProfileCreatesNoSettingsOrFacts() throws {
    let storeURL = makeStoreURL()
    defer { removeStore(at: storeURL) }

    let fixture = try createV1Store(at: storeURL, includeProfile: false)
    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let context = container.mainContext
      try assertV1Facts(in: context, fixture: fixture, includeProfile: false)
      XCTAssertTrue(
        try context.fetch(FetchDescriptor<PersistedLocalSettings>()).isEmpty
      )
      try assertNoV2Facts(in: context)
    }

    do {
      let reopened = try ModelContainer.moruContainer(storeURL: storeURL)
      let context = reopened.mainContext
      try assertV1Facts(in: context, fixture: fixture, includeProfile: false)
      XCTAssertTrue(
        try context.fetch(FetchDescriptor<PersistedLocalSettings>()).isEmpty
      )
      try assertNoV2Facts(in: context)
    }
  }

  @MainActor
  func testV2MappingRoundTripsValidSnapshotsAndRejectsInvalidValues() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let observation = makeObservation(now: now)
    let persistedObservation = try SwiftDataV2Mapper.makePersistedObservation(from: observation)
    XCTAssertEqual(
      try SwiftDataV2Mapper.makeObservationSnapshot(from: persistedObservation),
      observation
    )

    let weather = HomeWeatherSnapshot(
      id: UUID(),
      condition: .clear,
      temperatureCelsius: 21.5,
      latitudeE4: 375_665,
      longitudeE4: 1_269_780,
      fetchedAt: now,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
    let persistedWeather = try SwiftDataV2Mapper.makePersistedWeatherSnapshot(
      from: weather,
      now: now
    )
    XCTAssertEqual(
      try SwiftDataV2Mapper.makeHomeWeatherSnapshot(from: persistedWeather, now: now),
      weather
    )

    let platform = AlarmPlatformSnapshot(
      id: UUID(),
      scheduleID: UUID(),
      routineID: UUID(),
      desiredScheduleFingerprint: String(repeating: "c", count: 64),
      platformRequestID: UUID(),
      state: .repairRequired,
      updatedAt: now,
      lastErrorCode: "authorizationDenied"
    )
    let persistedPlatform = try SwiftDataV2Mapper.makePersistedAlarmPlatformState(
      from: platform
    )
    XCTAssertEqual(
      try SwiftDataV2Mapper.makeAlarmPlatformSnapshot(from: persistedPlatform),
      platform
    )

    var conflictingObservation = makeObservation(now: now)
    conflictingObservation = ScheduledAlarmStartObservationSnapshot(
      id: conflictingObservation.id,
      occurrenceID: observation.occurrenceID,
      rootOccurrenceID: conflictingObservation.rootOccurrenceID,
      parentOccurrenceID: conflictingObservation.parentOccurrenceID,
      routineID: conflictingObservation.routineID,
      scheduleID: conflictingObservation.scheduleID,
      actionObservedAt: conflictingObservation.actionObservedAt,
      scheduledFireAt: conflictingObservation.scheduledFireAt,
      resetGeneration: conflictingObservation.resetGeneration,
      source: conflictingObservation.source,
      immutableFingerprint: String(repeating: "b", count: 64),
      timeZoneIdentifier: conflictingObservation.timeZoneIdentifier,
      utcOffsetSeconds: conflictingObservation.utcOffsetSeconds,
      localGregorianDayKey: conflictingObservation.localGregorianDayKey,
      localGregorianDayOrdinal: conflictingObservation.localGregorianDayOrdinal,
      localMinute: conflictingObservation.localMinute,
      receivedAt: conflictingObservation.receivedAt
    )
    XCTAssertThrowsError(
      try SwiftDataV2Mapper.validate(observation: conflictingObservation, against: observation)
    ) { error in
      XCTAssertEqual(
        error as? PersistenceV2MappingError,
        .observationIdentityConflict(occurrenceID: observation.occurrenceID)
      )
    }

    let invalidMinute = PersistedScheduledAlarmStartObservation(
      id: UUID(),
      occurrenceID: "occurrence-invalid-minute",
      rootOccurrenceID: "root-invalid-minute",
      parentOccurrenceID: nil,
      routineID: UUID(),
      scheduleID: UUID(),
      actionObservedAt: now,
      scheduledFireAt: now,
      resetGeneration: 1,
      sourceRawValue: ScheduledAlarmObservationSource.alarmKitOccurrenceActionV1.rawValue,
      immutableFingerprint: String(repeating: "a", count: 64),
      timeZoneIdentifier: "Asia/Seoul",
      utcOffsetSeconds: 32_400,
      localGregorianDayKey: "2026-07-18",
      localGregorianDayOrdinal: 199,
      localMinute: 1_440,
      receivedAt: now
    )
    XCTAssertThrowsError(try SwiftDataV2Mapper.makeObservationSnapshot(from: invalidMinute)) {
      XCTAssertEqual($0 as? PersistenceV2MappingError, .invalidValue(field: "localMinute"))
    }

    let unknownSource = PersistedScheduledAlarmStartObservation(
      id: UUID(),
      occurrenceID: "occurrence-unknown-source",
      rootOccurrenceID: "root-unknown-source",
      parentOccurrenceID: nil,
      routineID: UUID(),
      scheduleID: UUID(),
      actionObservedAt: now,
      scheduledFireAt: now,
      resetGeneration: 1,
      sourceRawValue: "manual",
      immutableFingerprint: String(repeating: "a", count: 64),
      timeZoneIdentifier: "Asia/Seoul",
      utcOffsetSeconds: 32_400,
      localGregorianDayKey: "2026-07-18",
      localGregorianDayOrdinal: 199,
      localMinute: 0,
      receivedAt: now
    )
    XCTAssertThrowsError(try SwiftDataV2Mapper.makeObservationSnapshot(from: unknownSource)) {
      XCTAssertEqual(
        $0 as? PersistenceV2MappingError,
        .unknownRawValue(
          field: "PersistedScheduledAlarmStartObservation.sourceRawValue",
          rawValue: "manual"
        )
      )
    }

    let invalidWeather = HomeWeatherSnapshot(
      id: UUID(),
      condition: .clear,
      temperatureCelsius: .nan,
      latitudeE4: 0,
      longitudeE4: 0,
      fetchedAt: now,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
    XCTAssertThrowsError(
      try SwiftDataV2Mapper.makePersistedWeatherSnapshot(from: invalidWeather, now: now)
    ) {
      XCTAssertEqual($0 as? PersistenceV2MappingError, .invalidValue(field: "temperatureCelsius"))
    }

    let unknownWeather = PersistedHomeWeatherSnapshot(
      id: UUID(),
      conditionRawValue: "hail",
      temperatureCelsius: 20,
      latitudeE4: 0,
      longitudeE4: 0,
      fetchedAt: now,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
    XCTAssertThrowsError(
      try SwiftDataV2Mapper.makeHomeWeatherSnapshot(from: unknownWeather, now: now)
    ) {
      XCTAssertEqual(
        $0 as? PersistenceV2MappingError,
        .unknownRawValue(field: "PersistedHomeWeatherSnapshot.conditionRawValue", rawValue: "hail")
      )
    }

    let unknownSettings = PersistedLocalSettings(
      id: UUID(),
      profileID: UUID(),
      voiceMigrationStateRawValue: "unknown",
      voiceMigrationOriginalVoiceID: nil,
      voiceMigrationResolvedVoiceID: nil,
      voiceMigrationUpdatedAt: nil,
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Unresolved.rawValue
    )
    XCTAssertThrowsError(try SwiftDataV2Mapper.makeLocalSettingsSnapshot(from: unknownSettings)) {
      XCTAssertEqual(
        $0 as? PersistenceV2MappingError,
        .unknownRawValue(
          field: "PersistedLocalSettings.voiceMigrationStateRawValue",
          rawValue: "unknown"
        )
      )
    }

    let unknownRoot = PersistedAlarmRootChainState(
      id: UUID(),
      rootOccurrenceID: "root-unknown-state",
      routineID: UUID(),
      scheduleID: UUID(),
      resetGeneration: 1,
      rootFingerprint: String(repeating: "a", count: 64),
      earliestObservedOccurrenceID: "earliest",
      earliestObservedAt: now,
      latestObservedOccurrenceID: "latest",
      latestObservedAt: now,
      terminalOccurrenceID: nil,
      terminalAt: nil,
      stateRawValue: "unknown",
      updatedAt: now
    )
    XCTAssertThrowsError(
      try SwiftDataV2Mapper.makeAlarmRootChainStateSnapshot(from: unknownRoot)
    ) {
      XCTAssertEqual(
        $0 as? PersistenceV2MappingError,
        .unknownRawValue(field: "PersistedAlarmRootChainState.stateRawValue", rawValue: "unknown")
      )
    }
    let terminalRoot = AlarmRootChainStateSnapshot(
      id: UUID(),
      rootOccurrenceID: observation.rootOccurrenceID,
      routineID: observation.routineID,
      scheduleID: observation.scheduleID,
      resetGeneration: observation.resetGeneration,
      rootFingerprint: observation.immutableFingerprint,
      earliestObservedOccurrenceID: observation.occurrenceID,
      earliestObservedAt: observation.actionObservedAt,
      latestObservedOccurrenceID: observation.occurrenceID,
      latestObservedAt: observation.actionObservedAt,
      terminalOccurrenceID: observation.occurrenceID,
      terminalAt: observation.actionObservedAt,
      state: .terminal,
      updatedAt: now
    )
    let persistedTerminalRoot = try SwiftDataV2Mapper.makePersistedRootChainState(
      from: terminalRoot,
      terminalObservation: observation
    )
    XCTAssertEqual(
      try SwiftDataV2Mapper.makeAlarmRootChainStateSnapshot(
        from: persistedTerminalRoot,
        terminalObservation: observation
      ),
      terminalRoot
    )

    let mismatchedTerminalRoot = AlarmRootChainStateSnapshot(
      id: UUID(),
      rootOccurrenceID: observation.rootOccurrenceID,
      routineID: observation.routineID,
      scheduleID: observation.scheduleID,
      resetGeneration: observation.resetGeneration,
      rootFingerprint: observation.immutableFingerprint,
      earliestObservedOccurrenceID: observation.occurrenceID,
      earliestObservedAt: observation.actionObservedAt,
      latestObservedOccurrenceID: observation.occurrenceID,
      latestObservedAt: now.addingTimeInterval(1),
      terminalOccurrenceID: observation.occurrenceID,
      terminalAt: now.addingTimeInterval(1),
      state: .terminal,
      updatedAt: now
    )
    XCTAssertThrowsError(
      try SwiftDataV2Mapper.makePersistedRootChainState(
        from: mismatchedTerminalRoot,
        terminalObservation: observation
      )
    ) {
      XCTAssertEqual($0 as? PersistenceV2MappingError, .terminalObservationMismatch)
    }

    let unknownPlatform = PersistedAlarmPlatformState(
      id: UUID(),
      scheduleID: UUID(),
      routineID: UUID(),
      desiredScheduleFingerprint: String(repeating: "a", count: 64),
      platformRequestID: UUID(),
      stateRawValue: "unknown",
      updatedAt: now,
      lastErrorCode: nil
    )
    XCTAssertThrowsError(try SwiftDataV2Mapper.makeAlarmPlatformSnapshot(from: unknownPlatform)) {
      XCTAssertEqual(
        $0 as? PersistenceV2MappingError,
        .unknownRawValue(field: "PersistedAlarmPlatformState.stateRawValue", rawValue: "unknown")
      )
    }
  }

  @MainActor
  private func createV1Store(at storeURL: URL, includeProfile: Bool) throws -> V1Fixture {
    let schema = Schema(versionedSchema: MoruSchemaV1.self)
    let configuration = ModelConfiguration(
      "Moru",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = container.mainContext
    let fixture = V1Fixture()
    let step = PersistedRoutineStep(
      id: fixture.stepID,
      presetItemID: "wake",
      typeRawValue: RoutineStepType.confirm.rawValue,
      title: "Wake",
      instruction: "Wake up",
      order: 0,
      estimatedSeconds: nil,
      isRequired: true
    )
    let schedule = PersistedAlarmSchedule(
      id: fixture.scheduleID,
      hour: 7,
      minute: 0,
      weekdaysRawValue: "[2]",
      soundName: "moru-default",
      isEnabled: true,
      includeWeather: true,
      includeFortune: true
    )
    let routine = PersistedRoutine(
      id: fixture.routineID,
      name: "Routine",
      summary: "",
      goalTagsRawValue: "[]",
      steps: [step],
      alarmSchedule: schedule,
      isActive: true,
      createdAt: fixture.now,
      updatedAt: fixture.now,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
    let result = PersistedRoutineStepResult(
      id: fixture.resultID,
      stepID: fixture.stepID,
      stepTitle: "Wake",
      stepTypeRawValue: RoutineStepType.confirm.rawValue,
      completedAt: fixture.now,
      skipped: false,
      inputText: nil,
      transcript: nil,
      durationSeconds: nil
    )
    let snapshot = PersistedRoutineStepSnapshot(
      id: fixture.snapshotID,
      stepID: fixture.stepID,
      stepTitle: "Wake",
      stepTypeRawValue: RoutineStepType.confirm.rawValue,
      stepOrder: 0,
      estimatedSeconds: nil,
      isRequired: true
    )
    let run = PersistedRoutineRun(
      id: fixture.runID,
      routineID: fixture.routineID,
      routineName: "Routine",
      startedAt: fixture.now,
      completedAt: fixture.now,
      results: [result],
      plannedSteps: [snapshot],
      endedEarly: false,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )

    context.insert(routine)
    context.insert(run)
    if includeProfile {
      context.insert(
        PersistedLocalProfile(
          id: fixture.profileID,
          displayName: "Moru",
          selectedVoiceID: "moru-local",
          createdAt: fixture.now,
          updatedAt: fixture.now
        )
      )
    }
    try context.save()
    return fixture
  }

  @MainActor
  private func assertV1Facts(
    in context: ModelContext,
    fixture: V1Fixture,
    includeProfile: Bool = true
  ) throws {
    let routines = try context.fetch(FetchDescriptor<PersistedRoutine>())
    let runs = try context.fetch(FetchDescriptor<PersistedRoutineRun>())
    let profiles = try context.fetch(FetchDescriptor<PersistedLocalProfile>())
    XCTAssertEqual(routines.count, 1)
    XCTAssertEqual(runs.count, 1)
    XCTAssertEqual(profiles.count, includeProfile ? 1 : 0)

    let routine = try XCTUnwrap(routines.first)
    XCTAssertEqual(routine.id, fixture.routineID)
    XCTAssertEqual(routine.name, "Routine")
    XCTAssertEqual(routine.summary, "")
    XCTAssertEqual(routine.goalTagsRawValue, "[]")
    XCTAssertEqual(routine.isActive, true)
    XCTAssertEqual(routine.createdAt, fixture.now)
    XCTAssertEqual(routine.updatedAt, fixture.now)
    XCTAssertNil(routine.remoteID)
    XCTAssertEqual(routine.syncStatusRawValue, SyncStatus.localOnly.rawValue)
    XCTAssertNil(routine.lastSyncedAt)
    XCTAssertNil(routine.remoteRevision)

    let step = try XCTUnwrap(routine.steps.first)
    XCTAssertEqual(routine.steps.count, 1)
    XCTAssertEqual(step.id, fixture.stepID)
    XCTAssertEqual(step.presetItemID, "wake")
    XCTAssertEqual(step.typeRawValue, RoutineStepType.confirm.rawValue)
    XCTAssertEqual(step.title, "Wake")
    XCTAssertEqual(step.instruction, "Wake up")
    XCTAssertEqual(step.order, 0)
    XCTAssertNil(step.estimatedSeconds)
    XCTAssertEqual(step.isRequired, true)

    let schedule = try XCTUnwrap(routine.alarmSchedule)
    XCTAssertEqual(schedule.id, fixture.scheduleID)
    XCTAssertEqual(schedule.hour, 7)
    XCTAssertEqual(schedule.minute, 0)
    XCTAssertEqual(schedule.weekdaysRawValue, "[2]")
    XCTAssertEqual(schedule.soundName, "moru-default")
    XCTAssertEqual(schedule.isEnabled, true)
    XCTAssertFalse(schedule.includeWeather)
    XCTAssertFalse(schedule.includeFortune)

    let run = try XCTUnwrap(runs.first)
    XCTAssertEqual(run.id, fixture.runID)
    XCTAssertEqual(run.routineID, fixture.routineID)
    XCTAssertEqual(run.routineName, "Routine")
    XCTAssertEqual(run.startedAt, fixture.now)
    XCTAssertEqual(run.completedAt, fixture.now)
    XCTAssertEqual(run.endedEarly, false)
    XCTAssertNil(run.remoteID)
    XCTAssertEqual(run.syncStatusRawValue, SyncStatus.localOnly.rawValue)
    XCTAssertNil(run.lastSyncedAt)
    XCTAssertNil(run.remoteRevision)

    let result = try XCTUnwrap(run.results.first)
    XCTAssertEqual(run.results.count, 1)
    XCTAssertEqual(result.id, fixture.resultID)
    XCTAssertEqual(result.stepID, fixture.stepID)
    XCTAssertEqual(result.stepTitle, "Wake")
    XCTAssertEqual(result.stepTypeRawValue, RoutineStepType.confirm.rawValue)
    XCTAssertEqual(result.completedAt, fixture.now)
    XCTAssertEqual(result.skipped, false)
    XCTAssertNil(result.inputText)
    XCTAssertNil(result.transcript)
    XCTAssertNil(result.durationSeconds)

    let snapshot = try XCTUnwrap(run.plannedSteps.first)
    XCTAssertEqual(run.plannedSteps.count, 1)
    XCTAssertEqual(snapshot.id, fixture.snapshotID)
    XCTAssertEqual(snapshot.stepID, fixture.stepID)
    XCTAssertEqual(snapshot.stepTitle, "Wake")
    XCTAssertEqual(snapshot.stepTypeRawValue, RoutineStepType.confirm.rawValue)
    XCTAssertEqual(snapshot.stepOrder, 0)
    XCTAssertNil(snapshot.estimatedSeconds)
    XCTAssertEqual(snapshot.isRequired, true)

    if includeProfile {
      let profile = try XCTUnwrap(profiles.first)
      XCTAssertEqual(profile.id, fixture.profileID)
      XCTAssertEqual(profile.displayName, "Moru")
      XCTAssertEqual(profile.selectedVoiceID, "moru-local")
      XCTAssertEqual(profile.createdAt, fixture.now)
      XCTAssertEqual(profile.updatedAt, fixture.now)
    }
  }
  @MainActor
  private func assertNoV2Facts(in context: ModelContext) throws {
    XCTAssertTrue(
      try context.fetch(FetchDescriptor<PersistedScheduledAlarmStartObservation>()).isEmpty
    )
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedAlarmRootChainState>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedAlarmPlatformState>()).isEmpty)
  }

  private func makeObservation(now: Date) -> ScheduledAlarmStartObservationSnapshot {
    ScheduledAlarmStartObservationSnapshot(
      id: UUID(),
      occurrenceID: "occurrence-1",
      rootOccurrenceID: "root-1",
      parentOccurrenceID: nil,
      routineID: UUID(),
      scheduleID: UUID(),
      actionObservedAt: now,
      scheduledFireAt: now,
      resetGeneration: 1,
      source: .alarmKitOccurrenceActionV1,
      immutableFingerprint: String(repeating: "a", count: 64),
      timeZoneIdentifier: "Asia/Seoul",
      utcOffsetSeconds: 32_400,
      localGregorianDayKey: "2026-07-18",
      localGregorianDayOrdinal: 199,
      localMinute: 420,
      receivedAt: now
    )
  }

  private func makeStoreURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("MoruSchemaV2-\(UUID().uuidString)")
      .appendingPathExtension("sqlite")
  }

  private func removeStore(at storeURL: URL) {
    let paths = [
      storeURL,
      URL(fileURLWithPath: storeURL.path + "-shm"),
      URL(fileURLWithPath: storeURL.path + "-wal")
    ]
    paths.forEach { try? FileManager.default.removeItem(at: $0) }
  }
}

private struct V1Fixture {
  let routineID = UUID()
  let stepID = UUID()
  let scheduleID = UUID()
  let runID = UUID()
  let resultID = UUID()
  let snapshotID = UUID()
  let profileID = UUID()
  let now = Date(timeIntervalSince1970: 10_000)
}
