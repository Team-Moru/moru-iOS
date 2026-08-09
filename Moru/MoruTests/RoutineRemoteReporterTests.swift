//
//  RoutineRemoteReporterTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

@MainActor
final class RoutineRemoteReporterTests: XCTestCase {
  func testCreatesServerGroupPersistsBindingAndReportsMappedSteps() async throws {
    let confirmStep = RoutineStep(
      type: .confirm,
      title: "물 마시기",
      order: 0,
      estimatedSeconds: 30
    )
    let inputStep = RoutineStep(
      type: .input,
      title: "오늘의 다짐",
      order: 1,
      estimatedSeconds: 20
    )
    let routine = Routine(
      name: "아침 루틴",
      summary: "천천히 시작해요",
      steps: [confirmStep, inputStep],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 0,
        weekdays: [.monday],
        includeWeather: true
      ),
      sync: SyncMetadata(remoteRevision: "revision-7")
    )
    let repository = RemoteReporterRoutineRepository(routine: routine)
    let groupService = RemoteReporterRoutineGroupService(
      detail: ServerRoutineGroupDetail(
        routineGroupID: 88,
        title: routine.name,
        description: routine.summary,
        alarmDaysRaw: "MON",
        alarmTimeRaw: "07:00",
        weatherNotificationEnabled: true,
        routines: [
          ServerRoutineItem(
            routineID: 501,
            title: confirmStep.title,
            type: .check,
            durationSeconds: 30,
            steps: nil
          ),
          ServerRoutineItem(
            routineID: 502,
            title: inputStep.title,
            type: .input,
            durationSeconds: 20,
            steps: nil
          ),
        ]
      )
    )
    let executionService = RemoteReporterExecutionService()
    let memberProvider = RemoteReporterMemberProvider(memberID: 42)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let reporter = DefaultRoutineRemoteReporter(
      routineRepository: repository,
      routineGroupService: groupService,
      executionService: executionService,
      signedInMemberProvider: memberProvider,
      calendar: calendar
    )
    let startedAt = try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: 2026,
          month: 8,
          day: 10,
          hour: 7,
          minute: 5
        )
      )
    )
    let submittedAt = startedAt.addingTimeInterval(5 * 60)

    let judgment = try await reporter.judgeCheck(
      RoutineRemoteCheckRequest(
        runID: UUID(),
        routine: routine,
        step: confirmStep,
        submittedAt: submittedAt,
        durationSeconds: 8,
        memberInput: "물을 마셨어요",
        actualWakeTime: nil
      )
    )
    try await reporter.recordExecution(
      RoutineRemoteExecutionRequest(
        runID: UUID(),
        routine: routine,
        step: inputStep,
        submittedAt: submittedAt,
        durationSeconds: 12,
        isCompleted: true,
        memberInput: "차분하게 시작할게요",
        actualWakeTime: startedAt
      )
    )

    var editedRoutine = try XCTUnwrap(repository.routine)
    let replacementInputStep = RoutineStep(
      type: .input,
      title: inputStep.title,
      order: 1,
      estimatedSeconds: 20
    )
    editedRoutine.steps[1] = replacementInputStep
    try repository.saveRoutine(editedRoutine)
    try await reporter.recordExecution(
      RoutineRemoteExecutionRequest(
        runID: UUID(),
        routine: editedRoutine,
        step: replacementInputStep,
        submittedAt: submittedAt,
        durationSeconds: 14,
        isCompleted: true,
        memberInput: "수정 뒤에도 기록해요",
        actualWakeTime: startedAt
      )
    )

    XCTAssertEqual(
      judgment,
      RoutineRemoteCheckResult(aiResponse: "좋아요.", shouldProceed: true)
    )
    let groupSnapshot = await groupService.snapshot()
    XCTAssertEqual(groupSnapshot.createMemberIDs, [42])
    XCTAssertEqual(groupSnapshot.fetchRequests.count, 1)
    XCTAssertEqual(groupSnapshot.fetchRequests.first?.routineGroupID, 88)
    XCTAssertEqual(groupSnapshot.fetchRequests.first?.memberID, 42)
    XCTAssertEqual(groupSnapshot.createSubmissions.first?.title, "아침 루틴")
    XCTAssertNil(groupSnapshot.createSubmissions.first?.alarmDaysRaw)
    XCTAssertNil(groupSnapshot.createSubmissions.first?.alarmTimeRaw)
    XCTAssertEqual(
      groupSnapshot.createSubmissions.first?.weatherNotificationEnabled,
      false
    )
    XCTAssertEqual(
      groupSnapshot.createSubmissions.first?.routines.map(\.type),
      [.check, .input]
    )

    let executionSnapshot = await executionService.snapshot()
    XCTAssertEqual(executionSnapshot.judgmentMemberIDs, [42])
    XCTAssertEqual(executionSnapshot.judgments.first?.routineID, 501)
    XCTAssertEqual(executionSnapshot.judgments.first?.executedDate, "2026-08-10")
    XCTAssertEqual(executionSnapshot.judgments.first?.actualWakeTime, nil)
    XCTAssertEqual(executionSnapshot.executionMemberIDs, [42, 42])
    XCTAssertEqual(executionSnapshot.executions.first?.routineID, 502)
    XCTAssertEqual(executionSnapshot.executions.first?.actualWakeTime, "07:05")
    XCTAssertEqual(
      executionSnapshot.executions.first?.memberInput,
      "차분하게 시작할게요"
    )
    XCTAssertEqual(executionSnapshot.executions.last?.routineID, 502)
    XCTAssertEqual(
      executionSnapshot.executions.last?.memberInput,
      "수정 뒤에도 기록해요"
    )
    XCTAssertEqual(repository.routine?.sync?.remoteID, "42:88")
    XCTAssertNotNil(repository.routine?.sync?.lastSyncedAt)
    XCTAssertEqual(repository.routine?.sync?.remoteRevision, "revision-7")
  }

  func testUsesGregorianExecutionDateWhenDeviceCalendarIsBuddhist() async throws {
    let step = RoutineStep(
      type: .input,
      title: "기록하기",
      order: 0,
      estimatedSeconds: 60
    )
    let routine = Routine(name: "저녁 루틴", steps: [step])
    let repository = RemoteReporterRoutineRepository(routine: routine)
    let groupService = RemoteReporterRoutineGroupService(
      detail: serverDetail(routine: routine, routineIDs: [701])
    )
    let executionService = RemoteReporterExecutionService()
    let memberProvider = RemoteReporterMemberProvider(memberID: 42)
    var buddhistCalendar = Calendar(identifier: .buddhist)
    buddhistCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let reporter = DefaultRoutineRemoteReporter(
      routineRepository: repository,
      routineGroupService: groupService,
      executionService: executionService,
      signedInMemberProvider: memberProvider,
      calendar: buddhistCalendar
    )
    var gregorianCalendar = Calendar(identifier: .gregorian)
    gregorianCalendar.timeZone = buddhistCalendar.timeZone
    let submittedAt = try XCTUnwrap(
      gregorianCalendar.date(
        from: DateComponents(year: 2026, month: 8, day: 10, hour: 20)
      )
    )

    try await reporter.recordExecution(
      RoutineRemoteExecutionRequest(
        runID: UUID(),
        routine: routine,
        step: step,
        submittedAt: submittedAt,
        durationSeconds: 3,
        isCompleted: true,
        memberInput: "완료",
        actualWakeTime: nil
      )
    )

    let executionSnapshot = await executionService.snapshot()
    XCTAssertEqual(executionSnapshot.executions.first?.executedDate, "2026-08-10")
  }

  func testRecreatesBindingWhenSameNamedTimersAreReordered() async throws {
    let shortTimer = RoutineStep(
      type: .timer,
      title: "호흡",
      order: 0,
      estimatedSeconds: 30
    )
    let longTimer = RoutineStep(
      type: .timer,
      title: "호흡",
      order: 1,
      estimatedSeconds: 120
    )
    var reorderedLongTimer = longTimer
    reorderedLongTimer.order = 0
    var reorderedShortTimer = shortTimer
    reorderedShortTimer.order = 1
    let routine = Routine(
      name: "호흡 루틴",
      steps: [reorderedLongTimer, reorderedShortTimer],
      sync: SyncMetadata(remoteID: "42:88", status: .localOnly)
    )
    let repository = RemoteReporterRoutineRepository(routine: routine)
    let staleDetail = ServerRoutineGroupDetail(
      routineGroupID: 88,
      title: routine.name,
      description: nil,
      alarmDaysRaw: nil,
      alarmTimeRaw: nil,
      weatherNotificationEnabled: false,
      routines: [
        serverItem(id: 801, step: shortTimer),
        serverItem(id: 802, step: longTimer),
      ]
    )
    let createdDetail = serverDetail(
      routine: routine,
      routineGroupID: 99,
      routineIDs: [901, 902]
    )
    let groupService = RemoteReporterRoutineGroupService(
      detail: staleDetail,
      createdDetail: createdDetail
    )
    let executionService = RemoteReporterExecutionService()
    let memberProvider = RemoteReporterMemberProvider(memberID: 42)
    let reporter = DefaultRoutineRemoteReporter(
      routineRepository: repository,
      routineGroupService: groupService,
      executionService: executionService,
      signedInMemberProvider: memberProvider
    )
    try await reporter.recordExecution(
      RoutineRemoteExecutionRequest(
        runID: UUID(),
        routine: routine,
        step: reorderedLongTimer,
        submittedAt: Date(),
        durationSeconds: 120,
        isCompleted: true,
        memberInput: nil,
        actualWakeTime: nil
      )
    )

    let groupSnapshot = await groupService.snapshot()
    XCTAssertEqual(groupSnapshot.fetchRequests.count, 1)
    XCTAssertEqual(groupSnapshot.createMemberIDs, [42])
    XCTAssertEqual(repository.routine?.sync?.remoteID, "42:99")
    let executionSnapshot = await executionService.snapshot()
    XCTAssertEqual(executionSnapshot.executions.first?.routineID, 901)
  }

  func testPreservesBindingsForMultipleSignedInAccounts() async throws {
    let step = RoutineStep(
      type: .input,
      title: "한 줄 기록",
      order: 0,
      estimatedSeconds: 60
    )
    let routine = Routine(
      name: "공유 기기 루틴",
      steps: [step],
      sync: SyncMetadata(remoteID: "41:77", status: .localOnly)
    )
    let repository = RemoteReporterRoutineRepository(routine: routine)
    let executionService = RemoteReporterExecutionService()
    let member42Detail = serverDetail(
      routine: routine,
      routineGroupID: 99,
      routineIDs: [9901]
    )
    let member42Service = RemoteReporterRoutineGroupService(
      detail: member42Detail
    )
    let member42Provider = RemoteReporterMemberProvider(memberID: 42)
    let member42Reporter = DefaultRoutineRemoteReporter(
      routineRepository: repository,
      routineGroupService: member42Service,
      executionService: executionService,
      signedInMemberProvider: member42Provider
    )

    try await member42Reporter.recordExecution(
      executionRequest(routine: routine, step: step)
    )

    let reboundRoutine = try XCTUnwrap(repository.routine)
    XCTAssertEqual(reboundRoutine.sync?.remoteID, "41:77;42:99")
    let member41Detail = serverDetail(
      routine: reboundRoutine,
      routineGroupID: 77,
      routineIDs: [7701]
    )
    let member41Service = RemoteReporterRoutineGroupService(
      detail: member41Detail
    )
    let member41Provider = RemoteReporterMemberProvider(memberID: 41)
    let member41Reporter = DefaultRoutineRemoteReporter(
      routineRepository: repository,
      routineGroupService: member41Service,
      executionService: executionService,
      signedInMemberProvider: member41Provider
    )

    try await member41Reporter.recordExecution(
      executionRequest(routine: reboundRoutine, step: step)
    )

    let member41Snapshot = await member41Service.snapshot()
    XCTAssertEqual(member41Snapshot.fetchRequests.first?.routineGroupID, 77)
    XCTAssertTrue(member41Snapshot.createMemberIDs.isEmpty)
    let executionSnapshot = await executionService.snapshot()
    XCTAssertEqual(executionSnapshot.executions.map(\.routineID), [9901, 7701])
  }

  private func serverDetail(
    routine: Routine,
    routineGroupID: Int64 = 88,
    routineIDs: [Int64]
  ) -> ServerRoutineGroupDetail {
    ServerRoutineGroupDetail(
      routineGroupID: routineGroupID,
      title: routine.name,
      description: routine.summary,
      alarmDaysRaw: nil,
      alarmTimeRaw: nil,
      weatherNotificationEnabled: false,
      routines: zip(
        routine.steps.sorted { $0.order < $1.order },
        routineIDs
      ).map { step, routineID in
        serverItem(id: routineID, step: step)
      }
    )
  }

  private func serverItem(
    id: Int64,
    step: RoutineStep
  ) -> ServerRoutineItem {
    let type: ServerRoutineItemType
    switch step.type {
    case .confirm:
      type = .check
    case .timer:
      type = .timer
    case .input:
      type = .input
    }
    return ServerRoutineItem(
      routineID: id,
      title: step.title,
      type: type,
      durationSeconds: max(step.estimatedSeconds ?? 60, 1),
      steps: nil
    )
  }

  private func executionRequest(
    routine: Routine,
    step: RoutineStep
  ) -> RoutineRemoteExecutionRequest {
    RoutineRemoteExecutionRequest(
      runID: UUID(),
      routine: routine,
      step: step,
      submittedAt: Date(),
      durationSeconds: 1,
      isCompleted: true,
      memberInput: nil,
      actualWakeTime: nil
    )
  }
}

@MainActor
private final class RemoteReporterRoutineRepository: RoutineRepository {
  var routine: Routine?

  init(routine: Routine) {
    self.routine = routine
  }

  func fetchRoutines() throws -> [Routine] {
    routine.map { [$0] } ?? []
  }

  func fetchActiveRoutines() throws -> [Routine] {
    try fetchRoutines().filter(\.isActive)
  }

  func routine(id: UUID) throws -> Routine? {
    routine?.id == id ? routine : nil
  }

  func saveRoutine(_ routine: Routine) throws {
    self.routine = routine
  }

  func saveRoutines(_ routines: [Routine]) throws {
    self.routine = routines.last ?? routine
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routine(id: id) else {
      return
    }
    routine.isActive = isActive
    self.routine = routine
  }

  func deleteRoutine(id: UUID) throws {
    if routine?.id == id {
      routine = nil
    }
  }
}

private actor RemoteReporterRoutineGroupService:
  AccountRoutineGroupRemoteServing
{
  struct Snapshot: Sendable {
    let createSubmissions: [ServerRoutineGroupCreateSubmission]
    let createMemberIDs: [Int64]
    let fetchRequests: [(routineGroupID: Int64, memberID: Int64)]
  }

  private let detail: ServerRoutineGroupDetail
  private let createdDetail: ServerRoutineGroupDetail
  private var createSubmissions: [ServerRoutineGroupCreateSubmission] = []
  private var createMemberIDs: [Int64] = []
  private var fetchRequests: [(routineGroupID: Int64, memberID: Int64)] = []

  init(
    detail: ServerRoutineGroupDetail,
    createdDetail: ServerRoutineGroupDetail? = nil
  ) {
    self.detail = detail
    self.createdDetail = createdDetail ?? detail
  }

  func createRoutineGroup(
    _ submission: ServerRoutineGroupCreateSubmission,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    createSubmissions.append(submission)
    createMemberIDs.append(memberID)
    return createdDetail
  }

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary] {
    []
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    fetchRequests.append((routineGroupID, memberID))
    return detail
  }

  func snapshot() -> Snapshot {
    Snapshot(
      createSubmissions: createSubmissions,
      createMemberIDs: createMemberIDs,
      fetchRequests: fetchRequests
    )
  }
}

private actor RemoteReporterExecutionService:
  AccountRoutineExecutionRemoteServing
{
  struct Snapshot: Sendable {
    let executions: [ServerRoutineExecutionSubmission]
    let executionMemberIDs: [Int64]
    let judgments: [ServerAIExecutionSubmission]
    let judgmentMemberIDs: [Int64]
  }

  private var executions: [ServerRoutineExecutionSubmission] = []
  private var executionMemberIDs: [Int64] = []
  private var judgments: [ServerAIExecutionSubmission] = []
  private var judgmentMemberIDs: [Int64] = []

  func saveExecution(
    _ submission: ServerRoutineExecutionSubmission,
    memberID: Int64
  ) async throws -> ServerRoutineExecutionResult {
    executions.append(submission)
    executionMemberIDs.append(memberID)
    return ServerRoutineExecutionResult(
      executionID: 900,
      routineID: submission.routineID,
      executedDate: submission.executedDate,
      durationSeconds: submission.durationSeconds,
      isCompleted: submission.isCompleted
    )
  }

  func judgeCheckStep(
    _ submission: ServerAIExecutionSubmission,
    memberID: Int64
  ) async throws -> ServerAIExecutionJudgment {
    judgments.append(submission)
    judgmentMemberIDs.append(memberID)
    return ServerAIExecutionJudgment(
      aiResponse: "좋아요.",
      shouldProceed: true
    )
  }

  func snapshot() -> Snapshot {
    Snapshot(
      executions: executions,
      executionMemberIDs: executionMemberIDs,
      judgments: judgments,
      judgmentMemberIDs: judgmentMemberIDs
    )
  }
}

@MainActor
private final class RemoteReporterMemberProvider: SignedInMemberProviding {
  let signedInMemberID: Int64?

  init(memberID: Int64?) {
    self.signedInMemberID = memberID
  }
}
