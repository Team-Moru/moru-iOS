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
  private let streakCalculator: RoutineStreakCalculator

  init(
    routineRunRepository: any RoutineRunRepository,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { Date() }
  ) {
    self.routineRunRepository = routineRunRepository
    self.calendar = calendar
    self.now = now
    self.streakCalculator = RoutineStreakCalculator(calendar: calendar)
  }

  func load() throws -> HistoryOverview {
    let currentDate = now()
    let runs = try routineRunRepository.fetchRuns().filter { $0.completedAt != nil }

    return HistoryOverview(
      calendar: calendar,
      recentDays: makeDaySummaries(from: runs),
      week: makeWeekReport(from: runs, containing: currentDate),
      wakeMetrics: makeWakeMetrics(from: runs, containing: currentDate),
      monthlyHeatmap: makeMonthlyHeatmap(from: runs, containing: currentDate),
      streak: streakCalculator.calculate(from: runs, asOf: currentDate)
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
    let previousWeekStartDate = calendar.date(
      byAdding: .day,
      value: -7,
      to: weekStartDate
    )!
    let previousWeekRuns = runs.filter {
      $0.startedAt >= previousWeekStartDate && $0.startedAt < weekStartDate
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
      dailyCompletionRates: dailyCompletionRates,
      completionRateChangePercentagePoints: completionRateChange(
        currentRuns: weekRuns,
        previousRuns: previousWeekRuns
      )
    )
  }

  private func completionRateChange(
    currentRuns: [RoutineRun],
    previousRuns: [RoutineRun]
  ) -> Int? {
    guard !previousRuns.isEmpty else {
      return nil
    }

    let difference = (
      averageCompletionRate(for: currentRuns)
        - averageCompletionRate(for: previousRuns)
    ) * 100

    return Int(difference.rounded(.toNearestOrAwayFromZero))
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

  private func makeWakeMetrics(
    from runs: [RoutineRun],
    containing date: Date
  ) -> HistoryWakeMetrics {
    let today = calendar.startOfDay(for: date)
    let intervalStart = calendar.date(byAdding: .day, value: -27, to: today)!
    let intervalEnd = calendar.date(byAdding: .day, value: 1, to: today)!
    let eligibleRuns = runs.filter { run in
      guard let completedAt = run.completedAt else {
        return false
      }

      return run.startedAt >= intervalStart
        && run.startedAt < intervalEnd
        && run.startedAt <= date
        && completedAt <= date
    }
    let dailyFirstRuns = Dictionary(
      grouping: eligibleRuns,
      by: { calendar.startOfDay(for: $0.startedAt) }
    )
      .values
      .compactMap { $0.min(by: isRunStartedBefore) }
      .sorted(by: isRunStartedBefore)
    let observationCount = dailyFirstRuns.count

    guard observationCount > 0 else {
      return .unavailable
    }

    guard observationCount >= 3 else {
      return .insufficient(observationCount: observationCount)
    }

    let minutes = dailyFirstRuns.map { minuteOfDay(for: $0.startedAt) }
    let mean = circularMeanMinute(for: minutes)
    let averageWakeMinute = normalizedRoundedMinute(mean)
    let averageDeviation = minutes
      .map { shortestCircularDeviation(from: Double($0), to: mean) }
      .reduce(0, +) / Double(minutes.count)
    let averageDeviationMinutes = Int(averageDeviation.rounded(.toNearestOrAwayFromZero))

    return .calculated(
      observationCount: observationCount,
      averageWakeMinute: averageWakeMinute,
      averageDeviationMinutes: averageDeviationMinutes,
      regularity: HistoryStartTimeRegularity(
        averageDeviationMinutes: averageDeviationMinutes
      )
    )
  }

  private func makeMonthlyHeatmap(
    from runs: [RoutineRun],
    containing date: Date
  ) -> HistoryMonthlyHeatmap {
    let today = calendar.startOfDay(for: date)
    var monthComponents = calendar.dateComponents([.year, .month], from: today)
    monthComponents.day = 1

    let monthStart = calendar.date(from: monthComponents)!
    let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
    let dayCount = calendar.dateComponents(
      [.day],
      from: monthStart,
      to: monthEnd
    ).day!
    let weekday = calendar.component(.weekday, from: monthStart)
    let leadingFillerCount = (weekday + 5) % 7
    let eligibleRuns = runs.filter { run in
      guard let completedAt = run.completedAt else {
        return false
      }

      return run.startedAt >= monthStart
        && run.startedAt < monthEnd
        && run.startedAt <= date
        && completedAt <= date
    }
    let runsByDay = Dictionary(
      grouping: eligibleRuns,
      by: { calendar.startOfDay(for: $0.startedAt) }
    )
    let fillers = (0..<leadingFillerCount).map { offset in
      HistoryHeatmapDay(
        id: "filler-\(offset)",
        date: nil,
        completionRate: nil
      )
    }
    let days = (0..<dayCount).map { offset in
      let day = calendar.date(byAdding: .day, value: offset, to: monthStart)!
      let dayRuns = runsByDay[day] ?? []

      return HistoryHeatmapDay(
        id: dayKey(for: day),
        date: day,
        completionRate: dayRuns.isEmpty ? nil : averageCompletionRate(for: dayRuns)
      )
    }

    return HistoryMonthlyHeatmap(
      monthStartDate: monthStart,
      days: fillers + days
    )
  }

  private func minuteOfDay(for date: Date) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  private func circularMeanMinute(for minutes: [Int]) -> Double {
    let radiansPerMinute = 2 * Double.pi / 1_440
    let sineSum = minutes.reduce(0.0) { partial, minute in
      partial + sin(Double(minute) * radiansPerMinute)
    }
    let cosineSum = minutes.reduce(0.0) { partial, minute in
      partial + cos(Double(minute) * radiansPerMinute)
    }

    guard hypot(sineSum, cosineSum) / Double(minutes.count) > 1e-12 else {
      return Double(minutes.sorted()[0])
    }

    let meanRadians = atan2(sineSum, cosineSum)
    let minute = meanRadians / radiansPerMinute
    return minute >= 0 ? minute : minute + 1_440
  }

  private func shortestCircularDeviation(from minute: Double, to mean: Double) -> Double {
    let difference = abs(minute - mean)
    return min(difference, 1_440 - difference)
  }

  private func normalizedRoundedMinute(_ minute: Double) -> Int {
    let rounded = Int(minute.rounded(.toNearestOrAwayFromZero))
    return ((rounded % 1_440) + 1_440) % 1_440
  }

  private func dayKey(for date: Date) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year!,
      components.month!,
      components.day!
    )
  }

  private func isRunStartedBefore(_ lhs: RoutineRun, _ rhs: RoutineRun) -> Bool {
    if lhs.startedAt != rhs.startedAt {
      return lhs.startedAt < rhs.startedAt
    }

    return lhs.id.uuidString < rhs.id.uuidString
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
