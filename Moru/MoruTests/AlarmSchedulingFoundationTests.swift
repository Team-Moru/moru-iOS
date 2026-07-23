//
//  AlarmSchedulingFoundationTests.swift
//  MoruTests
//
//  Created by Codex on 7/23/26.
//

import AlarmKit
import Foundation
import SwiftData
import XCTest
@testable import Moru

final class AlarmSchedulingFoundationTests: XCTestCase {
  @MainActor
  func testAlarmKitWeeklyScheduleMapsLocalTimeAndWeekdaysDirectly() throws {
    let request = makeRequest(
      hour: 6,
      minute: 35,
      weekdays: [.friday, .monday, .wednesday]
    )

    guard case .relative(let relative) = AlarmKitSchedulingAdapter.makeSchedule(
      from: request
    ) else {
      return XCTFail("Expected a relative AlarmKit schedule.")
    }

    XCTAssertEqual(relative.time.hour, 6)
    XCTAssertEqual(relative.time.minute, 35)
    guard case .weekly(let weekdays) = relative.repeats else {
      return XCTFail("Expected weekly recurrence.")
    }
    XCTAssertEqual(weekdays, [.monday, .wednesday, .friday])
  }

  @MainActor
  func testFallbackRequestIdentifiersAreStableAndUniquePerWeekday() {
    let scheduleID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let monday = UserNotificationAlarmSchedulingAdapter.requestIdentifier(
      scheduleID: scheduleID,
      weekday: .monday
    )
    let sunday = UserNotificationAlarmSchedulingAdapter.requestIdentifier(
      scheduleID: scheduleID,
      weekday: .sunday
    )

    XCTAssertEqual(
      monday,
      "moru.alarm.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.weekday.2"
    )
    XCTAssertEqual(
      sunday,
      "moru.alarm.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.weekday.1"
    )
    XCTAssertNotEqual(monday, sunday)
  }

  @MainActor
  func testCoordinatorUsesAlarmKitWhenAuthorized() async throws {
    let fixture = makeFixture()
    let routine = makeRoutine()
    fixture.routineRepository.routines = [routine]

    let result = try await fixture.coordinator.apply(
      .synchronize(routines: [routine])
    )

    XCTAssertEqual(fixture.primary.scheduleRequests.count, 1)
    XCTAssertTrue(fixture.fallback.scheduleRequests.isEmpty)
    XCTAssertEqual(result.records.first?.backend, .alarmKit)
    XCTAssertEqual(result.records.first?.state, .scheduled)
    XCTAssertEqual(
      fixture.stateRepository.records.values.first?.request.fingerprint,
      AlarmScheduleRequest(routine: routine)?.fingerprint
    )
  }

  @MainActor
  func testCoordinatorFallsBackOnlyAfterAlarmKitDenialOrSchedulingFailure()
    async throws {
    let deniedFixture = makeFixture(primaryAuthorization: .denied)
    let deniedRoutine = makeRoutine(name: "권한 거부")
    deniedFixture.routineRepository.routines = [deniedRoutine]

    let deniedResult = try await deniedFixture.coordinator.apply(
      .synchronize(routines: [deniedRoutine])
    )

    XCTAssertTrue(deniedFixture.primary.scheduleRequests.isEmpty)
    XCTAssertEqual(deniedFixture.fallback.scheduleRequests.count, 1)
    XCTAssertEqual(deniedResult.records.first?.backend, .localNotification)

    let failedFixture = makeFixture()
    failedFixture.primary.scheduleError = AlarmSchedulingTestError.maximumLimit
    let failedRoutine = makeRoutine(name: "최대 개수")
    failedFixture.routineRepository.routines = [failedRoutine]

    let failedResult = try await failedFixture.coordinator.apply(
      .synchronize(routines: [failedRoutine])
    )

    XCTAssertEqual(failedFixture.primary.scheduleRequests.count, 1)
    XCTAssertEqual(failedFixture.fallback.scheduleRequests.count, 1)
    XCTAssertEqual(failedResult.records.first?.backend, .localNotification)
  }

  @MainActor
  func testBothBackendsDeniedPersistAuthorizationRequiredState() async throws {
    let fixture = makeFixture(
      primaryAuthorization: .denied,
      fallbackAuthorization: .denied
    )
    let routine = makeRoutine()
    fixture.routineRepository.routines = [routine]

    let result = try await fixture.coordinator.apply(
      .synchronize(routines: [routine])
    )

    XCTAssertEqual(result.records.first?.state, .authorizationRequired)
    XCTAssertNil(result.records.first?.backend)
    XCTAssertTrue(result.requiresRepair)
    XCTAssertEqual(
      fixture.stateRepository.records.values.first?.state,
      .authorizationRequired
    )
  }

  @MainActor
  func testProfileStatusDistinguishesFallbackAndRepairRequired() async throws {
    let fixture = makeFixture(primaryAuthorization: .denied)
    let profileService = AlarmProfileService(
      primaryScheduler: fixture.primary,
      fallbackScheduler: fixture.fallback,
      stateRepository: fixture.stateRepository,
      mutationCoordinator: fixture.coordinator
    )

    let fallbackStatus = await profileService.currentStatus()
    XCTAssertEqual(fallbackStatus, .fallbackConfigured)

    let request = makeRequest()
    try fixture.stateRepository.saveRecord(
      AlarmDeliveryRecord(
        request: request,
        backend: nil,
        state: .repairRequired,
        platformIdentifiers: [],
        lastErrorMessage: "test",
        updatedAt: Date()
      )
    )

    let repairStatus = await profileService.currentStatus()
    XCTAssertEqual(repairStatus, .repairRequired)
  }

  @MainActor
  func testReconcileRepairsMissingAlarmCancelsOrphanAndIsIdempotent() async throws {
    let fixture = makeFixture()
    let routine = makeRoutine()
    fixture.routineRepository.routines = [routine]
    _ = try await fixture.coordinator.apply(.synchronize(routines: [routine]))

    let scheduledIdentifier = try XCTUnwrap(
      fixture.stateRepository.records.values.first?.platformIdentifiers.first
    )
    fixture.primary.identifiers.remove(scheduledIdentifier)
    fixture.primary.identifiers.insert("00000000-0000-0000-0000-000000000099")

    await fixture.coordinator.reconcile()
    let scheduleCountAfterRepair = fixture.primary.scheduleRequests.count
    let cancellationCountAfterRepair = fixture.primary.cancellationBatches.count

    XCTAssertEqual(scheduleCountAfterRepair, 2)
    XCTAssertTrue(
      fixture.primary.cancellationBatches
        .joined()
        .contains("00000000-0000-0000-0000-000000000099")
    )
    XCTAssertTrue(fixture.primary.identifiers.contains(scheduledIdentifier))

    await fixture.coordinator.reconcile()

    XCTAssertEqual(fixture.primary.scheduleRequests.count, scheduleCountAfterRepair)
    XCTAssertEqual(
      fixture.primary.cancellationBatches.count,
      cancellationCountAfterRepair
    )
  }

  @MainActor
  func testRoutineConflictMutationReschedulesAffectedBatch() async throws {
    let fixture = makeFixture()
    let first = makeRoutine(
      name: "기존 루틴",
      weekdays: [.monday, .wednesday]
    )
    fixture.routineRepository.routines = [first]
    _ = try await fixture.coordinator.apply(.synchronize(routines: [first]))
    let useCase = RoutineSettingUseCase(
      routineRepository: fixture.routineRepository,
      alarmScheduleMutator: fixture.coordinator
    )
    let newRoutineID = UUID()

    _ = try await useCase.saveRoutine(
      from: RoutineSettingMutation(
        routineID: newRoutineID,
        name: "새 루틴",
        summary: "",
        hour: 7,
        minute: 10,
        selectedWeekdays: [.wednesday, .friday],
        steps: [
          RoutineStepMutation(
            id: UUID(),
            type: .confirm,
            title: "물 마시기",
            estimatedMinutes: 1
          ),
        ],
        isActive: true
      ),
      resolvingWeekdayConflict: true
    )

    let savedFirst = try XCTUnwrap(
      fixture.routineRepository.routines.first { $0.id == first.id }
    )
    let savedNew = try XCTUnwrap(
      fixture.routineRepository.routines.first { $0.id == newRoutineID }
    )
    XCTAssertEqual(savedFirst.alarmSchedule?.weekdays, [.monday])
    XCTAssertEqual(savedNew.alarmSchedule?.weekdays, [.wednesday, .friday])
    XCTAssertEqual(fixture.primary.scheduleRequests.count, 3)
    XCTAssertTrue(
      fixture.primary.cancellationBatches.joined().contains(
        first.alarmSchedule!.id.uuidString.lowercased()
      )
    )
  }

  @MainActor
  func testDeleteKeepsRoutineWhenPlatformCancellationFails() async throws {
    let fixture = makeFixture()
    let routine = makeRoutine()
    fixture.routineRepository.routines = [routine]
    _ = try await fixture.coordinator.apply(.synchronize(routines: [routine]))
    fixture.primary.cancelError = AlarmSchedulingTestError.unavailable
    let useCase = RoutineSettingUseCase(
      routineRepository: fixture.routineRepository,
      alarmScheduleMutator: fixture.coordinator
    )

    do {
      try await useCase.deleteRoutine(id: routine.id)
      XCTFail("Deletion must stop when platform cancellation fails.")
    } catch {
      XCTAssertNotNil(try fixture.routineRepository.routine(id: routine.id))
      XCTAssertEqual(
        fixture.stateRepository.records[routine.alarmSchedule!.id]?.state,
        .scheduled
      )
    }
  }

  @MainActor
  func testPlatformStateSaveFailureCompensatesNewAlarm() async {
    let fixture = makeFixture()
    let routine = makeRoutine()
    fixture.routineRepository.routines = [routine]
    fixture.stateRepository.saveError = AlarmSchedulingTestError.persistence

    do {
      _ = try await fixture.coordinator.apply(.synchronize(routines: [routine]))
      XCTFail("State persistence failure should be surfaced.")
    } catch {
      XCTAssertEqual(fixture.primary.scheduleRequests.count, 1)
      XCTAssertEqual(
        fixture.primary.cancellationBatches.last,
        [routine.alarmSchedule!.id.uuidString.lowercased()]
      )
      XCTAssertTrue(fixture.primary.identifiers.isEmpty)
    }
  }

  @MainActor
  func testSwiftDataPlatformAndSnoozeRecordsRoundTripAndReset() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataAlarmPlatformStateRepository(
      modelContext: container.mainContext
    )
    let delivery = AlarmDeliveryRecord(
      request: makeRequest(),
      backend: .alarmKit,
      state: .scheduled,
      platformIdentifiers: ["alarm-id"],
      lastErrorMessage: nil,
      updatedAt: Date(timeIntervalSince1970: 100)
    )
    let snooze = SnoozedAlarmRecord(
      id: UUID(),
      scheduleID: delivery.scheduleID,
      routineID: delivery.routineID,
      fireDate: Date(timeIntervalSince1970: 200),
      backend: .localNotification,
      platformIdentifiers: ["snooze-id"],
      createdAt: Date(timeIntervalSince1970: 150)
    )

    try repository.saveRecord(delivery)
    try repository.saveSnoozedAlarm(snooze)

    XCTAssertEqual(try repository.fetchRecords(), [delivery])
    XCTAssertEqual(try repository.fetchSnoozedAlarms(), [snooze])

    let replacement = SnoozedAlarmRecord(
      id: UUID(),
      scheduleID: delivery.scheduleID,
      routineID: delivery.routineID,
      fireDate: Date(timeIntervalSince1970: 300),
      backend: .alarmKit,
      platformIdentifiers: ["replacement-snooze-id"],
      createdAt: Date(timeIntervalSince1970: 250)
    )
    try repository.replaceSnoozedAlarm(
      scheduleID: delivery.scheduleID,
      with: replacement
    )

    XCTAssertEqual(try repository.fetchSnoozedAlarms(), [replacement])

    try SwiftDataLocalDataResetRepository(
      modelContext: container.mainContext
    ).resetToFreshInstallState()

    XCTAssertTrue(try repository.fetchRecords().isEmpty)
    XCTAssertTrue(try repository.fetchSnoozedAlarms().isEmpty)
  }

  @MainActor
  func testV1AndV2StoresMigrateToV3WithoutLosingExistingModels() throws {
    try assertMigrationFromV1()
    try assertMigrationFromV2()
  }

  @MainActor
  func testResetWaitsForInFlightMutationThenCancelsScheduledAlarm() async throws {
    let routineRepository = AlarmSchedulingTestRoutineRepository()
    let stateRepository = AlarmSchedulingTestStateRepository()
    let primary = BlockingAlarmSchedulingTestScheduler()
    let fallback = AlarmSchedulingTestScheduler(
      backend: .localNotification,
      authorization: .authorized
    )
    let coordinator = DefaultAlarmScheduleMutationCoordinator(
      routineRepository: routineRepository,
      stateRepository: stateRepository,
      primaryScheduler: primary,
      fallbackScheduler: fallback
    )
    let routine = makeRoutine()
    routineRepository.routines = [routine]

    let mutationTask = Task {
      try await coordinator.apply(.synchronize(routines: [routine]))
    }
    await primary.waitUntilSchedulingStarts()
    let resetTask = Task {
      try await coordinator.cancelAllForReset()
    }

    await Task.yield()
    XCTAssertTrue(primary.cancellationBatches.isEmpty)
    primary.finishScheduling()
    _ = try await mutationTask.value
    try await resetTask.value

    XCTAssertEqual(
      primary.cancellationBatches.last,
      [routine.alarmSchedule!.id.uuidString.lowercased()]
    )
    XCTAssertTrue(stateRepository.records.isEmpty)
  }

  @MainActor
  private func makeFixture(
    primaryAuthorization: AlarmAuthorizationState = .authorized,
    fallbackAuthorization: AlarmAuthorizationState = .authorized
  ) -> AlarmSchedulingFixture {
    let routineRepository = AlarmSchedulingTestRoutineRepository()
    let stateRepository = AlarmSchedulingTestStateRepository()
    let primary = AlarmSchedulingTestScheduler(
      backend: .alarmKit,
      authorization: primaryAuthorization
    )
    let fallback = AlarmSchedulingTestScheduler(
      backend: .localNotification,
      authorization: fallbackAuthorization
    )
    let coordinator = DefaultAlarmScheduleMutationCoordinator(
      routineRepository: routineRepository,
      stateRepository: stateRepository,
      primaryScheduler: primary,
      fallbackScheduler: fallback,
      now: { Date(timeIntervalSince1970: 100) }
    )
    return AlarmSchedulingFixture(
      routineRepository: routineRepository,
      stateRepository: stateRepository,
      primary: primary,
      fallback: fallback,
      coordinator: coordinator
    )
  }

  @MainActor
  private func makeRequest(
    hour: Int = 7,
    minute: Int = 10,
    weekdays: [Weekday] = [.monday, .wednesday]
  ) -> AlarmScheduleRequest {
    AlarmScheduleRequest(
      routineID: UUID(),
      scheduleID: UUID(),
      routineName: "활력 루틴",
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      soundName: "moru-default"
    )
  }

  @MainActor
  private func makeRoutine(
    name: String = "활력 루틴",
    weekdays: [Weekday] = [.monday, .wednesday]
  ) -> Routine {
    Routine(
      name: name,
      steps: [
        RoutineStep(type: .confirm, title: "물 마시기", order: 0),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 10,
        weekdays: weekdays
      )
    )
  }

  @MainActor
  private func assertMigrationFromV1() throws {
    let storeURL = temporaryStoreURL()
    defer { removeStore(at: storeURL) }
    let profileID = UUID()
    let routine = makePersistedRoutine()
    let run = makePersistedRun(routineID: routine.id)

    do {
      let schema = Schema(versionedSchema: MoruSchemaV1.self)
      let configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(for: schema, configurations: [configuration])
      container.mainContext.insert(
        PersistedLocalProfile(
          id: profileID,
          displayName: "V1 사용자",
          selectedVoiceID: VoiceProfile.yuna.id,
          createdAt: Date(timeIntervalSince1970: 1),
          updatedAt: Date(timeIntervalSince1970: 1)
        )
      )
      container.mainContext.insert(routine)
      container.mainContext.insert(run)
      try container.mainContext.save()
    }

    let migrated = try ModelContainer.moruContainer(storeURL: storeURL)
    XCTAssertEqual(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedLocalProfile>()).count,
      1
    )
    XCTAssertEqual(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutine>()).count,
      1
    )
    XCTAssertEqual(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedRoutineRun>()).count,
      1
    )
    XCTAssertTrue(
      try migrated.mainContext.fetch(
        FetchDescriptor<PersistedAlarmPlatformState>()
      ).isEmpty
    )
  }

  @MainActor
  private func assertMigrationFromV2() throws {
    let storeURL = temporaryStoreURL()
    defer { removeStore(at: storeURL) }
    let weatherID = UUID()

    do {
      let schema = Schema(versionedSchema: MoruSchemaV2.self)
      let configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(for: schema, configurations: [configuration])
      container.mainContext.insert(
        PersistedHomeWeatherSnapshot(
          id: weatherID,
          conditionRawValue: HomeWeatherCondition.clear.rawValue,
          temperatureCelsius: 22,
          latitudeE4: 375_666,
          longitudeE4: 1_269_781,
          fetchedAt: Date(timeIntervalSince1970: 1),
          fetchedTimeZoneIdentifier: "Asia/Seoul",
          fetchedUTCOffsetSeconds: 32_400
        )
      )
      try container.mainContext.save()
    }

    let migrated = try ModelContainer.moruContainer(storeURL: storeURL)
    XCTAssertEqual(
      try migrated.mainContext.fetch(
        FetchDescriptor<PersistedHomeWeatherSnapshot>()
      ).map(\.id),
      [weatherID]
    )
    XCTAssertTrue(
      try migrated.mainContext.fetch(FetchDescriptor<PersistedSnoozedAlarm>()).isEmpty
    )
  }

  private func makePersistedRoutine() -> PersistedRoutine {
    PersistedRoutine(
      id: UUID(),
      name: "이전 루틴",
      summary: "",
      goalTagsRawValue: "[]",
      steps: [
        PersistedRoutineStep(
          id: UUID(),
          presetItemID: nil,
          typeRawValue: RoutineStepType.confirm.rawValue,
          title: "물 마시기",
          instruction: "",
          order: 0,
          estimatedSeconds: 60,
          isRequired: true
        ),
      ],
      alarmSchedule: PersistedAlarmSchedule(
        id: UUID(),
        hour: 7,
        minute: 0,
        weekdaysRawValue: "[2]",
        soundName: "moru-default",
        isEnabled: true,
        includeWeather: false,
        includeFortune: false
      ),
      isActive: true,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
  }

  private func makePersistedRun(routineID: UUID) -> PersistedRoutineRun {
    PersistedRoutineRun(
      id: UUID(),
      routineID: routineID,
      routineName: "이전 루틴",
      startedAt: Date(timeIntervalSince1970: 2),
      completedAt: Date(timeIntervalSince1970: 3),
      results: [],
      plannedSteps: [
        PersistedRoutineStepSnapshot(
          id: UUID(),
          stepID: UUID(),
          stepTitle: "물 마시기",
          stepTypeRawValue: RoutineStepType.confirm.rawValue,
          stepOrder: 0,
          estimatedSeconds: 60,
          isRequired: true
        ),
      ],
      endedEarly: false,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
  }

  private func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("moru-alarm-\(UUID().uuidString).store")
  }

  private func removeStore(at storeURL: URL) {
    [
      storeURL,
      URL(fileURLWithPath: storeURL.path + "-shm"),
      URL(fileURLWithPath: storeURL.path + "-wal"),
    ].forEach { try? FileManager.default.removeItem(at: $0) }
  }
}

@MainActor
private struct AlarmSchedulingFixture {
  let routineRepository: AlarmSchedulingTestRoutineRepository
  let stateRepository: AlarmSchedulingTestStateRepository
  let primary: AlarmSchedulingTestScheduler
  let fallback: AlarmSchedulingTestScheduler
  let coordinator: DefaultAlarmScheduleMutationCoordinator
}

private enum AlarmSchedulingTestError: Error {
  case maximumLimit
  case unavailable
  case persistence
}

@MainActor
private final class AlarmSchedulingTestScheduler: AlarmScheduling {
  let backend: AlarmDeliveryBackend
  var authorization: AlarmAuthorizationState
  var requestedAuthorization: AlarmAuthorizationState?
  var scheduleError: Error?
  var cancelError: Error?
  var identifiers: Set<String> = []
  private(set) var scheduleRequests: [AlarmScheduleRequest] = []
  private(set) var cancellationBatches: [[String]] = []

  init(
    backend: AlarmDeliveryBackend,
    authorization: AlarmAuthorizationState
  ) {
    self.backend = backend
    self.authorization = authorization
  }

  func authorizationState() async -> AlarmAuthorizationState {
    authorization
  }

  func requestAuthorization() async throws -> AlarmAuthorizationState {
    if let requestedAuthorization {
      authorization = requestedAuthorization
    }
    return authorization
  }

  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String] {
    scheduleRequests.append(request)
    if let scheduleError {
      throw scheduleError
    }
    let scheduledIdentifiers: [String]
    switch backend {
    case .alarmKit:
      scheduledIdentifiers = [request.scheduleID.uuidString.lowercased()]
    case .localNotification:
      scheduledIdentifiers = request.weekdays.map {
        UserNotificationAlarmSchedulingAdapter.requestIdentifier(
          scheduleID: request.scheduleID,
          weekday: $0
        )
      }
    }
    identifiers.formUnion(scheduledIdentifiers)
    return scheduledIdentifiers
  }

  func scheduleSnooze(_ request: AlarmSnoozeRequest) async throws -> [String] {
    let identifiers = [request.alarmID.uuidString.lowercased()]
    self.identifiers.formUnion(identifiers)
    return identifiers
  }

  func stop(id: UUID) async throws {}

  func cancel(identifiers: [String]) async throws {
    cancellationBatches.append(identifiers)
    if let cancelError {
      throw cancelError
    }
    self.identifiers.subtract(identifiers)
  }

  func snapshot() async throws -> AlarmPlatformSnapshot {
    AlarmPlatformSnapshot(backend: backend, identifiers: identifiers)
  }
}

@MainActor
private final class BlockingAlarmSchedulingTestScheduler: AlarmScheduling {
  let backend = AlarmDeliveryBackend.alarmKit
  private(set) var cancellationBatches: [[String]] = []
  private var identifiers: Set<String> = []
  private var schedulingContinuation: CheckedContinuation<Void, Never>?
  private var didStartScheduling = false

  func authorizationState() async -> AlarmAuthorizationState {
    .authorized
  }

  func requestAuthorization() async throws -> AlarmAuthorizationState {
    .authorized
  }

  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String] {
    didStartScheduling = true
    await withCheckedContinuation { continuation in
      schedulingContinuation = continuation
    }
    let identifier = request.scheduleID.uuidString.lowercased()
    identifiers.insert(identifier)
    return [identifier]
  }

  func scheduleSnooze(_ request: AlarmSnoozeRequest) async throws -> [String] {
    let identifier = request.alarmID.uuidString.lowercased()
    identifiers.insert(identifier)
    return [identifier]
  }

  func stop(id: UUID) async throws {}

  func cancel(identifiers: [String]) async throws {
    cancellationBatches.append(identifiers)
    self.identifiers.subtract(identifiers)
  }

  func snapshot() async throws -> AlarmPlatformSnapshot {
    AlarmPlatformSnapshot(backend: backend, identifiers: identifiers)
  }

  func waitUntilSchedulingStarts() async {
    for _ in 0..<100 where !didStartScheduling {
      await Task.yield()
    }
  }

  func finishScheduling() {
    schedulingContinuation?.resume()
    schedulingContinuation = nil
  }
}

@MainActor
private final class AlarmSchedulingTestStateRepository:
  AlarmPlatformStateRepository {
  var records: [UUID: AlarmDeliveryRecord] = [:]
  var snoozedAlarms: [UUID: SnoozedAlarmRecord] = [:]
  var saveError: Error?

  func fetchRecords() throws -> [AlarmDeliveryRecord] {
    Array(records.values)
  }

  func record(scheduleID: UUID) throws -> AlarmDeliveryRecord? {
    records[scheduleID]
  }

  func saveRecord(_ record: AlarmDeliveryRecord) throws {
    if let saveError {
      throw saveError
    }
    records[record.scheduleID] = record
  }

  func deleteRecord(scheduleID: UUID) throws {
    records[scheduleID] = nil
  }

  func deleteAllRecords() throws {
    records.removeAll()
  }

  func fetchSnoozedAlarms() throws -> [SnoozedAlarmRecord] {
    Array(snoozedAlarms.values)
  }

  func saveSnoozedAlarm(_ record: SnoozedAlarmRecord) throws {
    snoozedAlarms[record.id] = record
  }

  func replaceSnoozedAlarm(
    scheduleID: UUID,
    with record: SnoozedAlarmRecord
  ) throws {
    snoozedAlarms = snoozedAlarms.filter {
      $0.value.scheduleID != scheduleID
    }
    snoozedAlarms[record.id] = record
  }

  func deleteSnoozedAlarm(id: UUID) throws {
    snoozedAlarms[id] = nil
  }

  func deleteAllSnoozedAlarms() throws {
    snoozedAlarms.removeAll()
  }
}

@MainActor
private final class AlarmSchedulingTestRoutineRepository: RoutineRepository {
  var routines: [Routine] = []

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
      if let index = self.routines.firstIndex(where: { $0.id == routine.id }) {
        self.routines[index] = routine
      } else {
        self.routines.append(routine)
      }
    }
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard let index = routines.firstIndex(where: { $0.id == id }) else {
      return
    }
    routines[index].isActive = isActive
  }

  func deleteRoutine(id: UUID) throws {
    routines.removeAll { $0.id == id }
  }
}
