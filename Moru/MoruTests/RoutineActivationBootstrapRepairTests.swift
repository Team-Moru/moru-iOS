//
//  RoutineActivationBootstrapRepairTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

@MainActor
final class RoutineActivationBootstrapRepairTests: XCTestCase {
  func testWinnerUsesUpdatedAtThenCreatedAtThenAscendingUUID() {
    let createdAt = Date(timeIntervalSince1970: 10)
    let updatedAt = Date(timeIntervalSince1970: 20)
    let newerUpdate = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000003"),
      createdAt: createdAt,
      updatedAt: Date(timeIntervalSince1970: 30)
    )
    let newerCreate = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000002"),
      createdAt: Date(timeIntervalSince1970: 11),
      updatedAt: updatedAt
    )
    let lexicographicallyFirst = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000001"),
      createdAt: createdAt,
      updatedAt: updatedAt
    )
    let lexicographicallyLast = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000004"),
      createdAt: createdAt,
      updatedAt: updatedAt
    )

    let newestUpdate = RoutineActivationBootstrapRepair.repair(
      routines: [newerCreate, lexicographicallyLast, newerUpdate]
    )
    XCTAssertEqual(newestUpdate?.winnerID, newerUpdate.id)

    let newestCreate = RoutineActivationBootstrapRepair.repair(
      routines: [lexicographicallyLast, newerCreate]
    )
    XCTAssertEqual(newestCreate?.winnerID, newerCreate.id)

    let uuidTie = RoutineActivationBootstrapRepair.repair(
      routines: [lexicographicallyLast, lexicographicallyFirst]
    )
    XCTAssertEqual(uuidTie?.winnerID, lexicographicallyFirst.id)
  }

  func testRepairDeactivatesLosersPreservesWeekdaysAndSavesOneBatch() throws {
    let winner = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000010"),
      createdAt: Date(timeIntervalSince1970: 10),
      updatedAt: Date(timeIntervalSince1970: 20),
      weekdays: [.friday]
    )
    let loser = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000020"),
      createdAt: Date(timeIntervalSince1970: 10),
      updatedAt: Date(timeIntervalSince1970: 10),
      weekdays: [.monday, .wednesday]
    )
    let repository = RoutineActivationRepairRepository(
      routines: [winner, loser]
    )
    let repairDate = Date(timeIntervalSince1970: 30)

    let result = try RoutineActivationBootstrapRepair.repairIfNeeded(
      in: repository,
      now: repairDate
    )

    XCTAssertEqual(result?.winnerID, winner.id)
    XCTAssertEqual(result?.deactivatedRoutineIDs, [loser.id])
    XCTAssertEqual(repository.saveBatches.count, 1)
    let savedWinner = try XCTUnwrap(
      repository.routines.first { $0.id == winner.id }
    )
    let savedLoser = try XCTUnwrap(
      repository.routines.first { $0.id == loser.id }
    )
    XCTAssertTrue(savedWinner.isActive)
    XCTAssertTrue(savedWinner.alarmSchedule?.isEnabled ?? false)
    XCTAssertFalse(savedLoser.isActive)
    XCTAssertFalse(savedLoser.alarmSchedule?.isEnabled ?? true)
    XCTAssertEqual(savedLoser.alarmSchedule?.weekdays, [.monday, .wednesday])
    XCTAssertEqual(savedLoser.updatedAt, repairDate)
  }

  func testRepairLeavesZeroOrOneActiveRoutineUntouched() throws {
    let inactive = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000030"),
      isActive: false
    )
    let active = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000040")
    )
    let zeroActiveRepository = RoutineActivationRepairRepository(
      routines: [inactive]
    )
    let oneActiveRepository = RoutineActivationRepairRepository(
      routines: [inactive, active]
    )

    XCTAssertNil(
      try RoutineActivationBootstrapRepair.repairIfNeeded(
        in: zeroActiveRepository
      )
    )
    XCTAssertNil(
      try RoutineActivationBootstrapRepair.repairIfNeeded(
        in: oneActiveRepository
      )
    )
    XCTAssertTrue(zeroActiveRepository.saveBatches.isEmpty)
    XCTAssertTrue(oneActiveRepository.saveBatches.isEmpty)
    XCTAssertEqual(zeroActiveRepository.routines, [inactive])
    XCTAssertEqual(oneActiveRepository.routines, [inactive, active])
  }

  func testPreflightDoesNotTouchAlarmPlatformWithoutDisabledRetainedRecord()
    async {
    let active = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000050")
    )
    let repository = RoutineActivationRepairRepository(routines: [active])
    let stateRepository = RoutineActivationAlarmStateRepository(
      records: [makeAlarmRecord(for: active)]
    )
    let alarmMutator = RoutineActivationAlarmMutator()

    await DefaultAppBootstrapPreflight.cancelDisabledAlarmRecordsIfNeeded(
      routineRepository: repository,
      alarmPlatformStateRepository: stateRepository,
      alarmScheduleMutator: alarmMutator
    )

    XCTAssertTrue(alarmMutator.appliedMutations.isEmpty)
    XCTAssertEqual(alarmMutator.reconcileCallCount, 0)
  }

  func testPreflightTargetsOnlyDisabledRoutineWithRetainedAlarmRecord() async {
    let active = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000060")
    )
    var disabledWithRecord = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000061"),
      isActive: false
    )
    disabledWithRecord.alarmSchedule?.isEnabled = false
    var disabledWithoutRecord = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000062"),
      isActive: false
    )
    disabledWithoutRecord.alarmSchedule?.isEnabled = false
    let repository = RoutineActivationRepairRepository(
      routines: [active, disabledWithRecord, disabledWithoutRecord]
    )
    let stateRepository = RoutineActivationAlarmStateRepository(
      records: [makeAlarmRecord(for: disabledWithRecord)]
    )
    let alarmMutator = RoutineActivationAlarmMutator()

    await DefaultAppBootstrapPreflight.cancelDisabledAlarmRecordsIfNeeded(
      routineRepository: repository,
      alarmPlatformStateRepository: stateRepository,
      alarmScheduleMutator: alarmMutator
    )

    XCTAssertEqual(alarmMutator.appliedMutations.count, 1)
    guard case .synchronize(let routines) = alarmMutator.appliedMutations[0] else {
      return XCTFail("Preflight must only issue a synchronization cancellation.")
    }
    XCTAssertEqual(routines, [disabledWithRecord])
    XCTAssertEqual(alarmMutator.reconcileCallCount, 0)
  }

  func testPreflightRetriesDisabledRoutineWithRetainedRepairRecord() async {
    var disabled = makeRoutine(
      id: uuid("00000000-0000-0000-0000-000000000070"),
      isActive: false
    )
    disabled.alarmSchedule?.isEnabled = false
    let repository = RoutineActivationRepairRepository(routines: [disabled])
    let stateRepository = RoutineActivationAlarmStateRepository(
      records: [makeAlarmRecord(for: disabled, state: .repairRequired)]
    )
    let alarmMutator = RoutineActivationAlarmMutator()

    await DefaultAppBootstrapPreflight.cancelDisabledAlarmRecordsIfNeeded(
      routineRepository: repository,
      alarmPlatformStateRepository: stateRepository,
      alarmScheduleMutator: alarmMutator
    )
    await DefaultAppBootstrapPreflight.cancelDisabledAlarmRecordsIfNeeded(
      routineRepository: repository,
      alarmPlatformStateRepository: stateRepository,
      alarmScheduleMutator: alarmMutator
    )

    XCTAssertEqual(alarmMutator.appliedMutations.count, 2)
    for mutation in alarmMutator.appliedMutations {
      guard case .synchronize(let routines) = mutation else {
        return XCTFail("Preflight must only retry synchronization cancellation.")
      }
      XCTAssertEqual(routines, [disabled])
    }
  }

  private func makeRoutine(
    id: UUID,
    isActive: Bool = true,
    createdAt: Date = Date(timeIntervalSince1970: 10),
    updatedAt: Date = Date(timeIntervalSince1970: 10),
    weekdays: [Weekday] = [.monday]
  ) -> Routine {
    Routine(
      id: id,
      name: "루틴",
      steps: [],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 0,
        weekdays: weekdays,
        isEnabled: true
      ),
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  private func uuid(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }

  private func makeAlarmRecord(
    for routine: Routine,
    state: AlarmDeliveryState = .scheduled
  ) -> AlarmDeliveryRecord {
    let schedule = routine.alarmSchedule!
    return AlarmDeliveryRecord(
      request: AlarmScheduleRequest(
        routineID: routine.id,
        scheduleID: schedule.id,
        routineName: routine.name,
        hour: schedule.hour,
        minute: schedule.minute,
        weekdays: schedule.weekdays,
        soundName: schedule.soundName
      ),
      backend: .alarmKit,
      state: state,
      platformIdentifiers: [schedule.id.uuidString.lowercased()],
      lastErrorMessage: state == .repairRequired ? "cancel failed" : nil,
      updatedAt: Date()
    )
  }
}

@MainActor
private final class RoutineActivationRepairRepository: RoutineRepository {
  var routines: [Routine]
  private(set) var saveBatches: [[Routine]] = []

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
    saveBatches.append(routines)
    self.routines = routines
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {}

  func deleteRoutine(id: UUID) throws {}
}

@MainActor
private final class RoutineActivationAlarmStateRepository:
  AlarmPlatformStateRepository {
  var records: [AlarmDeliveryRecord]

  init(records: [AlarmDeliveryRecord]) {
    self.records = records
  }

  func fetchRecords() throws -> [AlarmDeliveryRecord] {
    records
  }

  func record(scheduleID: UUID) throws -> AlarmDeliveryRecord? {
    records.first { $0.scheduleID == scheduleID }
  }

  func saveRecord(_ record: AlarmDeliveryRecord) throws {}
  func deleteRecord(scheduleID: UUID) throws {}
  func deleteAllRecords() throws {}
  func fetchSnoozedAlarms() throws -> [SnoozedAlarmRecord] { [] }
  func saveSnoozedAlarm(_ record: SnoozedAlarmRecord) throws {}
  func replaceSnoozedAlarm(
    scheduleID: UUID,
    with record: SnoozedAlarmRecord
  ) throws {}
  func deleteSnoozedAlarm(id: UUID) throws {}
  func deleteAllSnoozedAlarms() throws {}
}

@MainActor
private final class RoutineActivationAlarmMutator: AlarmScheduleMutating {
  private(set) var appliedMutations: [AlarmScheduleMutation] = []
  private(set) var reconcileCallCount = 0

  func apply(_ mutation: AlarmScheduleMutation) async throws -> AlarmMutationResult {
    appliedMutations.append(mutation)
    return .empty
  }

  func reconcile() async {
    reconcileCallCount += 1
  }

  func cancelAllForReset() async throws {}
}
