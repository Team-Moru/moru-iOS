//
//  HomeHistoryVerticalFlowTests.swift
//  MoruTests
//
//  Created by Codex on 7/14/26.
//

import Foundation
import XCTest
@testable import Moru

final class HomeHistoryVerticalFlowTests: XCTestCase {
  @MainActor
  func testHomeSelectedRegularRunAppearsInHistoryWithoutManufacturingTrialRun() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date()
    let weekday = Weekday(rawValue: calendar.component(.weekday, from: now))!
    let step = RoutineStep(type: .confirm, title: "물 마시기", order: 0)
    let routine = Routine(
      name: "아침 루틴",
      steps: [step],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 0,
        weekdays: [weekday]
      )
    )
    let competingRoutine = Routine(
      name: "경쟁 루틴",
      steps: [RoutineStep(type: .confirm, title: "스트레칭", order: 0)],
      alarmSchedule: AlarmSchedule(
        hour: 8,
        minute: 0,
        weekdays: [weekday]
      )
    )
    let routineRepository = VerticalFlowRoutineRepository(
      routines: [competingRoutine, routine]
    )
    let runRepository = VerticalFlowRoutineRunRepository()
    let homeViewModel = HomeViewModel(
      loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
        routineRepository: routineRepository,
        routineRunRepository: runRepository,
        localProfileRepository: VerticalFlowProfileRepository(),
        calendar: calendar,
        now: { now }
      )
    )

    homeViewModel.load()

    let homeRoutine = try XCTUnwrap(homeViewModel.state.todayRoutine)
    XCTAssertEqual(homeRoutine.id, routine.id)
    let launchRequest = RoutineLaunchRequest(routineID: homeRoutine.id)
    let resolver = ResolveRoutineExecutionUseCase(routineRepository: routineRepository)
    let regularPlayer = RoutinePlayerViewModel(
      request: RegularRoutineExecutionRequest(
        routineID: launchRequest.routineID,
        source: .manual
      ),
      resolver: resolver,
      finalizer: VerticalFlowRegularFinalizer(
        saveRoutineRunUseCase: SaveRoutineRunUseCase(routineRunRepository: runRepository)
      ),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    regularPlayer.resolveRoutine()
    regularPlayer.completeCurrentStep()
    regularPlayer.finishStepCompletedScreen()

    guard case .summary(let regularSummary) = regularPlayer.screenState else {
      XCTFail("A regular Home launch should finish with a saved summary.")
      return
    }

    let savedRunID = try XCTUnwrap(regularSummary.persistedRunID)
    let savedRuns = try runRepository.fetchRuns()
    let savedRun = try XCTUnwrap(savedRuns.first)
    XCTAssertEqual(savedRunID, savedRun.id)
    XCTAssertEqual(savedRun.routineID, homeRoutine.id)

    let trialPlayer = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: homeRoutine.id),
      resolver: resolver,
      finalizer: VerticalFlowTrialFinalizer(),
      presentationToken: UUID(),
      onEvent: { _, _ in }
    )

    trialPlayer.resolveRoutine()
    trialPlayer.completeCurrentStep()
    trialPlayer.finishStepCompletedScreen()

    guard case .summary(let trialSummary) = trialPlayer.screenState else {
      XCTFail("A trial launch should finish with a summary.")
      return
    }

    XCTAssertNil(trialSummary.persistedRunID)
    XCTAssertEqual(try runRepository.fetchRuns().count, 1)

    let overview = try LoadHistoryUseCase(
      routineRunRepository: runRepository,
      calendar: calendar,
      now: { now }
    ).load()
    let historyRun = try XCTUnwrap(overview.recentDays.first?.runs.first)

    XCTAssertEqual(historyRun.id, savedRunID)
    XCTAssertEqual(historyRun.routineName, homeRoutine.title)
    XCTAssertEqual(historyRun.status, .completed)
    XCTAssertEqual(historyRun.stepResults.map(\.stepTitle), [step.title])
  }
}

@MainActor
private final class VerticalFlowRoutineRepository: RoutineRepository {
  private var routines: [Routine]

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
    if let index = routines.firstIndex(where: { $0.id == routine.id }) {
      routines[index] = routine
    } else {
      routines.append(routine)
    }
  }

  func saveRoutines(_ routines: [Routine]) throws {
    for routine in routines {
      try saveRoutine(routine)
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

@MainActor
private final class VerticalFlowRoutineRunRepository: RoutineRunRepository {
  private var runs: [RoutineRun] = []

  func fetchRuns() throws -> [RoutineRun] {
    runs
  }

  func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
    Array(runs.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
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
    try fetchRuns(from: startDate, to: endDate).filter { $0.routineID == routineID }
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
private final class VerticalFlowProfileRepository: LocalProfileRepository {
  private var profile: LocalProfile?

  func fetchProfile() throws -> LocalProfile? {
    profile
  }

  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile {
      return profile
    }

    let createdProfile = LocalProfile()
    profile = createdProfile
    return createdProfile
  }

  func saveProfile(_ profile: LocalProfile) throws {
    self.profile = profile
  }

  func deleteProfile() throws {
    profile = nil
  }
}

@MainActor
private final class VerticalFlowRegularFinalizer: RegularRoutineFinalizing {
  private let saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol

  init(saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol) {
    self.saveRoutineRunUseCase = saveRoutineRunUseCase
  }

  func finalize(_ request: SaveRoutineRunRequest) throws -> RoutineCompletionSummary {
    let savedRun = try saveRoutineRunUseCase.execute(request)

    return try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: savedRun.id,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    ).get()
  }
}

@MainActor
private final class VerticalFlowTrialFinalizer: TrialRoutineFinalizing {
  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
    makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      endedEarly: false
    )
  }
}
