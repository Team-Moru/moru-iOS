//
//  HomeRoutineIntegrationTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

final class HomeRoutineIntegrationTests: XCTestCase {
  @MainActor
  func testTodayRoutineRequiresCurrentWeekday() {
    let now = fixtureDate("2026-07-13T08:00:00Z")
    let mondayRoutine = makeRoutine(name: "월요일", weekdays: [.monday])
    let tuesdayRoutine = makeRoutine(name: "화요일", weekdays: [.tuesday])
    let viewModel = makeViewModel(routines: [tuesdayRoutine, mondayRoutine], now: now)

    viewModel.load()

    XCTAssertEqual(viewModel.state.loadState, .content)
    XCTAssertEqual(viewModel.state.todayRoutine?.id, mondayRoutine.id)
  }

  @MainActor
  func testDisabledAlarmAndEmptyStepsAreNotScheduled() {
    let now = fixtureDate("2026-07-13T08:00:00Z")
    let disabledRoutine = makeRoutine(
      name: "꺼진 알람",
      weekdays: [.monday],
      alarmEnabled: false
    )
    let emptyRoutine = makeRoutine(
      name: "빈 루틴",
      weekdays: [.monday],
      steps: []
    )
    let viewModel = makeViewModel(routines: [disabledRoutine, emptyRoutine], now: now)

    viewModel.load()

    XCTAssertNil(viewModel.state.todayRoutine)
    XCTAssertEqual(viewModel.state.manualRoutines.map(\.id), [disabledRoutine.id])
  }

  @MainActor
  func testScheduledRoutineOrderingUsesAlarmTimeCreationDateAndUUID() throws {
    let now = fixtureDate("2026-07-13T08:00:00Z")
    let earlierAlarm = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000003"),
      name: "빠른 알람",
      hour: 6,
      createdAt: fixtureDate("2026-07-01T00:00:00Z")
    )
    let laterAlarm = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000001"),
      name: "늦은 알람",
      hour: 7,
      createdAt: fixtureDate("2026-06-01T00:00:00Z")
    )
    let alarmResult = try makeUseCase(
      routines: [laterAlarm, earlierAlarm],
      now: now
    ).execute()

    XCTAssertEqual(alarmResult.todayRoutine?.id, earlierAlarm.id)

    let earlierCreation = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000004"),
      name: "먼저 생성",
      createdAt: fixtureDate("2026-06-01T00:00:00Z")
    )
    let laterCreation = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000002"),
      name: "나중 생성",
      createdAt: fixtureDate("2026-06-02T00:00:00Z")
    )
    let creationResult = try makeUseCase(
      routines: [laterCreation, earlierCreation],
      now: now
    ).execute()

    XCTAssertEqual(creationResult.todayRoutine?.id, earlierCreation.id)

    let lowerUUID = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000005"),
      name: "낮은 UUID",
      createdAt: fixtureDate("2026-06-01T00:00:00Z")
    )
    let higherUUID = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000006"),
      name: "높은 UUID",
      createdAt: fixtureDate("2026-06-01T00:00:00Z")
    )
    let uuidResult = try makeUseCase(
      routines: [higherUUID, lowerUUID],
      now: now
    ).execute()

    XCTAssertEqual(uuidResult.todayRoutine?.id, lowerUUID.id)
  }

  @MainActor
  func testActiveRoutineRemainsAvailableForManualLaunchWhenNotScheduledToday() {
    let now = fixtureDate("2026-07-14T08:00:00Z")
    let manualRoutine = makeRoutine(name: "월요일 루틴", weekdays: [.monday])
    let viewModel = makeViewModel(routines: [manualRoutine], now: now)

    viewModel.load()

    XCTAssertEqual(viewModel.state.loadState, .content)
    XCTAssertNil(viewModel.state.todayRoutine)
    XCTAssertEqual(viewModel.state.manualRoutines.map(\.id), [manualRoutine.id])
  }

  @MainActor
  func testNoManualRoutinesProducesEmptyStateWithoutPlaceholderName() {
    let viewModel = makeViewModel(
      routines: [],
      profile: nil,
      now: fixtureDate("2026-07-13T08:00:00Z")
    )

    viewModel.load()

    XCTAssertEqual(viewModel.state.loadState, .empty)
    XCTAssertEqual(viewModel.state.userName, "")
    XCTAssertTrue(viewModel.state.manualRoutines.isEmpty)
  }

  @MainActor
  func testLoadingFailureProducesFailedState() {
    let now = fixtureDate("2026-07-13T08:00:00Z")
    let useCase = LoadHomeRoutinesUseCase(
      routineRepository: FailingRoutineRepository(),
      routineRunRepository: TestRoutineRunRepository(),
      localProfileRepository: TestProfileRepository(profile: LocalProfile(displayName: "모루")),
      now: { now }
    )
    let viewModel = HomeViewModel(loadHomeRoutinesUseCase: useCase)

    viewModel.load()

    XCTAssertEqual(viewModel.state.loadState, .failed)
    XCTAssertEqual(viewModel.state.errorMessage, "홈 정보를 불러오지 못했어요.")
  }

  @MainActor
  func testCalendarTimeZoneControlsWeekdayAndTodayRunBoundary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let now = fixtureDate("2026-07-14T07:30:00Z")
    let mondayRoutine = makeRoutine(name: "월요일", weekdays: [.monday])
    let tuesdayRoutine = makeRoutine(name: "화요일", weekdays: [.tuesday])
    let completedYesterday = RoutineRun(
      routine: tuesdayRoutine,
      startedAt: fixtureDate("2026-07-14T06:59:00Z"),
      completedAt: fixtureDate("2026-07-14T06:59:00Z"),
      results: completedResults(for: tuesdayRoutine)
    )
    let incompleteToday = RoutineRun(
      routine: tuesdayRoutine,
      startedAt: fixtureDate("2026-07-14T07:00:00Z")
    )
    let viewModel = makeViewModel(
      routines: [mondayRoutine, tuesdayRoutine],
      runs: [completedYesterday, incompleteToday],
      calendar: calendar,
      now: now
    )

    viewModel.load()

    XCTAssertEqual(viewModel.state.todayRoutine?.id, tuesdayRoutine.id)
    XCTAssertEqual(viewModel.state.todayProgress.completedText, "0/1 완료")
  }

  @MainActor
  func testProgressAndStreakUseRoutineRunSnapshots() {
    let now = fixtureDate("2026-07-14T12:00:00Z")
    let currentRoutine = makeRoutine(
      name: "수정된 루틴",
      weekdays: [.tuesday],
      steps: [
        RoutineStep(
          type: .confirm,
          title: "현재 스텝",
          order: 0,
          estimatedSeconds: 60
        ),
      ]
    )
    let recordedFirstStep = RoutineStep(
      type: .confirm,
      title: "기록된 첫 스텝",
      order: 0,
      estimatedSeconds: 60
    )
    let recordedSecondStep = RoutineStep(
      type: .timer,
      title: "기록된 두 번째 스텝",
      order: 1,
      estimatedSeconds: 120
    )
    let todayRun = RoutineRun(
      routineID: currentRoutine.id,
      routineName: "이전 루틴",
      startedAt: now,
      completedAt: now,
      results: [
        RoutineStepResult(
          stepID: recordedFirstStep.id,
          stepTitle: recordedFirstStep.title,
          stepType: recordedFirstStep.type,
          completedAt: now
        ),
        RoutineStepResult(
          stepID: UUID(),
          stepTitle: "관련 없는 스텝",
          stepType: .confirm,
          completedAt: now
        ),
      ],
      plannedSteps: [
        RoutineStepSnapshot(step: recordedFirstStep),
        RoutineStepSnapshot(step: recordedSecondStep),
      ]
    )
    let mondayRun = completedRun(on: fixtureDate("2026-07-13T12:00:00Z"))
    let sundayRun = completedRun(on: fixtureDate("2026-07-12T12:00:00Z"))
    let endedEarlyRun = RoutineRun(
      routineID: UUID(),
      routineName: "중단된 루틴",
      startedAt: fixtureDate("2026-07-11T12:00:00Z"),
      completedAt: fixtureDate("2026-07-11T12:00:00Z"),
      endedEarly: true
    )
    let viewModel = makeViewModel(
      routines: [currentRoutine],
      runs: [todayRun, mondayRun, sundayRun, endedEarlyRun],
      now: now
    )

    viewModel.load()

    XCTAssertEqual(viewModel.state.todayProgress.completedText, "1/2 완료")
    XCTAssertEqual(viewModel.state.todayProgress.progress, 0.5)
    XCTAssertEqual(
      viewModel.state.todayRoutine?.steps.map(\.title),
      ["기록된 첫 스텝", "기록된 두 번째 스텝"]
    )
    XCTAssertEqual(viewModel.state.streak.currentDays, 3)
    XCTAssertEqual(viewModel.state.streak.bestDays, 3)
    XCTAssertEqual(
      viewModel.state.streak.completedWeekdays,
      Set([.sunday, .monday, .tuesday])
    )
  }

  @MainActor
  func testPartialRunDoesNotIncreaseStreak() throws {
    let now = fixtureDate("2026-07-14T12:00:00Z")
    let snapshot = RoutineStepSnapshot(
      stepID: UUID(),
      stepTitle: "미완료 스텝",
      stepType: .confirm,
      stepOrder: 0
    )
    let partialRun = RoutineRun(
      routineID: UUID(),
      routineName: "부분 완료",
      startedAt: now,
      completedAt: now,
      plannedSteps: [snapshot]
    )
    let useCase = makeUseCase(
      routines: [],
      runs: [partialRun],
      now: now
    )

    let result = try useCase.execute()

    XCTAssertEqual(result.streak.currentDays, 0)
    XCTAssertEqual(result.streak.bestDays, 0)
    XCTAssertTrue(result.streak.completedWeekdays.isEmpty)
  }

  @MainActor
  private func makeViewModel(
    routines: [Routine],
    runs: [RoutineRun] = [],
    profile: LocalProfile? = LocalProfile(displayName: "모루"),
    calendar: Calendar = Calendar(identifier: .gregorian),
    now: Date
  ) -> HomeViewModel {
    HomeViewModel(
      loadHomeRoutinesUseCase: makeUseCase(
        routines: routines,
        runs: runs,
        profile: profile,
        calendar: calendar,
        now: now
      )
    )
  }

  @MainActor
  private func makeUseCase(
    routines: [Routine],
    runs: [RoutineRun] = [],
    profile: LocalProfile? = LocalProfile(displayName: "모루"),
    calendar: Calendar = Calendar(identifier: .gregorian),
    now: Date
  ) -> LoadHomeRoutinesUseCase {
    LoadHomeRoutinesUseCase(
      routineRepository: TestRoutineRepository(routines: routines),
      routineRunRepository: TestRoutineRunRepository(runs: runs),
      localProfileRepository: TestProfileRepository(profile: profile),
      calendar: calendar,
      now: { now }
    )
  }

  @MainActor
  private func makeRoutine(
    id: UUID = UUID(),
    name: String,
    weekdays: [Weekday] = [.monday],
    hour: Int = 7,
    minute: Int = 0,
    alarmEnabled: Bool = true,
    steps: [RoutineStep] = [
      RoutineStep(type: .confirm, title: "스텝", order: 0, estimatedSeconds: 60),
    ],
    createdAt: Date = Date(timeIntervalSince1970: 0)
  ) -> Routine {
    Routine(
      id: id,
      name: name,
      steps: steps,
      alarmSchedule: AlarmSchedule(
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        isEnabled: alarmEnabled
      ),
      createdAt: createdAt,
      updatedAt: createdAt
    )
  }

  @MainActor
  private func completedResults(for routine: Routine) -> [RoutineStepResult] {
    routine.steps.map { step in
      RoutineStepResult(
        stepID: step.id,
        stepTitle: step.title,
        stepType: step.type,
        completedAt: fixtureDate("2026-07-14T06:59:00Z")
      )
    }
  }

  @MainActor
  private func completedRun(on date: Date) -> RoutineRun {
    let stepID = UUID()
    let snapshot = RoutineStepSnapshot(
      stepID: stepID,
      stepTitle: "완료 스텝",
      stepType: .confirm,
      stepOrder: 0
    )
    let result = RoutineStepResult(
      stepID: stepID,
      stepTitle: snapshot.stepTitle,
      stepType: snapshot.stepType,
      completedAt: date
    )

    return RoutineRun(
      routineID: UUID(),
      routineName: "완료 루틴",
      startedAt: date,
      completedAt: date,
      results: [result],
      plannedSteps: [snapshot]
    )
  }

  private func fixtureDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  private func fixtureUUID(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }
}

@MainActor
private final class TestRoutineRepository: RoutineRepository {
  private var routines: [Routine]

  init(routines: [Routine] = []) {
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
      if let index = self.routines.firstIndex(where: { $0.id == routine.id }) {
        self.routines[index] = routine
      } else {
        self.routines.append(routine)
      }
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
    routines.removeAll { $0.id == id }
  }
}

@MainActor
private final class FailingRoutineRepository: RoutineRepository {
  func fetchRoutines() throws -> [Routine] {
    throw TestRepositoryError.unavailable
  }

  func fetchActiveRoutines() throws -> [Routine] {
    throw TestRepositoryError.unavailable
  }

  func routine(id: UUID) throws -> Routine? {
    throw TestRepositoryError.unavailable
  }

  func saveRoutine(_ routine: Routine) throws {
    throw TestRepositoryError.unavailable
  }

  func saveRoutines(_ routines: [Routine]) throws {
    throw TestRepositoryError.unavailable
  }

  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    throw TestRepositoryError.unavailable
  }

  func deleteRoutine(id: UUID) throws {
    throw TestRepositoryError.unavailable
  }
}

@MainActor
private final class TestRoutineRunRepository: RoutineRunRepository {
  private var runs: [RoutineRun]

  init(runs: [RoutineRun] = []) {
    self.runs = runs
  }

  func fetchRuns() throws -> [RoutineRun] {
    runs
  }

  func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
    Array(runs.prefix(limit))
  }

  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    runs.filter { $0.routineID == routineID }
  }

  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun] {
    runs.filter { $0.startedAt >= startDate && $0.startedAt < endDate }
  }

  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun] {
    try fetchRuns(for: routineID)
      .filter { $0.startedAt >= startDate && $0.startedAt < endDate }
  }

  func latestRun(for routineID: UUID) throws -> RoutineRun? {
    try fetchRuns(for: routineID).max { $0.startedAt < $1.startedAt }
  }

  func run(id: UUID) throws -> RoutineRun? {
    runs.first { $0.id == id }
  }

  func saveRun(_ run: RoutineRun) throws {
    if let index = runs.firstIndex(where: { $0.id == run.id }) {
      runs[index] = run
    } else {
      runs.append(run)
    }
  }

  func deleteAllRuns() throws {
    runs = []
  }
}

@MainActor
private final class TestProfileRepository: LocalProfileRepository {
  private var profile: LocalProfile?

  init(profile: LocalProfile? = nil) {
    self.profile = profile
  }

  func fetchProfile() throws -> LocalProfile? {
    profile
  }

  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile {
      return profile
    }

    let profile = LocalProfile()
    self.profile = profile
    return profile
  }

  func saveProfile(_ profile: LocalProfile) throws {
    self.profile = profile
  }

  func deleteProfile() throws {
    profile = nil
  }
}

private enum TestRepositoryError: Error {
  case unavailable
}
