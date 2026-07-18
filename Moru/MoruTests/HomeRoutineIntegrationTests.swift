//
//  HomeRoutineIntegrationTests.swift
//  MoruTests
//

import Foundation
import SwiftUI
import UIKit
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
  func testLoadingFailureProducesTypedLocalFailure() {
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
    XCTAssertEqual(
      viewModel.state.failure,
      .localRoutineDataUnavailable(
        diagnostic: String(reflecting: TestRepositoryError.unavailable)
      )
    )
    XCTAssertEqual(viewModel.state.errorMessage, "홈 정보를 불러오지 못했어요. 다시 시도해 주세요.")
    XCTAssertEqual(viewModel.state.failure?.diagnosticCategory, .localRoutineData)
    XCTAssertEqual(
      viewModel.state.failure?.diagnosticDescription,
      String(reflecting: TestRepositoryError.unavailable)
    )
    XCTAssertNil(viewModel.state.routineContent)
  }

  @MainActor
  func testRetryPreservesLoadedLocalRoutineContentWhenReloadFails() {
    let routine = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000007"),
      name: "보존할 루틴"
    )
    let successfulResult = HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "모루"),
      todayRoutine: routine,
      manualRoutines: [routine],
      todayRun: nil,
      streak: HomeRoutineStreak(
        currentDays: 1,
        bestDays: 1,
        completedWeekdays: [.monday]
      )
    )
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: SequencedHomeRoutinesUseCase(
        results: [.success(successfulResult), .failure(.unavailable)]
      )
    )

    viewModel.load()
    viewModel.retry()

    XCTAssertEqual(viewModel.state.loadState, .failed)
    XCTAssertEqual(viewModel.state.todayRoutine?.id, routine.id)
    XCTAssertEqual(viewModel.state.manualRoutines.map(\.id), [routine.id])
    XCTAssertEqual(
      viewModel.state.failure,
      .localRoutineDataUnavailable(
        diagnostic: String(reflecting: TestRepositoryError.unavailable)
      )
    )
  }

  @MainActor
  func testRoutineLaunchBoundaryForwardsExactRoutineIDForEveryOutcome() {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000008")
    let outcomes: [RoutineLaunchResult] = [.started, .alreadyRunning, .busy]

    for outcome in outcomes {
      var receivedRoutineID: UUID?
      let boundary = HomeRoutineLaunchBoundary(
        onStartRoutine: { request in
          receivedRoutineID = request.routineID
          return outcome
        },
        announceAccessibility: { _ in }
      )

      XCTAssertEqual(boundary.start(routineID: routineID), outcome)
      XCTAssertEqual(receivedRoutineID, routineID)
    }
  }
  @MainActor
  func testRoutineLaunchBoundaryOnlyAnnouncesAndProvidesMessageWhenBusy() {
    let routineID = fixtureUUID("00000000-0000-0000-0000-000000000009")

    for outcome in [RoutineLaunchResult.started, .alreadyRunning, .busy] {
      var announcements: [String] = []
      let boundary = HomeRoutineLaunchBoundary(
        onStartRoutine: { _ in outcome },
        announceAccessibility: { announcements.append($0) }
      )

      XCTAssertEqual(boundary.start(routineID: routineID), outcome)
      XCTAssertEqual(
        HomeRoutineLaunchBoundary.message(for: outcome),
        outcome == .busy ? HomeRoutineLaunchBoundary.busyMessage : nil
      )
      XCTAssertEqual(
        announcements,
        outcome == .busy ? [HomeRoutineLaunchBoundary.busyMessage] : []
      )
    }
  }

  @MainActor
  func testHomeStreakCardWeekdayAccessibilityValueReflectsCompletion() {
    XCTAssertEqual(
      HomeStreakCard.weekdayAccessibilityValue(isCompleted: true),
      "완료"
    )
    XCTAssertEqual(
      HomeStreakCard.weekdayAccessibilityValue(isCompleted: false),
      "미완료"
    )
  }

  @MainActor
  func testHomeBusyFeedbackRendersInNativeHomeSurface() throws {
    let routine = makeRoutine(
      id: fixtureUUID("00000000-0000-0000-0000-000000000010"),
      name: "아침 준비 루틴"
    )
    let viewModel = makeViewModel(
      routines: [routine],
      now: fixtureDate("2026-07-13T08:00:00Z")
    )
    viewModel.load()

    let view = HomeView(
      viewModel: viewModel,
      onStartRoutine: { _ in .busy },
      refreshToken: 0,
      routineSettingContent: AnyView(EmptyView()),
      initialRoutineLaunchMessage: HomeRoutineLaunchBoundary.busyMessage
    )

    let bounds = CGRect(x: 0, y: 0, width: 393, height: 1_400)
    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let hostingController = UIHostingController(rootView: view)
    let window = UIWindow(windowScene: windowScene)
    window.frame = bounds
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    hostingController.view.frame = bounds
    hostingController.view.layoutIfNeeded()

    let renderer = UIGraphicsImageRenderer(bounds: bounds)
    let image = renderer.image { _ in
      hostingController.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }
    window.isHidden = true

    let pngData = try XCTUnwrap(image.pngData())
    let screenshotURL = URL(fileURLWithPath: "/tmp/moru-g006-home-busy.png")
    try pngData.write(to: screenshotURL, options: .atomic)

    XCTAssertGreaterThan(pngData.count, 1_000)
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
    XCTAssertEqual(viewModel.state.streak.currentDays, 2)
    XCTAssertEqual(viewModel.state.streak.bestDays, 2)
    XCTAssertEqual(
      viewModel.state.streak.weekdays.map(\.id),
      ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    )
    XCTAssertEqual(
      viewModel.state.streak.weekdays.map(\.label),
      ["월", "화", "수", "목", "금", "토", "일"]
    )
    XCTAssertEqual(
      viewModel.state.streak.weekdays.filter(\.isCompleted).map(\.id),
      ["monday", "sunday"]
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
private final class SequencedHomeRoutinesUseCase: LoadHomeRoutinesUseCaseProtocol {
  private var results: [Result<HomeRoutineLoadResult, TestRepositoryError>]

  init(results: [Result<HomeRoutineLoadResult, TestRepositoryError>]) {
    self.results = results
  }

  func execute() throws -> HomeRoutineLoadResult {
    guard !results.isEmpty else {
      throw TestRepositoryError.unavailable
    }

    return try results.removeFirst().get()
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
