//
//  HomeHistoryVerticalFlowTests.swift
//  MoruTests
//
//  Created by Codex on 7/14/26.
//

import Foundation
import SwiftUI
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
      ),
      weatherRepository: nil,
      weatherService: nil
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

    guard case .summary(.regular(let regularCompletion)) = regularPlayer.screenState else {
      XCTFail("A regular Home launch should finish with a saved summary.")
      return
    }

    let savedRunID = regularCompletion.persistedRunID
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

    guard case .summary(.trial(let trialSummary)) = trialPlayer.screenState else {
      XCTFail("A trial launch should finish with a summary.")
      return
    }

    XCTAssertNil(trialSummary.persistedRunID)
    XCTAssertEqual(try runRepository.fetchRuns().count, 1)

    let overview = try LoadHistoryUseCase(
      routineRunRepository: runRepository,
      historyEvidenceRepository: MockHistoryEvidenceRepository(),
      currentResetGeneration: { nil },
      calendar: calendar,
      now: { now }
    ).load()
    let historyRun = try XCTUnwrap(overview.recentDays.first?.runs.first)

    XCTAssertEqual(historyRun.id, savedRunID)
    XCTAssertEqual(historyRun.routineName, homeRoutine.title)
    XCTAssertEqual(historyRun.status, .completed)
    XCTAssertEqual(historyRun.stepResults.map(\.stepTitle), [step.title])
  }
  @MainActor
  func testHistoryViewModelTransitionsFromLoadingToFailed() {
    let useCase = SequencedHistoryLoadUseCase(results: [.failure(.loadFailed)])
    let viewModel = HistoryViewModel(loadHistoryUseCase: useCase)

    guard case .loading = viewModel.state else {
      XCTFail("A new History view model should begin in the loading state.")
      return
    }

    viewModel.load()

    guard case .failed(let message) = viewModel.state else {
      XCTFail("A failed History load should produce the failed state.")
      return
    }

    XCTAssertEqual(message, "기록을 불러오지 못했어요.")
  }

  @MainActor
  func testHistoryViewModelMapsEmptyOverviewToEmptyState() {
    let useCase = SequencedHistoryLoadUseCase(
      results: [.success(makeHistoryOverview(recentDays: []))]
    )
    let viewModel = HistoryViewModel(loadHistoryUseCase: useCase)

    viewModel.load()

    guard case .empty = viewModel.state else {
      XCTFail("An overview without recent days should produce the empty state.")
      return
    }

    XCTAssertEqual(useCase.loadCount, 1)
  }

  @MainActor
  func testHistoryViewModelRetriesFromFailureToContent() {
    let expectedOverview = makeHistoryOverview(recentDays: [makeHistoryDaySummary()])
    let useCase = SequencedHistoryLoadUseCase(
      results: [
        .failure(.loadFailed),
        .success(expectedOverview)
      ]
    )
    let viewModel = HistoryViewModel(loadHistoryUseCase: useCase)

    viewModel.load()

    guard case .failed = viewModel.state else {
      XCTFail("The first sequenced result should fail.")
      return
    }

    viewModel.retryButtonDidTap()

    guard case .content(let overview) = viewModel.state else {
      XCTFail("Retry should load the next successful result.")
      return
    }

    XCTAssertEqual(overview, expectedOverview)
    XCTAssertEqual(useCase.loadCount, 2)
  }

  @MainActor
  func testHistoryViewModelDoesNotLoadAlternateFallbackAfterFailure() {
    let useCase = SequencedHistoryLoadUseCase(
      results: [
        .failure(.loadFailed),
        .success(makeHistoryOverview(recentDays: [makeHistoryDaySummary()]))
      ]
    )
    let viewModel = HistoryViewModel(loadHistoryUseCase: useCase)

    viewModel.load()

    guard case .failed = viewModel.state else {
      XCTFail("The first failure should remain visible until the user retries.")
      return
    }

    XCTAssertEqual(useCase.loadCount, 1)
  }

  @MainActor
  func testHistoryViewModelKeepsWakeOnlyOverviewAsContent() {
    let expectedOverview = makeHistoryOverview(
      recentDays: [],
      wakeMetrics: .insufficient(observationCount: 1)
    )
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: SequencedHistoryLoadUseCase(results: [.success(expectedOverview)])
    )

    viewModel.load()

    guard case .content(let overview) = viewModel.state else {
      XCTFail("Wake observations should keep the History dashboard visible.")
      return
    }

    XCTAssertEqual(overview, expectedOverview)
  }

  @MainActor
  func testHistoryViewModelKeepsHeatmapOnlyOverviewAsContent() {
    let date = Date(timeIntervalSince1970: 0)
    let expectedOverview = makeHistoryOverview(
      recentDays: [],
      monthlyHeatmap: HistoryMonthlyHeatmap(
        monthStartDate: date,
        days: [HistoryHeatmapDay(id: "1970-01-01", date: date, completionRate: 1)]
      )
    )
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: SequencedHistoryLoadUseCase(results: [.success(expectedOverview)])
    )

    viewModel.load()

    guard case .content(let overview) = viewModel.state else {
      XCTFail("Heatmap evidence should keep the History dashboard visible.")
      return
    }

    XCTAssertEqual(overview, expectedOverview)
  }

  @MainActor
  func testHistoryRunDetailDestinationSelectsExactRunAndConsumesBinding() {
    let requestedID = UUID()
    let otherID = UUID()
    let requestedRun = makeHistoryRun(id: requestedID)
    let otherRun = makeHistoryRun(id: otherID)
    let overview = makeHistoryOverview(
      recentDays: [
        HistoryDaySummary(
          date: Date(timeIntervalSince1970: 0),
          completedRunCount: 2,
          totalRunCount: 2,
          completionRate: 1,
          runs: [otherRun, requestedRun]
        ),
      ]
    )
    var pendingDestination: HistoryDestination? = .runDetail(requestedID)
    let destination = Binding<HistoryDestination?>(
      get: { pendingDestination },
      set: { pendingDestination = $0 }
    )

    let resolution = HistoryRunDetailDestinationResolver.resolve(
      destination: destination,
      in: overview
    )

    guard case .selected(let presentation) = resolution else {
      XCTFail("The requested run should resolve when exactly one matching ID exists.")
      return
    }

    XCTAssertEqual(presentation.run, requestedRun)
    XCTAssertEqual(presentation.calendar, overview.calendar)
    XCTAssertNil(pendingDestination)
  }

  @MainActor
  func testHistoryRunDetailDestinationFailsClosedForMissingAndDuplicateIDs() {
    let missingID = UUID()
    let matchingID = UUID()
    let firstRun = makeHistoryRun(id: matchingID)
    let duplicateRun = makeHistoryRun(id: matchingID)
    let missingOverview = makeHistoryOverview(recentDays: [makeHistoryDaySummary()])
    var missingDestination: HistoryDestination? = .runDetail(missingID)
    let missingBinding = Binding<HistoryDestination?>(
      get: { missingDestination },
      set: { missingDestination = $0 }
    )

    let missingResolution = HistoryRunDetailDestinationResolver.resolve(
      destination: missingBinding,
      in: missingOverview
    )

    XCTAssertEqual(missingResolution, .missing)
    XCTAssertEqual(missingDestination, .runDetail(missingID))

    let duplicateOverview = makeHistoryOverview(
      recentDays: [
        HistoryDaySummary(
          date: Date(timeIntervalSince1970: 0),
          completedRunCount: 1,
          totalRunCount: 1,
          completionRate: 1,
          runs: [firstRun]
        ),
        HistoryDaySummary(
          date: Date(timeIntervalSince1970: 86_400),
          completedRunCount: 1,
          totalRunCount: 1,
          completionRate: 1,
          runs: [duplicateRun]
        ),
      ]
    )
    var duplicateDestination: HistoryDestination? = .runDetail(matchingID)
    let duplicateBinding = Binding<HistoryDestination?>(
      get: { duplicateDestination },
      set: { duplicateDestination = $0 }
    )

    let duplicateResolution = HistoryRunDetailDestinationResolver.resolve(
      destination: duplicateBinding,
      in: duplicateOverview
    )

    XCTAssertEqual(duplicateResolution, .missing)
    XCTAssertEqual(duplicateDestination, .runDetail(matchingID))
  }
}

@MainActor
private final class SequencedHistoryLoadUseCase: LoadHistoryUseCaseProtocol {
  private var results: [HistoryLoadResult]
  private(set) var loadCount = 0

  init(results: [HistoryLoadResult]) {
    self.results = results
  }

  func load() throws -> HistoryOverview {
    loadCount += 1

    guard !results.isEmpty else {
      throw HistoryLoadTestError.noResultAvailable
    }

    switch results.removeFirst() {
    case .success(let overview):
      return overview
    case .failure(let error):
      throw error
    }
  }
}

private enum HistoryLoadResult {
  case success(HistoryOverview)
  case failure(HistoryLoadTestError)
}

private enum HistoryLoadTestError: Error {
  case loadFailed
  case noResultAvailable
}

private func makeHistoryOverview(
  recentDays: [HistoryDaySummary],
  wakeMetrics: HistoryWakeMetrics = .insufficient(observationCount: 0),
  monthlyHeatmap: HistoryMonthlyHeatmap = .empty
) -> HistoryOverview {
  let date = Date(timeIntervalSince1970: 0)

  return HistoryOverview(
    calendar: Calendar(identifier: .gregorian),
    recentDays: recentDays,
    week: HistoryWeekReport(
      weekStartDate: date,
      weekEndDate: date.addingTimeInterval(7 * 24 * 60 * 60),
      completedRunCount: 0,
      totalRunCount: 0,
      completionRate: 0,
      dailyCompletionRates: []
    ),
    wakeMetrics: wakeMetrics,
    monthlyHeatmap: monthlyHeatmap
  )
}

private func makeHistoryDaySummary() -> HistoryDaySummary {
  HistoryDaySummary(
    date: Date(timeIntervalSince1970: 0),
    completedRunCount: 1,
    totalRunCount: 1,
    completionRate: 1,
    runs: []
  )
}
private func makeHistoryRun(id: UUID) -> HistoryRun {
  HistoryRun(
    id: id,
    routineName: "동일한 루틴",
    startedAt: Date(timeIntervalSince1970: 0),
    completedAt: Date(timeIntervalSince1970: 60),
    status: .completed,
    completionRate: 1,
    stepResults: []
  )
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

  func finalize(_ request: SaveRoutineRunRequest) throws -> RegularRoutineCompletionResult {
    let savedRun = try saveRoutineRunUseCase.execute(request)
    let summary = try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: savedRun.id,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    ).get()

    guard let result = RegularRoutineCompletionResult(summary) else {
      throw RegularRoutineFinalizationError.missingPersistedRunID
    }

    return result
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
