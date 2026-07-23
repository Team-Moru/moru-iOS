//
//  LoadHomeRoutinesUseCase.swift
//  Moru
//

import Foundation

struct HomeRoutineStreak: Equatable {
  let currentDays: Int
  let bestDays: Int
  let completedWeekdays: Set<Weekday>
}

struct HomeRoutineLoadResult: Equatable {
  let profile: LocalProfile?
  let todayRoutine: Routine?
  let manualRoutines: [Routine]
  let todayRunsByRoutineID: [UUID: RoutineRun]
  let streak: HomeRoutineStreak
}

@MainActor
protocol LoadHomeRoutinesUseCaseProtocol: AnyObject {
  func execute() throws -> HomeRoutineLoadResult
}

@MainActor
final class LoadHomeRoutinesUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let routineRepository: any RoutineRepository
  private let routineRunRepository: any RoutineRunRepository
  private let localProfileRepository: any LocalProfileRepository
  private let calendar: Calendar
  private let now: () -> Date

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    calendar: Calendar = .current,
    now: @escaping () -> Date = Date.init
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.calendar = calendar
    self.now = now
  }

  func execute() throws -> HomeRoutineLoadResult {
    let currentDate = now()
    let profile = try localProfileRepository.fetchProfile()
    let activeRoutines = try routineRepository.fetchActiveRoutines().filter(\.isActive)
    let manualRoutines = manuallyLaunchableRoutines(from: activeRoutines)
    let todayRoutine = scheduledRoutine(for: currentDate, from: manualRoutines)
    let runs = try routineRunRepository.fetchRuns()

    return HomeRoutineLoadResult(
      profile: profile,
      todayRoutine: todayRoutine,
      manualRoutines: manualRoutines,
      todayRunsByRoutineID: latestTodayRuns(
        for: manualRoutines,
        from: runs,
        currentDate: currentDate
      ),
      streak: makeStreak(from: runs, currentDate: currentDate)
    )
  }

  private func manuallyLaunchableRoutines(from routines: [Routine]) -> [Routine] {
    routines
      .filter { !$0.steps.isEmpty }
      .sorted { lhs, rhs in
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
      }
  }

  private func scheduledRoutine(for currentDate: Date, from routines: [Routine]) -> Routine? {
    let weekday = weekday(from: currentDate)

    return routines
      .filter { routine in
        guard let schedule = routine.alarmSchedule else {
          return false
        }

        return schedule.isEnabled && schedule.weekdays.contains(weekday)
      }
      .sorted { lhs, rhs in
        guard let lhsSchedule = lhs.alarmSchedule,
              let rhsSchedule = rhs.alarmSchedule else {
          return false
        }

        if lhsSchedule.hour != rhsSchedule.hour {
          return lhsSchedule.hour < rhsSchedule.hour
        }

        if lhsSchedule.minute != rhsSchedule.minute {
          return lhsSchedule.minute < rhsSchedule.minute
        }

        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
      }
      .first
  }

  private func latestTodayRuns(
    for routines: [Routine],
    from runs: [RoutineRun],
    currentDate: Date
  ) -> [UUID: RoutineRun] {
    let startOfDay = calendar.startOfDay(for: currentDate)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
      return [:]
    }

    let routineIDs = Set(routines.map(\.id))
    let todayRuns = runs
      .filter { run in
        routineIDs.contains(run.routineID)
          && run.startedAt >= startOfDay
          && run.startedAt < endOfDay
      }
      .sorted { lhs, rhs in
        if lhs.startedAt != rhs.startedAt {
          return lhs.startedAt > rhs.startedAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
      }

    return todayRuns.reduce(into: [:]) { result, run in
      if result[run.routineID] == nil {
        result[run.routineID] = run
      }
    }
  }

  private func makeStreak(from runs: [RoutineRun], currentDate: Date) -> HomeRoutineStreak {
    let completedDates = Set(
      runs.compactMap { run -> Date? in
        guard let completedAt = run.completedAt,
              !run.endedEarly,
              run.completionRate == 1 else {
          return nil
        }

        return calendar.startOfDay(for: completedAt)
      }
    )

    let completedWeekdays = Set(
      completedDates
        .filter { calendar.isDate($0, equalTo: currentDate, toGranularity: .weekOfYear) }
        .map(weekday(from:))
    )

    return HomeRoutineStreak(
      currentDays: consecutiveCompletedDays(from: completedDates, currentDate: currentDate),
      bestDays: bestStreak(from: completedDates),
      completedWeekdays: completedWeekdays
    )
  }

  private func consecutiveCompletedDays(from completedDates: Set<Date>, currentDate: Date) -> Int {
    let today = calendar.startOfDay(for: currentDate)
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
      return 0
    }

    let startDate: Date
    if completedDates.contains(today) {
      startDate = today
    } else if completedDates.contains(yesterday) {
      startDate = yesterday
    } else {
      return 0
    }

    var count = 0
    var date = startDate

    while completedDates.contains(date) {
      count += 1

      guard let previousDate = calendar.date(byAdding: .day, value: -1, to: date) else {
        break
      }

      date = previousDate
    }

    return count
  }

  private func bestStreak(from completedDates: Set<Date>) -> Int {
    guard !completedDates.isEmpty else {
      return 0
    }

    let sortedDates = completedDates.sorted()
    var best = 0
    var current = 0
    var previousDate: Date?

    for date in sortedDates {
      if let previousDate,
         let nextDate = calendar.date(byAdding: .day, value: 1, to: previousDate),
         calendar.isDate(date, inSameDayAs: nextDate) {
        current += 1
      } else {
        current = 1
      }

      best = max(best, current)
      previousDate = date
    }

    return best
  }

  private func weekday(from date: Date) -> Weekday {
    Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
  }
}
