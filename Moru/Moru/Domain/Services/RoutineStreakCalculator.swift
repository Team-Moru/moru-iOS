//
//  RoutineStreakCalculator.swift
//  Moru
//

import Foundation

struct RoutineStreak: Sendable, Equatable {
  let currentDays: Int
  let bestDays: Int
  let completedWeekdays: Set<Weekday>

  nonisolated init(
    currentDays: Int,
    bestDays: Int,
    completedWeekdays: Set<Weekday>
  ) {
    self.currentDays = currentDays
    self.bestDays = bestDays
    self.completedWeekdays = completedWeekdays
  }

  nonisolated static let empty = RoutineStreak(
    currentDays: 0,
    bestDays: 0,
    completedWeekdays: []
  )
}

struct RoutineStreakSchedule: Sendable, Equatable {
  let routineID: UUID
  let weekdays: Set<Weekday>
  let startsAt: Date

  nonisolated init(
    routineID: UUID,
    weekdays: Set<Weekday>,
    startsAt: Date = .distantPast
  ) {
    self.routineID = routineID
    self.weekdays = weekdays
    self.startsAt = startsAt
  }

  nonisolated init?(routine: Routine) {
    guard routine.isActive,
          !routine.steps.isEmpty,
          let alarmSchedule = routine.alarmSchedule,
          alarmSchedule.isEnabled,
          !alarmSchedule.weekdays.isEmpty else {
      return nil
    }

    self.init(
      routineID: routine.id,
      weekdays: Set(alarmSchedule.weekdays),
      startsAt: routine.createdAt
    )
  }
}

struct RoutineStreakCalculator {
  private let calendar: Calendar

  init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  func calculate(
    from runs: [RoutineRun],
    schedules: [RoutineStreakSchedule],
    asOf currentDate: Date
  ) -> RoutineStreak {
    let schedulesByRoutineID = Dictionary(
      schedules.map { ($0.routineID, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    let completedDates = Set(
      runs.compactMap { run -> Date? in
        guard let completedAt = run.completedAt,
              completedAt <= currentDate,
              !run.endedEarly,
              run.completionRate == 1,
              let schedule = schedulesByRoutineID[run.routineID],
              calendar.startOfDay(for: completedAt)
                >= calendar.startOfDay(for: schedule.startsAt),
              schedule.weekdays.contains(weekday(from: completedAt)) else {
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

    guard let firstCompletedDate = completedDates.min() else {
      return .empty
    }

    let scheduledDates = scheduledDates(
      from: firstCompletedDate,
      through: currentDate,
      schedules: schedules
    )

    return RoutineStreak(
      currentDays: currentStreak(
        from: completedDates,
        scheduledDates: scheduledDates,
        asOf: currentDate
      ),
      bestDays: bestStreak(
        from: completedDates,
        scheduledDates: scheduledDates
      ),
      completedWeekdays: completedWeekdays
    )
  }

  private func currentStreak(
    from completedDates: Set<Date>,
    scheduledDates: [Date],
    asOf currentDate: Date
  ) -> Int {
    let today = calendar.startOfDay(for: currentDate)
    var count = 0

    for date in scheduledDates.reversed() {
      // An unfinished occurrence today is still open and must not break the
      // streak earned through the most recent completed scheduled day.
      if calendar.isDate(date, inSameDayAs: today),
         !completedDates.contains(date) {
        continue
      }

      guard completedDates.contains(date) else {
        break
      }

      count += 1
    }

    return count
  }

  private func bestStreak(
    from completedDates: Set<Date>,
    scheduledDates: [Date]
  ) -> Int {
    var best = 0
    var current = 0

    for date in scheduledDates {
      if completedDates.contains(date) {
        current += 1
      } else {
        current = 0
      }

      best = max(best, current)
    }

    return best
  }

  private func scheduledDates(
    from firstDate: Date,
    through currentDate: Date,
    schedules: [RoutineStreakSchedule]
  ) -> [Date] {
    guard !schedules.isEmpty else {
      return []
    }

    let lastDate = calendar.startOfDay(for: currentDate)
    var dates: [Date] = []
    var date = calendar.startOfDay(for: firstDate)

    while date <= lastDate {
      if schedules.contains(where: { schedule in
        date >= calendar.startOfDay(for: schedule.startsAt)
          && schedule.weekdays.contains(weekday(from: date))
      }) {
        dates.append(date)
      }

      guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
        break
      }

      date = nextDate
    }

    return dates
  }

  private func weekday(from date: Date) -> Weekday {
    Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
  }
}
