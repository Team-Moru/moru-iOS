//
//  LoadHistoryUseCase.swift
//  Moru
//

import Foundation

@MainActor
protocol LoadHistoryUseCaseProtocol: AnyObject {
  func load() throws -> HistoryOverview
}

@MainActor
final class LoadHistoryUseCase: LoadHistoryUseCaseProtocol {
  private let routineRunRepository: any RoutineRunRepository
  private let calendar: Calendar
  private let now: () -> Date

  init(
    routineRunRepository: any RoutineRunRepository,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { Date() }
  ) {
    self.routineRunRepository = routineRunRepository
    self.calendar = calendar
    self.now = now
  }

  func load() throws -> HistoryOverview {
    let runs = try routineRunRepository.fetchRuns().filter { $0.completedAt != nil }

    return HistoryOverview(
      calendar: calendar,
      recentDays: makeDaySummaries(from: runs),
      week: makeWeekReport(from: runs, containing: now())
    )
  }

  private func makeDaySummaries(from runs: [RoutineRun]) -> [HistoryDaySummary] {
    let dayStarts = Set(runs.map { calendar.startOfDay(for: $0.startedAt) })
      .sorted(by: >)

    return dayStarts.map { dayStart in
      makeDaySummary(for: dayStart, runs: runsDuringDay(startingAt: dayStart, from: runs))
    }
  }

  private func makeWeekReport(
    from runs: [RoutineRun],
    containing date: Date
  ) -> HistoryWeekReport {
    let weekStartDate = mondayStartingWeek(containing: date)
    let weekEndDate = calendar.date(byAdding: .day, value: 7, to: weekStartDate)!
    let weekRuns = runs.filter {
      $0.startedAt >= weekStartDate && $0.startedAt < weekEndDate
    }
    let dailyCompletionRates = (0..<7).map { offset in
      let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStartDate)!
      let dayRuns = runsDuringDay(startingAt: dayStart, from: weekRuns)

      return HistoryDailyCompletion(
        date: dayStart,
        completionRate: averageCompletionRate(for: dayRuns)
      )
    }

    return HistoryWeekReport(
      weekStartDate: weekStartDate,
      weekEndDate: weekEndDate,
      completedRunCount: completedRunCount(in: weekRuns),
      totalRunCount: weekRuns.count,
      completionRate: averageCompletionRate(for: weekRuns),
      dailyCompletionRates: dailyCompletionRates
    )
  }

  private func makeDaySummary(
    for dayStart: Date,
    runs: [RoutineRun]
  ) -> HistoryDaySummary {
    let sortedRuns = runs.sorted(by: isRunOrderedBefore)

    return HistoryDaySummary(
      date: dayStart,
      completedRunCount: completedRunCount(in: sortedRuns),
      totalRunCount: sortedRuns.count,
      completionRate: averageCompletionRate(for: sortedRuns),
      runs: sortedRuns.map(makeHistoryRun)
    )
  }

  private func runsDuringDay(
    startingAt dayStart: Date,
    from runs: [RoutineRun]
  ) -> [RoutineRun] {
    let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!

    return runs.filter {
      $0.startedAt >= dayStart && $0.startedAt < nextStartOfDay
    }
  }

  private func mondayStartingWeek(containing date: Date) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: startOfDay)
    let daysSinceMonday = (weekday + 5) % 7

    return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay)!
  }

  private func makeHistoryRun(_ run: RoutineRun) -> HistoryRun {
    let sortedSnapshots = run.plannedSteps.sorted(by: isSnapshotOrderedBefore)

    return HistoryRun(
      id: run.id,
      routineName: run.routineName,
      startedAt: run.startedAt,
      completedAt: run.completedAt,
      status: status(for: run),
      completionRate: run.completionRate,
      stepResults: sortedSnapshots.map { snapshot in
        makeStepResult(for: snapshot, results: run.results)
      }
    )
  }

  private func makeStepResult(
    for snapshot: RoutineStepSnapshot,
    results: [RoutineStepResult]
  ) -> HistoryStepResult {
    let matchingResults = results
      .filter { $0.stepID == snapshot.stepID }
      .sorted(by: isResultOrderedBefore)
    let completedResult = matchingResults.first(where: \.isCompleted)
    let isCompleted = completedResult != nil

    return HistoryStepResult(
      stepID: snapshot.stepID,
      stepTitle: snapshot.stepTitle,
      isCompleted: isCompleted,
      isSkipped: !isCompleted && matchingResults.contains(where: \.skipped),
      transcript: completedResult?.transcript ?? matchingResults.first?.transcript
    )
  }

  private func status(for run: RoutineRun) -> HistoryRunStatus {
    if run.endedEarly {
      return .endedEarly
    }

    return run.completionRate == 1 ? .completed : .partial
  }

  private func completedRunCount(in runs: [RoutineRun]) -> Int {
    runs.filter { status(for: $0) == .completed }.count
  }

  private func averageCompletionRate(for runs: [RoutineRun]) -> Double {
    guard !runs.isEmpty else {
      return 0
    }

    return runs
      .sorted(by: isRunOrderedBefore)
      .reduce(0) { $0 + $1.completionRate } / Double(runs.count)
  }

  private func isRunOrderedBefore(_ lhs: RoutineRun, _ rhs: RoutineRun) -> Bool {
    if lhs.startedAt != rhs.startedAt {
      return lhs.startedAt > rhs.startedAt
    }

    return lhs.id.uuidString < rhs.id.uuidString
  }

  private func isSnapshotOrderedBefore(
    _ lhs: RoutineStepSnapshot,
    _ rhs: RoutineStepSnapshot
  ) -> Bool {
    if lhs.stepOrder != rhs.stepOrder {
      return lhs.stepOrder < rhs.stepOrder
    }

    return lhs.stepID.uuidString < rhs.stepID.uuidString
  }

  private func isResultOrderedBefore(
    _ lhs: RoutineStepResult,
    _ rhs: RoutineStepResult
  ) -> Bool {
    lhs.id.uuidString < rhs.id.uuidString
  }
}
