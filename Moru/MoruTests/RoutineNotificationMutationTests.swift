//
//  RoutineNotificationMutationTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class RoutineNotificationMutationTests: XCTestCase {
  @MainActor
  func testSaveCommitsPlatformBeforeSavingRoutine() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000001")
    let scheduleID = fixtureUUID("00000000-0000-0000-0000-000000000101")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(
      routines: [makeRoutine(id: routineID, scheduleID: scheduleID)],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let useCase = makeUseCase(repository: repository, mutator: mutator)

    try await useCase.saveRoutine(
      from: makeMutation(routineID: routineID, hour: 8, minute: 30)
    )

    let committedRoutine = try XCTUnwrap(mutator.commitRequests.first?.first)
    let committedSchedule = try XCTUnwrap(committedRoutine.alarmSchedule)
    XCTAssertEqual(committedRoutine.id, routineID)
    XCTAssertEqual(committedSchedule.id, scheduleID)
    XCTAssertEqual(committedSchedule.hour, 8)
    XCTAssertEqual(committedSchedule.minute, 30)
    XCTAssertEqual(eventLog.events, [.platformCommit, .localSaveRoutine(routineID)])
  }

  @MainActor
  func testDisabledActivationCommitsCancellationBeforeSavingRoutine() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000002")
    let scheduleID = fixtureUUID("00000000-0000-0000-0000-000000000102")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(
      routines: [makeRoutine(id: routineID, scheduleID: scheduleID)],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let useCase = makeUseCase(repository: repository, mutator: mutator)

    try await useCase.updateActivation(routineID: routineID, isActive: false)

    let committedRoutine = try XCTUnwrap(mutator.commitRequests.first?.first)
    XCTAssertFalse(committedRoutine.isActive)
    XCTAssertFalse(try XCTUnwrap(committedRoutine.alarmSchedule).isEnabled)
    XCTAssertEqual(eventLog.events, [.platformCommit, .localSaveRoutine(routineID)])
  }

  @MainActor
  func testConflictResolutionCommitsBulkChangeBeforeLocalSave() async throws {
    let targetID = fixtureUUID("00000000-0000-0000-0000-000000000003")
    let targetScheduleID = fixtureUUID("00000000-0000-0000-0000-000000000103")
    let conflictingID = fixtureUUID("00000000-0000-0000-0000-000000000004")
    let conflictingScheduleID = fixtureUUID("00000000-0000-0000-0000-000000000104")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(
      routines: [
        makeRoutine(
          id: targetID,
          scheduleID: targetScheduleID,
          weekdays: [.wednesday],
          isActive: false
        ),
        makeRoutine(
          id: conflictingID,
          scheduleID: conflictingScheduleID,
          weekdays: [.monday]
        ),
      ],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let useCase = makeUseCase(repository: repository, mutator: mutator)

    try await useCase.saveRoutine(
      from: makeMutation(
        routineID: targetID,
        selectedWeekdays: [.monday, .wednesday],
        isActive: true
      ),
      resolvingWeekdayConflict: true
    )

    let committedRoutines = try XCTUnwrap(mutator.commitRequests.first)
    let committedTarget = try XCTUnwrap(committedRoutines.first { $0.id == targetID })
    let committedConflict = try XCTUnwrap(committedRoutines.first { $0.id == conflictingID })
    XCTAssertEqual(committedTarget.alarmSchedule?.id, targetScheduleID)
    XCTAssertEqual(committedTarget.alarmSchedule?.weekdays, [.monday, .wednesday])
    XCTAssertEqual(committedConflict.alarmSchedule?.id, conflictingScheduleID)
    XCTAssertFalse(committedConflict.isActive)
    XCTAssertFalse(try XCTUnwrap(committedConflict.alarmSchedule).isEnabled)
    XCTAssertEqual(
      eventLog.events,
      [.platformCommit, .localSaveRoutines([targetID, conflictingID])]
    )
  }

  @MainActor
  func testDeleteMutatesExactRoutineAndScheduleBeforeLocalDelete() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000005")
    let scheduleID = fixtureUUID("00000000-0000-0000-0000-000000000105")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(
      routines: [makeRoutine(id: routineID, scheduleID: scheduleID)],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let useCase = makeUseCase(repository: repository, mutator: mutator)

    try await useCase.deleteRoutine(id: routineID)

    XCTAssertEqual(mutator.deleteRequests, [
      RoutineNotificationDeleteRequest(routineID: routineID, scheduleID: scheduleID),
    ])
    XCTAssertNil(try repository.routine(id: routineID))
    XCTAssertEqual(
      eventLog.events,
      [.platformDelete(routineID, scheduleID), .localDeleteRoutine(routineID)]
    )
  }
  @MainActor
  func testSwiftDataDeleteRollbackPreventsDelayedDeletionAfterSaveFailure() throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "RoutineDeleteRollback-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    let storeURL = directoryURL.appendingPathComponent("Moru.store")
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000015")
    let routine = makeRoutine(
      id: routineID,
      scheduleID: fixtureUUID("00000000-0000-0000-0000-000000000115")
    )

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let repository = SwiftDataRoutineRepository(modelContext: container.mainContext)
      try repository.saveRoutine(routine)
    }

    do {
      let schema = Schema(versionedSchema: MoruSchemaV2.self)
      let configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        allowsSave: false,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(
        for: schema,
        migrationPlan: MoruMigrationPlan.self,
        configurations: [configuration]
      )
      let repository = SwiftDataRoutineRepository(modelContext: container.mainContext)

      XCTAssertThrowsError(try repository.deleteRoutine(id: routineID))
    }

    let reopenedContainer = try ModelContainer.moruContainer(storeURL: storeURL)
    let reopenedRepository = SwiftDataRoutineRepository(
      modelContext: reopenedContainer.mainContext
    )
    var reopenedRoutine = try XCTUnwrap(reopenedRepository.routine(id: routineID))
    reopenedRoutine.summary = "후속 저장"
    try reopenedRepository.saveRoutine(reopenedRoutine)
    XCTAssertEqual(
      try reopenedRepository.routine(id: routineID)?.summary,
      "후속 저장"
    )
  }

  @MainActor
  func testFrozenMutationDoesNotCommitLocalRoutine() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000011")
    let scheduleID = fixtureUUID("00000000-0000-0000-0000-000000000111")
    let eventLog = RoutineNotificationMutationEventLog()
    let originalRoutine = makeRoutine(id: routineID, scheduleID: scheduleID, name: "원래 이름")
    let repository = RoutineNotificationRoutineRepository(
      routines: [originalRoutine],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let useCase = makeUseCase(repository: repository, mutator: mutator)
    let token = try await mutator.freezeAndDrain()
    defer {
      mutator.thaw(token)
    }

    do {
      try await useCase.saveRoutine(
        from: makeMutation(routineID: routineID)
      )
      XCTFail("Expected frozen notification mutation.")
    } catch {
      XCTAssertEqual(error as? NotificationAlarmMutationError, .mutationFrozen)
    }

    XCTAssertEqual(try repository.routine(id: routineID), originalRoutine)
    XCTAssertTrue(mutator.commitRequests.isEmpty)
    XCTAssertTrue(eventLog.events.isEmpty)
  }

  @MainActor
  func testDeniedSaveDoesNotCommitLocalRoutineAndShowsExistingError() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000006")
    let scheduleID = fixtureUUID("00000000-0000-0000-0000-000000000106")
    let eventLog = RoutineNotificationMutationEventLog()
    let originalRoutine = makeRoutine(id: routineID, scheduleID: scheduleID, name: "원래 이름")
    let repository = RoutineNotificationRoutineRepository(
      routines: [originalRoutine],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    mutator.commitError = NotificationAlarmMutationError.permissionDenied
    let viewModel = RoutineSettingViewModel(
      routineRepository: repository,
      alarmScheduleMutator: mutator
    )

    let didSave = await viewModel.saveDraft(
      makeDraft(routineID: routineID, title: "바뀐 이름")
    )

    XCTAssertFalse(didSave)
    XCTAssertEqual(try repository.routine(id: routineID), originalRoutine)
    XCTAssertEqual(viewModel.state.errorMessage, "루틴을 저장하지 못했어요.")
    XCTAssertEqual(eventLog.events, [.platformCommit])
  }

  @MainActor
  func testPlatformFailureRollsBackActivationAndShowsExistingError() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000007")
    let scheduleID = fixtureUUID("00000000-0000-0000-0000-000000000107")
    let eventLog = RoutineNotificationMutationEventLog()
    let originalRoutine = makeRoutine(id: routineID, scheduleID: scheduleID)
    let repository = RoutineNotificationRoutineRepository(
      routines: [originalRoutine],
      eventLog: eventLog
    )
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    mutator.commitError = NotificationAlarmMutationError.platformFailure
    let viewModel = RoutineSettingViewModel(
      routineRepository: repository,
      alarmScheduleMutator: mutator
    )

    let didChangeActivation = await viewModel.routineActivationDidChange(
      id: routineID,
      isActive: false
    )

    XCTAssertFalse(didChangeActivation)
    XCTAssertEqual(try repository.routine(id: routineID), originalRoutine)
    XCTAssertEqual(viewModel.state.errorMessage, "루틴 상태를 변경하지 못했어요.")
    XCTAssertEqual(eventLog.events, [.platformCommit])
  }
  @MainActor
  func testMakeDraftFailureShowsLoadingErrorWithoutMutation() {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000009")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(eventLog: eventLog)
    repository.routineError = NotificationAlarmMutationError.platformFailure
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let viewModel = RoutineSettingViewModel(
      routineRepository: repository,
      alarmScheduleMutator: mutator
    )

    let draft = viewModel.makeDraft(for: routineID)

    XCTAssertNil(draft)
    XCTAssertEqual(viewModel.state.errorMessage, "루틴 정보를 불러오지 못했어요.")
    XCTAssertTrue(mutator.commitRequests.isEmpty)
    XCTAssertTrue(mutator.deleteRequests.isEmpty)
    XCTAssertTrue(eventLog.events.isEmpty)
  }

  @MainActor
  func testWeekdayConflictFailureShowsLoadingErrorWithoutMutation() {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000010")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(eventLog: eventLog)
    repository.fetchRoutinesError = NotificationAlarmMutationError.platformFailure
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    let viewModel = RoutineSettingViewModel(
      routineRepository: repository,
      alarmScheduleMutator: mutator
    )

    let conflict = viewModel.weekdayConflict(for: makeDraft(routineID: routineID))

    XCTAssertNil(conflict)
    XCTAssertEqual(viewModel.state.errorMessage, "루틴 정보를 불러오지 못했어요.")
    XCTAssertTrue(mutator.commitRequests.isEmpty)
    XCTAssertTrue(mutator.deleteRequests.isEmpty)
    XCTAssertTrue(eventLog.events.isEmpty)
  }
  @MainActor
  func testDuplicateSaveActionIsSuppressedWhileFirstMutationIsInProgress() async throws {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000008")
    let eventLog = RoutineNotificationMutationEventLog()
    let repository = RoutineNotificationRoutineRepository(eventLog: eventLog)
    let mutator = RoutineNotificationMutatorSpy(eventLog: eventLog)
    mutator.suspendsCommit = true
    let viewModel = RoutineSettingViewModel(
      routineRepository: repository,
      alarmScheduleMutator: mutator
    )
    let draft = makeDraft(routineID: routineID)

    let initialSave = Task { @MainActor in
      await viewModel.saveDraft(draft)
    }
    await mutator.waitForCommitToStart()

    XCTAssertTrue(viewModel.isMutationInProgress)
    let duplicateSave = await viewModel.saveDraft(draft)
    XCTAssertFalse(duplicateSave)
    XCTAssertEqual(mutator.commitRequests.count, 1)

    mutator.completeCommit()
    let didInitialSave = await initialSave.value
    XCTAssertTrue(didInitialSave)
    XCTAssertFalse(viewModel.isMutationInProgress)
    XCTAssertEqual(mutator.commitRequests.count, 1)
    XCTAssertEqual(try repository.routine(id: routineID)?.id, routineID)
  }

  @MainActor
  private func makeUseCase(
    repository: any RoutineRepository,
    mutator: any AlarmScheduleMutating
  ) -> RoutineSettingUseCase {
    RoutineSettingUseCase(
      routineRepository: repository,
      alarmScheduleMutator: mutator
    )
  }

  private func makeMutation(
    routineID: UUID,
    hour: Int = 7,
    minute: Int = 0,
    selectedWeekdays: Set<Weekday> = [.monday],
    isActive: Bool = true
  ) -> RoutineSettingMutation {
    RoutineSettingMutation(
      routineID: routineID,
      name: "아침 루틴",
      summary: "하루 준비",
      hour: hour,
      minute: minute,
      selectedWeekdays: selectedWeekdays,
      steps: [
        RoutineStepMutation(
          id: fixtureUUID("00000000-0000-0000-0000-000000000201"),
          type: .confirm,
          title: "물 마시기",
          estimatedMinutes: 3
        ),
      ],
      isActive: isActive
    )
  }

  @MainActor
  private func makeDraft(
    routineID: UUID,
    title: String = "아침 루틴"
  ) -> RoutineDraftState {
    RoutineDraftState(
      routineID: routineID,
      title: title,
      summary: "하루 준비",
      selectedWeekdays: [.monday],
      steps: [
        RoutineStepDraftState(
          id: fixtureUUID("00000000-0000-0000-0000-000000000202"),
          type: .confirm,
          title: "물 마시기",
          estimatedMinutes: 3
        ),
      ]
    )
  }

  private func makeRoutine(
    id: UUID,
    scheduleID: UUID,
    name: String = "아침 루틴",
    weekdays: [Weekday] = [.monday],
    isActive: Bool = true
  ) -> Routine {
    Routine(
      id: id,
      name: name,
      steps: [
        RoutineStep(
          id: fixtureUUID("00000000-0000-0000-0000-000000000203"),
          type: .confirm,
          title: "물 마시기",
          order: 0,
          estimatedSeconds: 180
        ),
      ],
      alarmSchedule: AlarmSchedule(
        id: scheduleID,
        hour: 7,
        minute: 0,
        weekdays: weekdays,
        isEnabled: isActive
      ),
      isActive: isActive,
      createdAt: fixtureDate,
      updatedAt: fixtureDate
    )
  }

  private func fixtureUUID(_ value: String) -> UUID {
    guard let uuid = UUID(uuidString: value) else {
      fatalError("Invalid fixture UUID: \(value)")
    }

    return uuid
  }

  private var fixtureDate: Date {
    Date(timeIntervalSince1970: 1_784_678_400)
  }
}

@MainActor
private final class RoutineNotificationRoutineRepository: RoutineRepository {
  private var routines: [Routine]
  private let eventLog: RoutineNotificationMutationEventLog
  var fetchRoutinesError: (any Error)?
  var routineError: (any Error)?

  init(
    routines: [Routine] = [],
    eventLog: RoutineNotificationMutationEventLog
  ) {
    self.routines = routines
    self.eventLog = eventLog
  }

  func fetchRoutines() throws -> [Routine] {
    if let fetchRoutinesError {
      throw fetchRoutinesError
    }

    return routines
  }

  func fetchActiveRoutines() throws -> [Routine] {
    routines.filter(\.isActive)
  }

  func routine(id: UUID) throws -> Routine? {
    if let routineError {
      throw routineError
    }

    return routines.first { $0.id == id }
  }

  func saveRoutine(_ routine: Routine) throws {
    eventLog.events.append(.localSaveRoutine(routine.id))
    upsert(routine)
  }

  func saveRoutines(_ routines: [Routine]) throws {
    eventLog.events.append(.localSaveRoutines(routines.map(\.id)))
    for routine in routines {
      upsert(routine)
    }
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routine(id: id) else {
      return
    }

    routine.isActive = isActive
    try saveRoutine(routine)
  }

  func deleteRoutine(id: UUID) throws {
    eventLog.events.append(.localDeleteRoutine(id))
    routines.removeAll { $0.id == id }
  }

  private func upsert(_ routine: Routine) {
    if let index = routines.firstIndex(where: { $0.id == routine.id }) {
      routines[index] = routine
    } else {
      routines.append(routine)
    }
  }
}

@MainActor
private final class RoutineNotificationMutatorSpy: AlarmScheduleMutating {
  private let eventLog: RoutineNotificationMutationEventLog
  private var commitContinuation: CheckedContinuation<Void, Never>?
  private var commitStartContinuation: CheckedContinuation<Void, Never>?

  private(set) var commitRequests: [[Routine]] = []
  private(set) var deleteRequests: [RoutineNotificationDeleteRequest] = []
  var commitError: (any Error)?
  var deleteError: (any Error)?
  var suspendsCommit = false
  private var freezeToken: AlarmMutationFreezeToken?

  init(eventLog: RoutineNotificationMutationEventLog) {
    self.eventLog = eventLog
  }

  func commit(
    routines: [Routine],
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try ensureMutationAllowed()
    commitRequests.append(routines)
    eventLog.events.append(.platformCommit)
    commitStartContinuation?.resume()
    commitStartContinuation = nil

    if suspendsCommit {
      await withCheckedContinuation { continuation in
        commitContinuation = continuation
      }
    }

    if let commitError {
      throw commitError
    }

    try localCommit()
  }

  private func ensureMutationAllowed() throws {
    guard freezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
  }

  func delete(
    routineID: UUID,
    scheduleID: UUID?,
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try ensureMutationAllowed()
    deleteRequests.append(
      RoutineNotificationDeleteRequest(routineID: routineID, scheduleID: scheduleID)
    )
    eventLog.events.append(.platformDelete(routineID, scheduleID))

    if let deleteError {
      throw deleteError
    }

    try localCommit()
  }

  func reconcile(routines: [Routine]) async throws {
    try ensureMutationAllowed()
  }

  func freezeAndDrain() async throws -> AlarmMutationFreezeToken {
    guard freezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }

    let token = AlarmMutationFreezeToken()
    freezeToken = token
    return token
  }

  func cancelAll(
    scheduleIDs: [UUID],
    using token: AlarmMutationFreezeToken
  ) async throws {
    guard freezeToken == token else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
  }

  func thaw(_ token: AlarmMutationFreezeToken) {
    guard freezeToken == token else {
      return
    }

    freezeToken = nil
  }

  func permissionState() async -> AlarmNotificationPermissionState {
    .authorized
  }

  func waitForCommitToStart() async {
    guard commitRequests.isEmpty else {
      return
    }

    await withCheckedContinuation { continuation in
      commitStartContinuation = continuation
    }
  }

  func completeCommit() {
    guard let commitContinuation else {
      fatalError("Expected a suspended notification mutation.")
    }

    self.commitContinuation = nil
    commitContinuation.resume()
  }
}

@MainActor
private final class RoutineNotificationMutationEventLog {
  var events: [RoutineNotificationMutationEvent] = []
}

private struct RoutineNotificationDeleteRequest: Equatable {
  let routineID: UUID
  let scheduleID: UUID?
}

private enum RoutineNotificationMutationEvent: Equatable {
  case platformCommit
  case platformDelete(UUID, UUID?)
  case localSaveRoutine(UUID)
  case localSaveRoutines([UUID])
  case localDeleteRoutine(UUID)
}

