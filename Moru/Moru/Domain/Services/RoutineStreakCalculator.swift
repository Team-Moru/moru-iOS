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

struct RoutineStreakCalculator {
  private let calendar: Calendar

  init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  func calculate(from runs: [RoutineRun], asOf currentDate: Date) -> RoutineStreak {
    let completedDates = Set(
      runs.compactMap { run -> Date? in
        guard let completedAt = run.completedAt,
              completedAt <= currentDate,
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

    return RoutineStreak(
      currentDays: currentStreak(from: completedDates, asOf: currentDate),
      bestDays: bestStreak(from: completedDates),
      completedWeekdays: completedWeekdays
    )
  }

  private func currentStreak(from completedDates: Set<Date>, asOf currentDate: Date) -> Int {
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

    var best = 0
    var current = 0
    var previousDate: Date?

    for date in completedDates.sorted() {
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
