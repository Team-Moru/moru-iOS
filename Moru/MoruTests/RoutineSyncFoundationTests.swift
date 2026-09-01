//
//  RoutineSyncFoundationTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class RoutineSyncFoundationTests: XCTestCase {
  @MainActor
  func testBindingUsesStableLocalIDAcrossCallsAndRepositories() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let localID = UUID()
    let firstDate = Date(timeIntervalSince1970: 10)
    let firstRepository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )

    let first = try firstRepository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: localID,
      at: firstDate
    )
    let secondRepository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    let second = try secondRepository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: localID,
      at: Date(timeIntervalSince1970: 20)
    )
    let anotherAccount = try secondRepository.recordRemoteID(
      92,
      revision: nil,
      memberID: 8,
      entityKind: .routineGroup,
      localEntityID: localID,
      at: firstDate
    )

    XCTAssertEqual(second.id, first.id)
    XCTAssertEqual(first.localEntityID, localID)
    XCTAssertEqual(first.clientEntityID, localID)
    XCTAssertEqual(first.remoteID, 41)
    XCTAssertEqual(anotherAccount.clientEntityID, localID)
    XCTAssertEqual(anotherAccount.remoteID, 92)
    XCTAssertEqual(
      try container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).count,
      2
    )
  }

  @MainActor
  func testRemoteIDIsTypedAndCannotBeSilentlyRebound() throws {
    let repository = try makeRepository()
    let localID = UUID()
    let groupID = UUID()

    let bound = try XCTUnwrap(
      repository.recordRemoteIDs(
        [
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: localID,
            remoteID: 41,
            remoteRevision: " rev-1 ",
            parentEntityKind: .routineGroup,
            parentLocalEntityID: groupID
          )
        ],
        memberID: 7,
        at: Date(timeIntervalSince1970: 20)
      ).first
    )

    XCTAssertEqual(bound.remoteID, 41)
    XCTAssertEqual(bound.remoteRevision, "rev-1")
    XCTAssertEqual(
      try repository.binding(
        memberID: 7,
        entityKind: .routine,
        localEntityID: localID
      ),
      bound
    )
    XCTAssertThrowsError(
      try repository.recordRemoteIDs(
        [
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: localID,
            remoteID: 42,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: groupID
          )
        ],
        memberID: 7,
        at: Date(timeIntervalSince1970: 30)
      )
    ) {
      XCTAssertEqual(
        $0 as? RoutineSyncRepositoryError,
        .remoteIDConflict(existing: 41, incoming: 42)
      )
    }
  }

  @MainActor
  func testRemoteIDCannotBindToTwoLocalEntitiesInSameAccount() throws {
    let repository = try makeRepository()
    let firstLocalID = UUID()
    let secondLocalID = UUID()
    let groupID = UUID()
    _ = try repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: firstLocalID,
          remoteID: 41,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 10)
    )

    XCTAssertThrowsError(
      try repository.recordRemoteIDs(
        [
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: secondLocalID,
            remoteID: 41,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: groupID
          )
        ],
        memberID: 7,
        at: Date(timeIntervalSince1970: 20)
      )
    ) {
      XCTAssertEqual(
        $0 as? RoutineSyncRepositoryError,
        .remoteIDAlreadyBound(
          remoteID: 41,
          localEntityID: firstLocalID
        )
      )
    }
  }

  @MainActor
  func testAggregateBindingRecordsGroupAndChildrenInOneSave() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let firstStepID = UUID()
    let secondStepID = UUID()

    let bindings = try repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: firstStepID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: secondStepID,
          remoteID: 52,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 10)
    )

    XCTAssertEqual(bindings.map(\.localEntityID), [groupID, firstStepID, secondStepID])
    XCTAssertEqual(bindings.map(\.remoteID), [41, 51, 52])
  }

  @MainActor
  func testAggregateBindingConflictDoesNotPartiallyWrite() throws {
    let repository = try makeRepository()
    let alreadyBoundStepID = UUID()
    let groupID = UUID()
    _ = try repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: alreadyBoundStepID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 5)
    )
    let newGroupID = UUID()

    XCTAssertThrowsError(
      try repository.recordRemoteIDs(
        [
          RoutineServerBindingAssignment(
            entityKind: .routineGroup,
            localEntityID: newGroupID,
            remoteID: 41
          ),
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: UUID(),
            remoteID: 51,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: newGroupID
          ),
        ],
        memberID: 7,
        at: Date(timeIntervalSince1970: 10)
      )
    )

    XCTAssertNil(
      try repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: newGroupID
      )
    )
    XCTAssertEqual(
      try repository.binding(
        memberID: 7,
        entityKind: .routine,
        localEntityID: alreadyBoundStepID
      )?.remoteID,
      51
    )
  }

  @MainActor
  func testExactDuplicateMutationReusesOneGeneration() throws {
    let repository = try makeRepository()
    let localID = UUID()
    let firstRequest = EnqueuedRoutineSyncMutation(
      memberID: 7,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: localID,
      payload: Data(#"{"title":"아침","active":true}"#.utf8)
    )
    let sameJSONWithDifferentKeyOrder = EnqueuedRoutineSyncMutation(
      memberID: 7,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: localID,
      payload: Data(#"{"active":true,"title":"아침"}"#.utf8)
    )

    let first = try repository.enqueue(
      firstRequest,
      at: Date(timeIntervalSince1970: 10)
    )
    let duplicate = try repository.enqueue(
      sameJSONWithDifferentKeyOrder,
      at: Date(timeIntervalSince1970: 20)
    )

    XCTAssertEqual(duplicate, first)
    XCTAssertEqual(first.generation, 1)
    XCTAssertEqual(first.state, .waitingForServerContract)
    XCTAssertEqual(try repository.mutations(memberID: 7), [first])
  }

  @MainActor
  func testChangedPayloadCoalescesAndRotatesGenerationID() throws {
    let repository = try makeRepository()
    let localID = UUID()
    let first = try repository.enqueue(
      mutation(
        localID: localID,
        payload: Data(#"{"active":true}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 10)
    )
    let changed = try repository.enqueue(
      mutation(
        localID: localID,
        payload: Data(#"{"active":false}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 20)
    )

    XCTAssertEqual(changed.id, first.id)
    XCTAssertNotEqual(changed.generationID, first.generationID)
    XCTAssertEqual(changed.generation, 2)
    XCTAssertEqual(changed.createdAt, first.createdAt)
    XCTAssertEqual(changed.updatedAt, Date(timeIntervalSince1970: 20))
    XCTAssertEqual(try repository.mutations(memberID: 7), [changed])
  }

  @MainActor
  func testLateResultCannotDamageNewerMutationGeneration() throws {
    let repository = try makeRepository()
    let localID = UUID()
    let first = try repository.enqueue(
      mutation(
        localID: localID,
        payload: Data(#"{"active":true}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 10)
    )
    let changed = try repository.enqueue(
      mutation(
        localID: localID,
        payload: Data(#"{"active":false}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 20)
    )

    try repository.markNeedsReconciliation(
      id: first.id,
      expectedGenerationID: first.generationID,
      at: Date(timeIntervalSince1970: 30)
    )
    XCTAssertEqual(
      try repository.mutations(memberID: 7).first?.state,
      .waitingForServerContract
    )

    try repository.removeCompleted(
      id: first.id,
      expectedGenerationID: first.generationID
    )
    XCTAssertEqual(try repository.mutations(memberID: 7), [changed])

    try repository.markNeedsReconciliation(
      id: changed.id,
      expectedGenerationID: changed.generationID,
      at: Date(timeIntervalSince1970: 40)
    )
    let reconciled = try XCTUnwrap(
      try repository.mutations(memberID: 7).first
    )
    XCTAssertEqual(reconciled.state, .needsReconciliation)

    try repository.removeCompleted(
      id: reconciled.id,
      expectedGenerationID: reconciled.generationID
    )
    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testAmbiguousMutationMustReconcileBeforePayloadCanChange() throws {
    let repository = try makeRepository()
    let localID = UUID()
    let first = try repository.enqueue(
      EnqueuedRoutineSyncMutation(
        memberID: 7,
        operation: .createRoutineGroup,
        entityKind: .routineGroup,
        localEntityID: localID,
        payload: Data(#"{"title":"아침"}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 10)
    )
    try repository.markNeedsReconciliation(
      id: first.id,
      expectedGenerationID: first.generationID,
      at: Date(timeIntervalSince1970: 20)
    )

    XCTAssertThrowsError(
      try repository.enqueue(
        EnqueuedRoutineSyncMutation(
          memberID: 7,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: localID,
          payload: Data(#"{"title":"저녁"}"#.utf8)
        ),
        at: Date(timeIntervalSince1970: 30)
      )
    ) {
      XCTAssertEqual(
        $0 as? RoutineSyncRepositoryError,
        .reconciliationRequired(existingMutationID: first.id)
      )
    }
    let stored = try XCTUnwrap(try repository.mutations(memberID: 7).first)
    XCTAssertEqual(stored.payload, first.payload)
    XCTAssertEqual(stored.state, .needsReconciliation)
  }

  @MainActor
  func testOperationRejectsWrongEntityKind() throws {
    let repository = try makeRepository()

    XCTAssertThrowsError(
      try repository.enqueue(
        EnqueuedRoutineSyncMutation(
          memberID: 7,
          operation: .saveRoutineExecution,
          entityKind: .routineGroup,
          localEntityID: UUID(),
          payload: Data(#"{"completed":true}"#.utf8)
        ),
        at: Date(timeIntervalSince1970: 10)
      )
    ) {
      XCTAssertEqual(
        $0 as? RoutineSyncRepositoryError,
        .invalidOperationEntityCombination
      )
    }
  }

  @MainActor
  func testMutationRejectsNonJSONPayloadAndInvalidVersion() throws {
    let repository = try makeRepository()

    XCTAssertThrowsError(
      try repository.enqueue(
        EnqueuedRoutineSyncMutation(
          memberID: 7,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: UUID(),
          payload: Data("not-json".utf8)
        ),
        at: Date(timeIntervalSince1970: 10)
      )
    ) {
      XCTAssertEqual($0 as? RoutineSyncRepositoryError, .invalidPayload)
    }
    XCTAssertThrowsError(
      try repository.enqueue(
        EnqueuedRoutineSyncMutation(
          memberID: 7,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: UUID(),
          payloadVersion: 0,
          payload: Data(#"{"title":"아침"}"#.utf8)
        ),
        at: Date(timeIntervalSince1970: 10)
      )
    ) {
      XCTAssertEqual($0 as? RoutineSyncRepositoryError, .invalidPayload)
    }
  }

  @MainActor
  func testAccountCleanupRemovesOnlySelectedAccountSyncData() throws {
    let repository = try makeRepository()
    let localID = UUID()
    for memberID in [Int64(7), Int64(8)] {
      _ = try repository.recordRemoteID(
        memberID + 100,
        revision: nil,
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: localID,
        at: Date(timeIntervalSince1970: 10)
      )
      _ = try repository.enqueue(
        EnqueuedRoutineSyncMutation(
          memberID: memberID,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: localID,
          payload: Data(#"{"title":"아침"}"#.utf8)
        ),
        at: Date(timeIntervalSince1970: 10)
      )
    }

    try repository.removeAccountScopedData(memberID: 7)

    XCTAssertNil(
      try repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: localID
      )
    )
    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
    XCTAssertNotNil(
      try repository.binding(
        memberID: 8,
        entityKind: .routineGroup,
        localEntityID: localID
      )
    )
    XCTAssertEqual(try repository.mutations(memberID: 8).count, 1)
  }

  @MainActor
  func testProductionAndStagingBindingsDoNotShareRemoteIdentity() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let production = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext,
      serverNamespace: .production
    )
    let staging = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext,
      serverNamespace: .staging
    )
    let localID = UUID()

    let productionBinding = try production.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: localID,
      at: Date(timeIntervalSince1970: 10)
    )
    let stagingBinding = try staging.recordRemoteID(
      92,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: localID,
      at: Date(timeIntervalSince1970: 10)
    )

    XCTAssertEqual(productionBinding.serverNamespace, .production)
    XCTAssertEqual(productionBinding.remoteID, 41)
    XCTAssertEqual(stagingBinding.serverNamespace, .staging)
    XCTAssertEqual(stagingBinding.remoteID, 92)

    let productionMutation = try production.enqueue(
      EnqueuedRoutineSyncMutation(
        memberID: 7,
        operation: .createRoutineGroup,
        entityKind: .routineGroup,
        localEntityID: localID,
        payload: Data(#"{"title":"운영"}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 20)
    )
    let stagingMutation = try staging.enqueue(
      EnqueuedRoutineSyncMutation(
        memberID: 7,
        operation: .createRoutineGroup,
        entityKind: .routineGroup,
        localEntityID: localID,
        payload: Data(#"{"title":"스테이징"}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 20)
    )

    try production.removeCompleted(
      id: stagingMutation.id,
      expectedGenerationID: stagingMutation.generationID
    )
    XCTAssertEqual(try staging.mutations(memberID: 7), [stagingMutation])

    try production.removeCompleted(
      id: productionMutation.id,
      expectedGenerationID: productionMutation.generationID
    )
    XCTAssertTrue(try production.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testV3StoreMigratesToV4WithEmptySyncFoundation() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("moru.store")
    let profileID = UUID()
    let routineID = UUID()
    let stepID = UUID()
    let scheduleID = UUID()
    let runID = UUID()
    let snapshotID = UUID()
    let resultID = UUID()
    let weatherID = UUID()
    let snoozeID = UUID()

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
      let step = PersistedRoutineStep(
        id: stepID,
        presetItemID: nil,
        typeRawValue: RoutineStepType.confirm.rawValue,
        title: "기존 단계",
        instruction: "",
        order: 0,
        estimatedSeconds: nil,
        isRequired: true
      )
      let schedule = PersistedAlarmSchedule(
        id: scheduleID,
        hour: 7,
        minute: 30,
        weekdaysRawValue: "[1,2]",
        soundName: "moru-default",
        isEnabled: true,
        includeWeather: false,
        includeFortune: false
      )
      let snapshot = PersistedRoutineStepSnapshot(
        id: snapshotID,
        stepID: stepID,
        stepTitle: "기존 단계",
        stepTypeRawValue: RoutineStepType.confirm.rawValue,
        stepOrder: 0,
        estimatedSeconds: nil,
        isRequired: true
      )
      let result = PersistedRoutineStepResult(
        id: resultID,
        stepID: stepID,
        stepTitle: "기존 단계",
        stepTypeRawValue: RoutineStepType.confirm.rawValue,
        completedAt: Date(timeIntervalSince1970: 2),
        skipped: false,
        inputText: "보존",
        transcript: "보존",
        durationSeconds: 10
      )
      container.mainContext.insert(
        PersistedRoutine(
          id: routineID,
          name: "기존 루틴",
          summary: "요약",
          goalTagsRawValue: "[]",
          steps: [step],
          alarmSchedule: schedule,
          isActive: true,
          createdAt: Date(timeIntervalSince1970: 1),
          updatedAt: Date(timeIntervalSince1970: 1),
          remoteID: nil,
          syncStatusRawValue: "localOnly",
          lastSyncedAt: nil,
          remoteRevision: nil
        )
      )
      container.mainContext.insert(
        PersistedRoutineRun(
          id: runID,
          routineID: routineID,
          routineName: "기존 루틴",
          startedAt: Date(timeIntervalSince1970: 1),
          completedAt: Date(timeIntervalSince1970: 2),
          results: [result],
          plannedSteps: [snapshot],
          endedEarly: false,
          remoteID: nil,
          syncStatusRawValue: "localOnly",
          lastSyncedAt: nil,
          remoteRevision: nil
        )
      )
      container.mainContext.insert(
        PersistedLocalProfile(
          id: profileID,
          displayName: "기존 사용자",
          selectedVoiceID: VoiceProfile.aoede.id,
          createdAt: Date(timeIntervalSince1970: 1),
          updatedAt: Date(timeIntervalSince1970: 1)
        )
      )
      container.mainContext.insert(
        PersistedHomeWeatherSnapshot(
          id: weatherID,
          conditionRawValue: "clear",
          temperatureCelsius: 20,
          latitudeE4: 100,
          longitudeE4: 200,
          fetchedAt: Date(timeIntervalSince1970: 1),
          fetchedTimeZoneIdentifier: "Asia/Seoul",
          fetchedUTCOffsetSeconds: 32400
        )
      )
      container.mainContext.insert(
        PersistedAlarmPlatformState(
          scheduleID: scheduleID,
          routineID: routineID,
          routineName: "기존 루틴",
          hour: 7,
          minute: 30,
          weekdaysRawValue: "[1,2]",
          soundName: "moru-default",
          fingerprint: "fixture",
          backendRawValue: nil,
          deliveryStateRawValue: "scheduled",
          platformIdentifiersRawValue: "[]",
          lastErrorMessage: nil,
          updatedAt: Date(timeIntervalSince1970: 1)
        )
      )
      container.mainContext.insert(
        PersistedSnoozedAlarm(
          id: snoozeID,
          scheduleID: scheduleID,
          routineID: routineID,
          fireDate: Date(timeIntervalSince1970: 3),
          backendRawValue: "notification",
          platformIdentifiersRawValue: "[]",
          createdAt: Date(timeIntervalSince1970: 1)
        )
      )
      try container.mainContext.save()
    }

    let migrated = try ModelContainer.moruContainer(storeURL: storeURL)

    XCTAssertEqual(
      try migrated.mainContext.fetch(
        FetchDescriptor<PersistedLocalProfile>()
      ).map(\.id),
      [profileID]
    )
    XCTAssertTrue(
      try migrated.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).isEmpty
    )
    let migratedRoutine = try XCTUnwrap(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutine>()).first
    )
    XCTAssertEqual(migratedRoutine.id, routineID)
    XCTAssertEqual(migratedRoutine.steps.map(\.id), [stepID])
    XCTAssertEqual(migratedRoutine.steps.first?.title, "기존 단계")
    XCTAssertEqual(migratedRoutine.alarmSchedule?.id, scheduleID)
    XCTAssertEqual(migratedRoutine.alarmSchedule?.hour, 7)
    let migratedRun = try XCTUnwrap(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutineRun>()).first
    )
    XCTAssertEqual(migratedRun.id, runID)
    XCTAssertEqual(migratedRun.results.map(\.id), [resultID])
    XCTAssertEqual(migratedRun.results.first?.inputText, "보존")
    XCTAssertEqual(migratedRun.plannedSteps.map(\.id), [snapshotID])
    XCTAssertEqual(migratedRun.plannedSteps.first?.stepID, stepID)
    XCTAssertEqual(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).first?.temperatureCelsius,
      20
    )
    XCTAssertEqual(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>()).first?.fingerprint,
      "fixture"
    )
    XCTAssertEqual(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedSnoozedAlarm>()).first?.backendRawValue,
      "notification"
    )
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutine>()).map(\.id), [routineID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutineStep>()).map(\.id), [stepID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedAlarmSchedule>()).map(\.id), [scheduleID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutineRun>()).map(\.id), [runID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutineStepSnapshot>()).map(\.id), [snapshotID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutineStepResult>()).map(\.id), [resultID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).map(\.id), [weatherID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>()).map(\.scheduleID), [scheduleID])
    XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<PersistedSnoozedAlarm>()).map(\.id), [snoozeID])
    XCTAssertTrue(
      try migrated.mainContext.fetch(
        FetchDescriptor<PersistedRoutineSyncMutation>()
      ).isEmpty
    )
    XCTAssertTrue(
      try migrated.mainContext.fetch(
        FetchDescriptor<PersistedPendingAccountCleanup>()
      ).isEmpty
    )
  }

  @MainActor
  func testV4SyncFoundationMigratesToV5AcrossContainerReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("moru.store")
    let localID = UUID()

    do {
      let schema = Schema(versionedSchema: MoruSchemaV4.self)
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
      let repository = SwiftDataRoutineSyncRepository(
        modelContext: container.mainContext
      )
      _ = try repository.recordRemoteID(
        41,
        revision: nil,
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: localID,
        at: Date(timeIntervalSince1970: 10)
      )
      _ = try repository.enqueue(
        EnqueuedRoutineSyncMutation(
          memberID: 7,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: localID,
          payload: Data(#"{"title":"아침"}"#.utf8)
        ),
        at: Date(timeIntervalSince1970: 10)
      )
    }

    let reopened = try ModelContainer.moruContainer(storeURL: storeURL)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: reopened.mainContext
    )

    XCTAssertEqual(
      try repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: localID
      )?.remoteID,
      41
    )
    XCTAssertEqual(try repository.mutations(memberID: 7).count, 1)
  }

  @MainActor
  func testFreshResetDeletesBindingsAndMutationsButPreservesWithdrawalRecovery() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    let localID = UUID()
    _ = try repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: localID,
      at: Date(timeIntervalSince1970: 10)
    )
    _ = try repository.enqueue(
      EnqueuedRoutineSyncMutation(
        memberID: 7,
        operation: .createRoutineGroup,
        entityKind: .routineGroup,
        localEntityID: localID,
        payload: Data(#"{"title":"아침"}"#.utf8)
      ),
      at: Date(timeIntervalSince1970: 10)
    )
    try repository.preparePendingAccountCleanup(
      memberID: 7,
      at: Date(timeIntervalSince1970: 11)
    )

    try SwiftDataLocalDataResetRepository(
      modelContext: container.mainContext
    ).resetToFreshInstallState()

    XCTAssertTrue(
      try container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).isEmpty
    )
    XCTAssertTrue(
      try container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineSyncMutation>()
      ).isEmpty
    )
    XCTAssertEqual(
      try container.mainContext.fetch(
        FetchDescriptor<PersistedPendingAccountCleanup>()
      ).count,
      1
    )
  }

  @MainActor
  func testRevisionNilPreservesExistingBindingRevision() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    _ = try repository.recordRemoteID(
      41,
      revision: "revision-1",
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: Date(timeIntervalSince1970: 1)
    )

    let updated = try repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: Date(timeIntervalSince1970: 2)
    )

    XCTAssertEqual(updated.remoteRevision, "revision-1")
  }

  @MainActor
  func testPartialCreateRejectsEveryBindingAndPreservesOutbox() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let childID = UUID()
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: "아침",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: [
          RoutineSyncRoutineSnapshot(
            localID: childID,
            title: "물 마시기",
            type: "confirm",
            durationSeconds: nil,
            order: 0
          )
        ]
      )
    )
    let mutation = try repository.enqueue(
      command: command,
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )

    XCTAssertThrowsError(
      try repository.completeCreateRoutineGroup(
        id: mutation.id,
        expectedGenerationID: mutation.generationID,
        assignments: [
          RoutineServerBindingAssignment(
            entityKind: .routineGroup,
            localEntityID: groupID,
            remoteID: 41
          )
        ],
        childMappingsComplete: false,
        at: Date(timeIntervalSince1970: 2)
      )
    ) { error in
      XCTAssertEqual(
        error as? RoutineSyncRepositoryError,
        .incompleteChildMapping
      )
    }

    XCTAssertNil(
      try repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: groupID
      )
    )
    XCTAssertNil(
      try repository.binding(
        memberID: 7,
        entityKind: .routine,
        localEntityID: childID
      )
    )
    XCTAssertEqual(try repository.mutations(memberID: 7).map(\.id), [mutation.id])
  }

  @MainActor
  func testGroupDeleteRemovesChildBindingsButPreservesExecutionBindings() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let childID = UUID()
    let executionID = UUID()
    _ = try repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: childID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
        RoutineServerBindingAssignment(
          entityKind: .routineExecution,
          localEntityID: executionID,
          remoteID: 61,
          parentEntityKind: .routine,
          parentLocalEntityID: childID
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let mutation = try repository.enqueue(
      command: .deleteRoutineGroup(groupLocalID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )

    try repository.completeDelete(
      id: mutation.id,
      expectedGenerationID: mutation.generationID,
      at: Date(timeIntervalSince1970: 3)
    )

    XCTAssertNil(try repository.binding(memberID: 7, entityKind: .routineGroup, localEntityID: groupID))
    XCTAssertNil(try repository.binding(memberID: 7, entityKind: .routine, localEntityID: childID))
    XCTAssertEqual(
      try repository.binding(
        memberID: 7,
        entityKind: .routineExecution,
        localEntityID: executionID
      )?.remoteID,
      61
    )
    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testAddAndExecutionSettlementAtomicallyBindAndRemoveOutboxRows() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let childID = UUID()
    let add = try repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: childID,
          title: "스트레칭",
          type: "timer",
          durationSeconds: 30,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    try repository.completeMutation(
      id: add.id,
      expectedGenerationID: add.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: childID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        )
      ],
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(
      try repository.binding(memberID: 7, entityKind: .routine, localEntityID: childID)?.parentLocalEntityID,
      groupID
    )

    let resultID = UUID()
    let execution = try repository.enqueue(
      command: .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          runLocalID: UUID(),
          groupLocalID: groupID,
          routineLocalID: childID,
          runStartedAt: Date(timeIntervalSince1970: 2),
          runCompletedAt: Date(timeIntervalSince1970: 3),
          timeZoneIdentifier: "Asia/Seoul",
          result: RoutineSyncExecutionResultSnapshot(
            localID: resultID,
            completedAt: Date(timeIntervalSince1970: 3),
            skipped: false,
            durationSeconds: 30,
            inputText: "입력",
            transcript: "전사"
          )
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    try repository.completeMutation(
      id: execution.id,
      expectedGenerationID: execution.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineExecution,
          localEntityID: resultID,
          remoteID: 61,
          parentEntityKind: .routine,
          parentLocalEntityID: childID
        )
      ],
      at: Date(timeIntervalSince1970: 4)
    )
    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(
      try repository.binding(
        memberID: 7,
        entityKind: .routineExecution,
        localEntityID: resultID
      )?.parentLocalEntityID,
      childID
    )
  }

  @MainActor
  func testInterruptedAttemptBecomesReconciliationWithoutChangingSnapshot() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let localID = UUID()
    let mutationID = UUID()
    let generationID = UUID()
    let payload = Data(#"{"title":"아침"}"#.utf8)
    container.mainContext.insert(
      PersistedRoutineSyncMutation(
        operationKey: "production|7|createRoutineGroup|routineGroup|\(localID.uuidString.lowercased())",
        id: mutationID,
        serverNamespaceRawValue: RoutineSyncServerNamespace.production.rawValue,
        memberID: 7,
        operationRawValue: RoutineSyncOperation.createRoutineGroup.rawValue,
        entityKindRawValue: RoutineSyncEntityKind.routineGroup.rawValue,
        localEntityID: localID,
        generationID: generationID,
        generation: 1,
        payloadVersion: 1,
        payload: payload,
        stateRawValue: RoutineSyncMutationState.attempting.rawValue,
        attemptedGenerationID: generationID,
        attemptedGeneration: 1,
        attemptedPayloadVersion: 1,
        attemptedPayload: payload,
        attemptedAt: Date(timeIntervalSince1970: 1),
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
      )
    )
    try container.mainContext.save()
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)

    try repository.recoverInterruptedAttempts(at: Date(timeIntervalSince1970: 2))

    let recovered = try XCTUnwrap(try repository.mutations(memberID: 7).first)
    XCTAssertEqual(recovered.state, .needsReconciliation)
    XCTAssertEqual(recovered.attempt?.generationID, generationID)
    XCTAssertEqual(recovered.attempt?.payload, payload)
  }

  @MainActor
  func testClaimPersistsExactSnapshotAcrossContainerReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("moru.store")
    let localID = UUID()
    let mutationID = UUID()
    let generationID = UUID()
    let payload = Data(#"{"title":"아침"}"#.utf8)

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      container.mainContext.insert(
        PersistedRoutineSyncMutation(
          operationKey: "production|7|createRoutineGroup|routineGroup|\(localID.uuidString.lowercased())",
          id: mutationID,
          serverNamespaceRawValue: RoutineSyncServerNamespace.production.rawValue,
          memberID: 7,
          operationRawValue: RoutineSyncOperation.createRoutineGroup.rawValue,
          entityKindRawValue: RoutineSyncEntityKind.routineGroup.rawValue,
          localEntityID: localID,
          generationID: generationID,
          generation: 1,
          payloadVersion: 1,
          payload: payload,
          stateRawValue: RoutineSyncMutationState.queued.rawValue,
          createdAt: Date(timeIntervalSince1970: 1),
          updatedAt: Date(timeIntervalSince1970: 1)
        )
      )
      try container.mainContext.save()
      let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
      let claimed = try XCTUnwrap(
        repository.claimForDelivery(id: mutationID, at: Date(timeIntervalSince1970: 2))
      )
      XCTAssertEqual(claimed.generationID, generationID)
      XCTAssertEqual(claimed.payload, payload)
    }

    let reopened = try ModelContainer.moruContainer(storeURL: storeURL)
    let repository = SwiftDataRoutineSyncRepository(modelContext: reopened.mainContext)
    let mutation = try XCTUnwrap(try repository.mutations(memberID: 7).first)
    XCTAssertEqual(mutation.state, .attempting)
    XCTAssertEqual(mutation.attempt?.generationID, generationID)
    XCTAssertEqual(mutation.attempt?.payload, payload)
  }

  @MainActor
  func testAtomicSettlementConflictRollsBackBindingAndOutboxChange() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let alreadyBoundChildID = UUID()
    let newChildID = UUID()
    _ = try repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: alreadyBoundChildID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let mutation = try repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: newChildID,
          title: "새 단계",
          type: "confirm",
          durationSeconds: nil,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )

    XCTAssertThrowsError(
      try repository.completeMutation(
        id: mutation.id,
        expectedGenerationID: mutation.generationID,
        assignments: [
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: newChildID,
            remoteID: 51,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: groupID
          )
        ],
        at: Date(timeIntervalSince1970: 3)
      )
    )
    XCTAssertNil(
      try repository.binding(memberID: 7, entityKind: .routine, localEntityID: newChildID)
    )
    XCTAssertEqual(try repository.mutations(memberID: 7).map(\.id), [mutation.id])
  }

  @MainActor
  func testLateExecutionAttemptSuccessDropsCoalescedSuccessor() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let resultID = UUID()
    let runID = UUID()
    let groupID = UUID()
    let routineID = UUID()
    func command(inputText: String?) -> RoutineSyncCommand {
      .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          runLocalID: runID,
          groupLocalID: groupID,
          routineLocalID: routineID,
          runStartedAt: Date(timeIntervalSince1970: 1),
          runCompletedAt: Date(timeIntervalSince1970: 2),
          timeZoneIdentifier: "Asia/Seoul",
          result: RoutineSyncExecutionResultSnapshot(
            localID: resultID,
            completedAt: Date(timeIntervalSince1970: 2),
            skipped: false,
            durationSeconds: 10,
            inputText: inputText,
            transcript: nil
          )
        )
      )
    }
    let first = try repository.enqueue(
      command: command(inputText: nil),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let persisted = try XCTUnwrap(
      try container.mainContext.fetch(FetchDescriptor<PersistedRoutineSyncMutation>()).first
    )
    persisted.stateRawValue = RoutineSyncMutationState.queued.rawValue
    try container.mainContext.save()
    _ = try XCTUnwrap(
      repository.claimForDelivery(id: first.id, at: Date(timeIntervalSince1970: 2))
    )
    let newer = try repository.enqueue(
      command: command(inputText: "변경"),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    XCTAssertNotEqual(newer.generationID, first.generationID)
    XCTAssertEqual(newer.state, .attempting)

    try repository.removeCompleted(
      id: first.id,
      expectedGenerationID: first.generationID
    )

    // Production execution save is create-only. A local edit while its first
    // immutable attempt is in flight must not become a second POST with a new
    // key after that original request succeeds.
    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testPendingCleanupRecoveryUsesExplicitPhasesAndKeepsLocalDataCleanedMarker() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    _ = try repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: Date(timeIntervalSince1970: 1)
    )

    try repository.preparePendingAccountCleanup(memberID: 7, at: Date(timeIntervalSince1970: 2))
    let preparedRecovery = try repository.pendingAccountCleanupRecovery()
    XCTAssertEqual(preparedRecovery, .none)
    XCTAssertNotNil(try repository.binding(memberID: 7, entityKind: .routineGroup, localEntityID: groupID))

    try repository.preparePendingAccountCleanup(memberID: 7, at: Date(timeIntervalSince1970: 3))
    try repository.beginPendingAccountCleanupAttempt(memberID: 7)
    let ambiguousRecovery = try repository.pendingAccountCleanupRecovery()
    XCTAssertTrue(ambiguousRecovery.blocksSessionRestoration)
    XCTAssertNotNil(try repository.binding(memberID: 7, entityKind: .routineGroup, localEntityID: groupID))

    try repository.confirmPendingAccountCleanup(memberID: 7)
    try repository.completePendingAccountCleanup(memberID: 7)
    let cleanedRecovery = try repository.pendingAccountCleanupRecovery()
    XCTAssertEqual(cleanedRecovery.completedMemberIDs, [7])
    XCTAssertNil(try repository.binding(memberID: 7, entityKind: .routineGroup, localEntityID: groupID))
    XCTAssertEqual(
      try container.mainContext.fetch(FetchDescriptor<PersistedPendingAccountCleanup>()).count,
      1
    )

    try repository.finalizePendingAccountCleanup(memberID: 7)
    XCTAssertTrue(
      try container.mainContext.fetch(FetchDescriptor<PersistedPendingAccountCleanup>()).isEmpty
    )
  }

  @MainActor
  func testAttemptingPendingCleanupCanBeginAgainForExplicitRemoteRetry() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )

    try repository.preparePendingAccountCleanup(
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    try repository.beginPendingAccountCleanupAttempt(memberID: 7)

    // A timeout or lost response leaves `.attempting`. A user-confirmed retry
    // must be able to cross the same durable boundary and issue DELETE again.
    try repository.preparePendingAccountCleanup(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    try repository.beginPendingAccountCleanupAttempt(memberID: 7)

    XCTAssertEqual(
      try repository.pendingAccountCleanupRecovery().ambiguousMemberIDs,
      [7]
    )
  }

  @MainActor
  func testCorruptPendingCleanupMarkerFailsClosedBeforeRecoveryCanRestoreSession() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    container.mainContext.insert(
      PersistedPendingAccountCleanup(
        cleanupKey: "production|7",
        id: UUID(),
        serverNamespaceRawValue: RoutineSyncServerNamespace.staging.rawValue,
        memberID: 7,
        phaseRawValue: PendingAccountCleanupPhase.prepared.rawValue,
        createdAt: Date(timeIntervalSince1970: 1)
      )
    )
    try container.mainContext.save()
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)

    XCTAssertThrowsError(try repository.pendingAccountCleanupRecovery()) { error in
      XCTAssertEqual(
        error as? RoutineSyncRepositoryError,
        .corruptedStoredValue(field: "PersistedPendingAccountCleanup")
      )
    }
    XCTAssertThrowsError(try repository.beginPendingAccountCleanupAttempt(memberID: 7)) { error in
      XCTAssertEqual(
        error as? RoutineSyncRepositoryError,
        .corruptedStoredValue(field: "PersistedPendingAccountCleanup")
      )
    }
  }

  @MainActor
  func testUnknownPendingCleanupPhaseFailsClosed() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    container.mainContext.insert(
      PersistedPendingAccountCleanup(
        cleanupKey: "production|7",
        id: UUID(),
        serverNamespaceRawValue: RoutineSyncServerNamespace.production.rawValue,
        memberID: 7,
        phaseRawValue: "future-or-corrupt-phase",
        createdAt: Date(timeIntervalSince1970: 1)
      )
    )
    try container.mainContext.save()

    XCTAssertThrowsError(
      try SwiftDataRoutineSyncRepository(
        modelContext: container.mainContext
      ).pendingAccountCleanupRecovery()
    ) { error in
      XCTAssertEqual(
        error as? RoutineSyncRepositoryError,
        .corruptedStoredValue(field: "PersistedPendingAccountCleanup")
      )
    }
  }

  @MainActor
  func testPartialCreateRejectsExtraChildAssignmentAndRollsBack() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let childID = UUID()
    let mutation = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: [childID]),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )

    XCTAssertThrowsError(
      try repository.completeCreateRoutineGroup(
        id: mutation.id,
        expectedGenerationID: mutation.generationID,
        assignments: [
          RoutineServerBindingAssignment(
            entityKind: .routineGroup,
            localEntityID: groupID,
            remoteID: 41
          ),
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: childID,
            remoteID: 51,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: groupID
          ),
        ],
        childMappingsComplete: false,
        at: Date(timeIntervalSince1970: 2)
      )
    )
    XCTAssertNil(try repository.binding(memberID: 7, entityKind: .routineGroup, localEntityID: groupID))
    XCTAssertEqual(try repository.mutations(memberID: 7).map(\.id), [mutation.id])
  }

  @MainActor
  func testAtomicAddSettlementRejectsExtraAssignmentAndRollsBack() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let childID = UUID()
    let mutation = try repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: childID,
          title: "추가",
          type: "confirm",
          durationSeconds: nil,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )

    XCTAssertThrowsError(
      try repository.completeMutation(
        id: mutation.id,
        expectedGenerationID: mutation.generationID,
        assignments: [
          RoutineServerBindingAssignment(
            entityKind: .routine,
            localEntityID: childID,
            remoteID: 51,
            parentEntityKind: .routineGroup,
            parentLocalEntityID: groupID
          ),
          RoutineServerBindingAssignment(
            entityKind: .routineGroup,
            localEntityID: groupID,
            remoteID: 41
          ),
        ],
        at: Date(timeIntervalSince1970: 2)
      )
    )
    XCTAssertNil(try repository.binding(memberID: 7, entityKind: .routine, localEntityID: childID))
    XCTAssertNil(try repository.binding(memberID: 7, entityKind: .routineGroup, localEntityID: groupID))
    XCTAssertEqual(try repository.mutations(memberID: 7).map(\.id), [mutation.id])
  }

  @MainActor
  func testCompletedOldAddDropsUnsupportedEditedSuccessorWithoutSecondPost() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let childID = UUID()
    let first = try repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: childID,
          title: "처음",
          type: "confirm",
          durationSeconds: nil,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let persisted = try XCTUnwrap(
      try container.mainContext.fetch(FetchDescriptor<PersistedRoutineSyncMutation>()).first
    )
    persisted.stateRawValue = RoutineSyncMutationState.queued.rawValue
    try container.mainContext.save()
    _ = try XCTUnwrap(repository.claimForDelivery(id: first.id, at: Date(timeIntervalSince1970: 2)))
    _ = try repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: childID,
          title: "수정했지만 PATCH 없음",
          type: "confirm",
          durationSeconds: 10,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    try repository.completeMutation(
      id: first.id,
      expectedGenerationID: first.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: childID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        )
      ],
      at: Date(timeIntervalSince1970: 4)
    )

    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(
      try repository.binding(memberID: 7, entityKind: .routine, localEntityID: childID)?.remoteID,
      51
    )
  }

  @MainActor
  func testCompletedOldCreateTurnsNewChildIntoAddWithoutSecondCreate() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let firstChildID = UUID()
    let addedChildID = UUID()
    let first = try enqueueClaimedCreate(
      repository: repository,
      context: container.mainContext,
      command: createGroupCommand(groupID: groupID, children: [firstChildID])
    )
    _ = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: [firstChildID, addedChildID]),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    try repository.completeCreateRoutineGroup(
      id: first.id,
      expectedGenerationID: first.generationID,
      assignments: [
        RoutineServerBindingAssignment(entityKind: .routineGroup, localEntityID: groupID, remoteID: 41),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: firstChildID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      childMappingsComplete: true,
      at: Date(timeIntervalSince1970: 4)
    )

    let remaining = try XCTUnwrap(try repository.mutations(memberID: 7).first)
    XCTAssertEqual(remaining.operation, .addRoutine)
    XCTAssertEqual(
      try JSONDecoder().decode(RoutineSyncCommand.self, from: remaining.payload),
      .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: addedChildID,
          title: "단계 \(addedChildID.uuidString.prefix(4))",
          type: "confirm",
          durationSeconds: nil,
          order: 1
        )
      )
    )
  }

  @MainActor
  func testCompletedOldCreateTurnsRemovedMappedChildIntoDelete() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let childID = UUID()
    let first = try enqueueClaimedCreate(
      repository: repository,
      context: container.mainContext,
      command: createGroupCommand(groupID: groupID, children: [childID])
    )
    _ = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    try repository.completeCreateRoutineGroup(
      id: first.id,
      expectedGenerationID: first.generationID,
      assignments: [
        RoutineServerBindingAssignment(entityKind: .routineGroup, localEntityID: groupID, remoteID: 41),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: childID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      childMappingsComplete: true,
      at: Date(timeIntervalSince1970: 4)
    )

    let remaining = try XCTUnwrap(try repository.mutations(memberID: 7).first)
    XCTAssertEqual(
      try JSONDecoder().decode(RoutineSyncCommand.self, from: remaining.payload),
      .deleteRoutine(groupLocalID: groupID, routineLocalID: childID)
    )
  }

  @MainActor
  func testCompletedOldCreateDropsTitleOnlySuccessorAsLocalProjectionDrift() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let childID = UUID()
    let first = try enqueueClaimedCreate(
      repository: repository,
      context: container.mainContext,
      command: createGroupCommand(groupID: groupID, children: [childID], name: "처음")
    )
    _ = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: [childID], name: "로컬 수정"),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    try repository.completeCreateRoutineGroup(
      id: first.id,
      expectedGenerationID: first.generationID,
      assignments: [
        RoutineServerBindingAssignment(entityKind: .routineGroup, localEntityID: groupID, remoteID: 41),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: childID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      childMappingsComplete: true,
      at: Date(timeIntervalSince1970: 4)
    )

    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testAdmissionRequiresVerifiedOperationSpecificServerContract() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    _ = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )

    XCTAssertTrue(try repository.admitEligibleMutations(
      memberID: 7,
      contract: .unavailable,
      at: Date(timeIntervalSince1970: 2)
    ).isEmpty)
    XCTAssertTrue(try repository.admitEligibleMutations(
      memberID: 7,
      contract: RoutineSyncServerContract(
        capabilities: .allRequired,
        isE2EVerified: false
      ),
      at: Date(timeIntervalSince1970: 3)
    ).isEmpty)
    XCTAssertTrue(try repository.admitEligibleMutations(
      memberID: 7,
      contract: RoutineSyncServerContract(
        capabilities: .allRequired.subtracting(.clientEntityID),
        isE2EVerified: true
      ),
      at: Date(timeIntervalSince1970: 3)
    ).isEmpty)
    XCTAssertEqual(try repository.mutations(memberID: 7).first?.state, .waitingForServerContract)

    let admitted = try repository.admitEligibleMutations(
      memberID: 7,
      contract: verifiedServerContract,
      at: Date(timeIntervalSince1970: 4)
    )
    XCTAssertEqual(admitted.count, 1)
    XCTAssertEqual(admitted.first?.operation, .createRoutineGroup)
    XCTAssertEqual(admitted.first?.state, .queued)
  }

  @MainActor
  func testAdmissionHonorsCreateAddExecutionDependencyOrder() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let routineID = UUID()
    let resultID = UUID()
    let create = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let add = try repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: routineID,
          title: "단계",
          type: "confirm",
          durationSeconds: nil,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let execution = try repository.enqueue(
      command: .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          runLocalID: UUID(),
          groupLocalID: groupID,
          routineLocalID: routineID,
          runStartedAt: Date(timeIntervalSince1970: 1),
          runCompletedAt: Date(timeIntervalSince1970: 2),
          timeZoneIdentifier: "UTC",
          result: RoutineSyncExecutionResultSnapshot(
            localID: resultID,
            completedAt: Date(timeIntervalSince1970: 2),
            skipped: false,
            durationSeconds: 1,
            inputText: nil,
            transcript: nil
          )
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    XCTAssertEqual(
      try repository.admitEligibleMutations(
        memberID: 7,
        contract: verifiedServerContract,
        at: Date(timeIntervalSince1970: 4)
      ).map(\.id),
      [create.id]
    )
    try repository.completeCreateRoutineGroup(
      id: create.id,
      expectedGenerationID: create.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        )
      ],
      childMappingsComplete: true,
      at: Date(timeIntervalSince1970: 5)
    )

    XCTAssertEqual(
      try repository.admitEligibleMutations(
        memberID: 7,
        contract: verifiedServerContract,
        at: Date(timeIntervalSince1970: 6)
      ).map(\.id),
      [add.id]
    )
    _ = try XCTUnwrap(repository.claimForDelivery(id: add.id, at: Date(timeIntervalSince1970: 7)))
    try repository.completeMutation(
      id: add.id,
      expectedGenerationID: add.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: routineID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        )
      ],
      at: Date(timeIntervalSince1970: 8)
    )

    XCTAssertEqual(
      try repository.admitEligibleMutations(
        memberID: 7,
        contract: verifiedServerContract,
        at: Date(timeIntervalSince1970: 9)
      ).map(\.id),
      [execution.id]
    )
  }

  @MainActor
  func testAdmissionSettlesActiveAndExecutionBeforeChildAndGroupDeletes() throws {
    let repository = try makeRepository()
    let groupID = UUID()
    let routineID = UUID()
    let resultID = UUID()
    _ = try repository.recordRemoteIDs(
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
      at: Date(timeIntervalSince1970: 1)
    )
    let active = try repository.enqueue(
      command: .selectActiveRoutineGroup(selectedGroupLocalID: nil),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let execution = try repository.enqueue(
      command: .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          runLocalID: UUID(),
          groupLocalID: groupID,
          routineLocalID: routineID,
          runStartedAt: Date(timeIntervalSince1970: 2),
          runCompletedAt: Date(timeIntervalSince1970: 3),
          timeZoneIdentifier: "UTC",
          result: RoutineSyncExecutionResultSnapshot(
            localID: resultID,
            completedAt: Date(timeIntervalSince1970: 3),
            skipped: false,
            durationSeconds: 1,
            inputText: nil,
            transcript: nil
          )
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    let deleteRoutine = try repository.enqueue(
      command: .deleteRoutine(groupLocalID: groupID, routineLocalID: routineID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 4)
    )
    let deleteGroup = try repository.enqueue(
      command: .deleteRoutineGroup(groupLocalID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 5)
    )

    XCTAssertEqual(
      try repository.admitEligibleMutations(
        memberID: 7,
        contract: verifiedServerContract,
        at: Date(timeIntervalSince1970: 6)
      ).map(\.id),
      [active.id, execution.id]
    )
    try repository.removeCompleted(
      id: active.id,
      expectedGenerationID: active.generationID
    )
    try repository.completeMutation(
      id: execution.id,
      expectedGenerationID: execution.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineExecution,
          localEntityID: resultID,
          remoteID: 61,
          parentEntityKind: .routine,
          parentLocalEntityID: routineID
        )
      ],
      at: Date(timeIntervalSince1970: 7)
    )

    XCTAssertEqual(
      try repository.admitEligibleMutations(
        memberID: 7,
        contract: verifiedServerContract,
        at: Date(timeIntervalSince1970: 8)
      ).map(\.id),
      [deleteRoutine.id]
    )
    try repository.completeDelete(
      id: deleteRoutine.id,
      expectedGenerationID: deleteRoutine.generationID,
      at: Date(timeIntervalSince1970: 9)
    )
    XCTAssertEqual(
      try repository.admitEligibleMutations(
        memberID: 7,
        contract: verifiedServerContract,
        at: Date(timeIntervalSince1970: 10)
      ).map(\.id),
      [deleteGroup.id]
    )
  }

  @MainActor
  func testProductionDeleteWaitsForPendingActiveSelectionUnderAtomicSingleActive() throws {
    // productionP0 now includes .atomicSingleActive (see PR #207), so
    // setRoutineGroupActive is supported in production and a pending
    // active-selection mutation for a group must settle before that group's
    // delete is admitted, per dependenciesAreSatisfied's .deleteRoutineGroup
    // handling of .selectActiveRoutineGroup dependents.
    let repository = try makeRepository()
    let groupID = UUID()
    _ = try repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: Date(timeIntervalSince1970: 1)
    )
    let active = try repository.enqueue(
      command: .selectActiveRoutineGroup(selectedGroupLocalID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let delete = try repository.enqueue(
      command: .deleteRoutineGroup(groupLocalID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    let admitted = try repository.admitEligibleMutations(
      memberID: 7,
      contract: .productionP0,
      at: Date(timeIntervalSince1970: 4)
    )

    XCTAssertEqual(admitted.map(\.id), [active.id])
    XCTAssertEqual(
      try repository.mutations(memberID: 7).first { $0.id == delete.id }?.state,
      .waitingForServerContract
    )
  }

  @MainActor
  func testReconciliationKeepsAttemptAndCoalescesLatestDesiredCreateGraph() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let firstChildID = UUID()
    let addedChildID = UUID()
    let first = try enqueueClaimedCreate(
      repository: repository,
      context: container.mainContext,
      command: createGroupCommand(groupID: groupID, children: [firstChildID])
    )
    XCTAssertThrowsError(
      try repository.completeCreateRoutineGroup(
        id: first.id,
        expectedGenerationID: first.generationID,
        assignments: [
          RoutineServerBindingAssignment(
            entityKind: .routineGroup,
            localEntityID: groupID,
            remoteID: 41
          )
        ],
        childMappingsComplete: false,
        at: Date(timeIntervalSince1970: 3)
      )
    )

    let desired = try repository.enqueue(
      command: createGroupCommand(
        groupID: groupID,
        children: [firstChildID, addedChildID]
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 4)
    )
    XCTAssertEqual(desired.state, .attempting)
    XCTAssertEqual(desired.attempt?.generationID, first.generationID)
    XCTAssertNotEqual(desired.generationID, first.generationID)

    try repository.completeCreateRoutineGroup(
      id: first.id,
      expectedGenerationID: first.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: firstChildID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      childMappingsComplete: true,
      at: Date(timeIntervalSince1970: 5)
    )

    let successor = try XCTUnwrap(try repository.mutations(memberID: 7).first)
    XCTAssertEqual(successor.operation, .addRoutine)
    XCTAssertEqual(successor.localEntityID, addedChildID)
  }

  @MainActor
  func testNotCommittedCreateCollapsesDependencyBlockedDeleteGraph() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let childID = UUID()
    let first = try enqueueClaimedCreate(
      repository: repository,
      context: container.mainContext,
      command: createGroupCommand(groupID: groupID, children: [childID])
    )
    try repository.markNeedsReconciliation(
      id: first.id,
      expectedGenerationID: first.generationID,
      at: Date(timeIntervalSince1970: 3)
    )
    _ = try repository.enqueue(
      command: .deleteRoutineGroup(groupLocalID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 4)
    )

    try repository.resolveNotCommitted(
      id: first.id,
      expectedGenerationID: first.generationID,
      at: Date(timeIntervalSince1970: 5)
    )

    XCTAssertTrue(try repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testNotCommittedCreateDropsExecutionForChildRemovedFromDesiredGraph() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let groupID = UUID()
    let childID = UUID()
    let resultID = UUID()
    let first = try enqueueClaimedCreate(
      repository: repository,
      context: container.mainContext,
      command: createGroupCommand(groupID: groupID, children: [childID])
    )
    _ = try repository.enqueue(
      command: .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          runLocalID: UUID(),
          groupLocalID: groupID,
          routineLocalID: childID,
          runStartedAt: Date(timeIntervalSince1970: 1),
          runCompletedAt: Date(timeIntervalSince1970: 2),
          timeZoneIdentifier: "UTC",
          result: RoutineSyncExecutionResultSnapshot(
            localID: resultID,
            completedAt: Date(timeIntervalSince1970: 2),
            skipped: false,
            durationSeconds: 1,
            inputText: nil,
            transcript: nil
          )
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    let desired = try repository.enqueue(
      command: createGroupCommand(groupID: groupID, children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 4)
    )

    try repository.resolveNotCommitted(
      id: first.id,
      expectedGenerationID: first.generationID,
      at: Date(timeIntervalSince1970: 5)
    )

    let remaining = try repository.mutations(memberID: 7)
    XCTAssertEqual(remaining.count, 1)
    XCTAssertEqual(remaining.first?.id, first.id)
    XCTAssertEqual(remaining.first?.generationID, desired.generationID)
    XCTAssertEqual(remaining.first?.state, .waitingForServerContract)
    XCTAssertNil(remaining.first?.attempt)
  }

  @MainActor
  func testAdmissionRejectsVerifiedContractFromDifferentNamespace() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext,
      serverNamespace: .staging
    )
    _ = try repository.enqueue(
      command: createGroupCommand(groupID: UUID(), children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )

    XCTAssertTrue(try repository.admitEligibleMutations(
      memberID: 7,
      contract: verifiedServerContract,
      at: Date(timeIntervalSince1970: 2)
    ).isEmpty)
    XCTAssertEqual(try repository.mutations(memberID: 7).first?.state, .waitingForServerContract)
  }

  @MainActor
  private func makeRepository() throws -> SwiftDataRoutineSyncRepository {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    return SwiftDataRoutineSyncRepository(modelContainer: container)
  }

  @MainActor
  private func enqueueClaimedCreate(
    repository: SwiftDataRoutineSyncRepository,
    context: ModelContext,
    command: RoutineSyncCommand
  ) throws -> RoutineSyncMutation {
    let mutation = try repository.enqueue(
      command: command,
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let persisted = try XCTUnwrap(
      try context.fetch(FetchDescriptor<PersistedRoutineSyncMutation>()).first
    )
    persisted.stateRawValue = RoutineSyncMutationState.queued.rawValue
    try context.save()
    _ = try XCTUnwrap(repository.claimForDelivery(id: mutation.id, at: Date(timeIntervalSince1970: 2)))
    return mutation
  }

  private func createGroupCommand(
    groupID: UUID,
    children: [UUID],
    name: String = "그룹"
  ) -> RoutineSyncCommand {
    .createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: name,
        summary: "",
        isActive: false,
        alarm: nil,
        routines: children.enumerated().map { index, childID in
          RoutineSyncRoutineSnapshot(
            localID: childID,
            title: "단계 \(childID.uuidString.prefix(4))",
            type: "confirm",
            durationSeconds: nil,
            order: index
          )
        }
      )
    )
  }

  private func mutation(
    localID: UUID,
    payload: Data
  ) -> EnqueuedRoutineSyncMutation {
    EnqueuedRoutineSyncMutation(
      memberID: 7,
      operation: .setRoutineGroupActive,
      entityKind: .routineGroup,
      localEntityID: localID,
      payload: payload
    )
  }

  private var verifiedServerContract: RoutineSyncServerContract {
    RoutineSyncServerContract(
      capabilities: .allRequired,
      isE2EVerified: true
    )
  }
}
