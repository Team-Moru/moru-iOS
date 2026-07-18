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
  private let historyEvidenceRepository: any HistoryEvidenceRepository
  private let currentResetGeneration: () -> UInt64?
  private let calendar: Calendar
  private let now: () -> Date

  init(
    routineRunRepository: any RoutineRunRepository,
    historyEvidenceRepository: any HistoryEvidenceRepository,
    currentResetGeneration: @escaping () -> UInt64?,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { Date() }
  ) {
    self.routineRunRepository = routineRunRepository
    self.historyEvidenceRepository = historyEvidenceRepository
    self.currentResetGeneration = currentResetGeneration
    self.calendar = calendar
    self.now = now
  }

  func load() throws -> HistoryOverview {
    let currentDate = now()
    let runs = try routineRunRepository.fetchRuns().filter { $0.completedAt != nil }
    let evidence = try historyEvidenceRepository.fetchEvidence()

    return HistoryOverview(
      calendar: calendar,
      recentDays: makeDaySummaries(from: runs),
      week: makeWeekReport(from: runs, containing: currentDate),
      wakeMetrics: makeWakeMetrics(from: evidence, containing: currentDate),
      monthlyHeatmap: makeMonthlyHeatmap(from: runs, containing: currentDate)
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

  private func makeWakeMetrics(
    from evidence: HistoryEvidence,
    containing now: Date
  ) -> HistoryWakeMetrics {
    guard let currentResetGeneration = currentResetGeneration(),
          currentResetGeneration > 0 else {
      return .unavailable
    }

    let calendar = gregorianCalendar
    let intervalStart = calendar.date(
      byAdding: .day,
      value: -27,
      to: calendar.startOfDay(for: now)
    )!
    let intervalEnd = calendar.date(byAdding: .day, value: 28, to: intervalStart)!
    let observations = validTerminalObservations(
      from: evidence,
      currentResetGeneration: currentResetGeneration
    )
      .filter { observation in
        guard let observedDay = date(
          fromStoredGregorianDayKey: observation.localGregorianDayKey,
          calendar: calendar
        ) else {
          return false
        }

        return observedDay >= intervalStart && observedDay < intervalEnd
      }

    guard observations.count >= 3 else {
      return .insufficient(observationCount: observations.count)
    }

    let mean = circularMeanMinute(for: observations)
    let averageWakeMinute = normalizedRoundedMinute(mean)
    let averageDeviation = observations
      .map { shortestCircularDeviation(from: Double($0.localMinute), to: mean) }
      .reduce(0, +) / Double(observations.count)
    let averageDeviationMinutes = roundedAwayFromZero(averageDeviation)
    let consistencyScore = min(
      max(roundedAwayFromZero(100 * (1 - averageDeviation / 60)), 0),
      100
    )

    return .calculated(
      observationCount: observations.count,
      averageWakeMinute: averageWakeMinute,
      averageDeviationMinutes: averageDeviationMinutes,
      consistencyScore: consistencyScore
    )
  }

  private func validTerminalObservations(
    from evidence: HistoryEvidence,
    currentResetGeneration: UInt64
  ) -> [ScheduledAlarmStartObservationSnapshot] {
    let observationsByOccurrenceID = Dictionary(
      grouping: evidence.observations,
      by: \.occurrenceID
    )
    let rootStatesByOccurrenceID = Dictionary(
      grouping: evidence.rootChainStates,
      by: \.rootOccurrenceID
    )

    return rootStatesByOccurrenceID.values.compactMap { rootStates in
      guard rootStates.count == 1,
            let rootState = rootStates.first,
            !rootState.rootOccurrenceID.isEmpty,
            rootState.state == .terminal,
            rootState.resetGeneration == currentResetGeneration,
            let earliestOccurrenceID = rootState.earliestObservedOccurrenceID,
            !earliestOccurrenceID.isEmpty,
            let earliestObservedAt = rootState.earliestObservedAt,
            let terminalOccurrenceID = rootState.terminalOccurrenceID,
            !terminalOccurrenceID.isEmpty,
            let terminalAt = rootState.terminalAt,
            rootState.latestObservedOccurrenceID == terminalOccurrenceID,
            rootState.latestObservedAt == terminalAt,
            earliestObservedAt <= terminalAt,
            let rootObservation = uniqueObservation(
              for: earliestOccurrenceID,
              in: observationsByOccurrenceID
            ),
            let terminalObservation = uniqueObservation(
              for: terminalOccurrenceID,
              in: observationsByOccurrenceID
            ),
            rootObservation.actionObservedAt == earliestObservedAt,
            terminalObservation.actionObservedAt == terminalAt else {
        return nil
      }

      let chainObservations = evidence.observations.filter {
        $0.rootOccurrenceID == rootState.rootOccurrenceID
      }
      let chainOccurrenceIDs = Set(chainObservations.map(\.occurrenceID))
      guard !chainObservations.isEmpty,
            chainObservations.count == chainOccurrenceIDs.count,
            chainObservations.allSatisfy({
              isObservationCompatible($0, with: rootState)
            }),
            isObservationCompatible(rootObservation, with: rootState),
            isObservationCompatible(terminalObservation, with: rootState),
            hasValidTerminalLineage(
              terminalObservation,
              rootObservation: rootObservation,
              earliestObservedAt: earliestObservedAt,
              chainOccurrenceIDs: chainOccurrenceIDs,
              observationsByOccurrenceID: observationsByOccurrenceID,
              rootState: rootState
            ) else {
        return nil
      }

      return terminalObservation
    }
    .sorted(by: isObservationOrderedBefore)
  }

  private func hasValidTerminalLineage(
    _ terminalObservation: ScheduledAlarmStartObservationSnapshot,
    rootObservation: ScheduledAlarmStartObservationSnapshot,
    earliestObservedAt: Date,
    chainOccurrenceIDs: Set<String>,
    observationsByOccurrenceID: [String: [ScheduledAlarmStartObservationSnapshot]],
    rootState: AlarmRootChainStateSnapshot
  ) -> Bool {
    var currentObservation = terminalObservation
    var lineageOccurrenceIDs = Set<String>()

    while true {
      guard lineageOccurrenceIDs.insert(currentObservation.occurrenceID).inserted,
            isObservationCompatible(currentObservation, with: rootState) else {
        return false
      }

      if currentObservation.occurrenceID == rootObservation.occurrenceID {
        return currentObservation.parentOccurrenceID == nil
          && currentObservation.actionObservedAt == earliestObservedAt
          && lineageOccurrenceIDs == chainOccurrenceIDs
      }

      guard let parentOccurrenceID = currentObservation.parentOccurrenceID,
            !parentOccurrenceID.isEmpty,
            let parentObservation = uniqueObservation(
              for: parentOccurrenceID,
              in: observationsByOccurrenceID
            ),
            parentObservation.actionObservedAt <= currentObservation.actionObservedAt else {
        return false
      }

      currentObservation = parentObservation
    }
  }

  private func uniqueObservation(
    for occurrenceID: String,
    in observationsByOccurrenceID: [String: [ScheduledAlarmStartObservationSnapshot]]
  ) -> ScheduledAlarmStartObservationSnapshot? {
    guard let observations = observationsByOccurrenceID[occurrenceID],
          observations.count == 1 else {
      return nil
    }

    return observations[0]
  }

  private func isObservationCompatible(
    _ observation: ScheduledAlarmStartObservationSnapshot,
    with rootState: AlarmRootChainStateSnapshot
  ) -> Bool {
    !observation.occurrenceID.isEmpty
      && observation.parentOccurrenceID?.isEmpty != true
      && observation.source == .alarmKitOccurrenceActionV1
      && observation.rootOccurrenceID == rootState.rootOccurrenceID
      && observation.routineID == rootState.routineID
      && observation.scheduleID == rootState.scheduleID
      && observation.resetGeneration == rootState.resetGeneration
      && (0...1_439).contains(observation.localMinute)
  }

  private func circularMeanMinute(
    for observations: [ScheduledAlarmStartObservationSnapshot]
  ) -> Double {
    let radiansPerMinute = 2 * Double.pi / 1_440
    let sineSum = observations.reduce(0.0) { partial, observation in
      partial + sin(Double(observation.localMinute) * radiansPerMinute)
    }
    let cosineSum = observations.reduce(0.0) { partial, observation in
      partial + cos(Double(observation.localMinute) * radiansPerMinute)
    }

    guard hypot(sineSum, cosineSum) / Double(observations.count) > 1e-12 else {
      return Double(observations.sorted(by: isObservationOrderedBefore)[0].localMinute)
    }

    let meanRadians = atan2(sineSum, cosineSum)
    let minute = meanRadians / radiansPerMinute
    return minute >= 0 ? minute : minute + 1_440
  }

  private func makeMonthlyHeatmap(
    from runs: [RoutineRun],
    containing date: Date
  ) -> HistoryMonthlyHeatmap {
    let calendar = gregorianCalendar
    let today = calendar.startOfDay(for: date)
    var monthComponents = calendar.dateComponents([.year, .month], from: today)
    monthComponents.day = 1
    let monthStart = calendar.date(from: monthComponents)!
    let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
    let dayCount = calendar.dateComponents([.day], from: monthStart, to: today).day! + 1
    let weekday = calendar.component(.weekday, from: monthStart)
    let leadingFillerCount = (weekday + 5) % 7
    let eligibleRuns = runs.filter { run in
      guard let completedAt = run.completedAt else {
        return false
      }

      return !run.endedEarly
        && status(for: run) == .completed
        && run.startedAt >= monthStart
        && run.startedAt < monthEnd
        && run.startedAt <= date
        && completedAt <= date
    }
    let runsByDay = Dictionary(
      grouping: eligibleRuns,
      by: { calendar.startOfDay(for: $0.startedAt) }
    )
    let fillers = (0..<leadingFillerCount).map {
      HistoryHeatmapDay(id: "filler-\($0)", date: nil, completionRate: nil)
    }
    let days = (0..<dayCount).map { offset in
      let day = calendar.date(byAdding: .day, value: offset, to: monthStart)!
      let dayRuns = runsByDay[day] ?? []

      return HistoryHeatmapDay(
        id: gregorianDayKey(for: day, calendar: calendar),
        date: day,
        completionRate: dayRuns.isEmpty ? nil : averageCompletionRate(for: dayRuns)
      )
    }

    return HistoryMonthlyHeatmap(monthStartDate: monthStart, days: fillers + days)
  }

  private var gregorianCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = self.calendar.locale
    calendar.timeZone = self.calendar.timeZone
    return calendar
  }

  private func date(
    fromStoredGregorianDayKey key: String,
    calendar: Calendar
  ) -> Date? {
    let bytes = Array(key.utf8)
    let values = key.split(separator: "-", omittingEmptySubsequences: false)
    guard bytes.count == 10,
          bytes[4] == 45,
          bytes[7] == 45,
          values.count == 3,
          let year = Int(values[0]),
          let month = Int(values[1]),
          let day = Int(values[2]) else {
      return nil
    }

    let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    let resolved = date.map {
      calendar.dateComponents([.year, .month, .day], from: $0)
    }
    guard resolved?.year == year,
          resolved?.month == month,
          resolved?.day == day else {
      return nil
    }

    return date
  }

  private func gregorianDayKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
  }

  private func shortestCircularDeviation(from minute: Double, to mean: Double) -> Double {
    let difference = abs(minute - mean)
    return min(difference, 1_440 - difference)
  }

  private func normalizedRoundedMinute(_ minute: Double) -> Int {
    let rounded = roundedAwayFromZero(minute)
    return ((rounded % 1_440) + 1_440) % 1_440
  }

  private func roundedAwayFromZero(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrAwayFromZero))
  }

  private func isObservationOrderedBefore(
    _ lhs: ScheduledAlarmStartObservationSnapshot,
    _ rhs: ScheduledAlarmStartObservationSnapshot
  ) -> Bool {
    if lhs.actionObservedAt != rhs.actionObservedAt {
      return lhs.actionObservedAt < rhs.actionObservedAt
    }

    return Array(lhs.occurrenceID.utf8)
      .lexicographicallyPrecedes(Array(rhs.occurrenceID.utf8))
  }
}
