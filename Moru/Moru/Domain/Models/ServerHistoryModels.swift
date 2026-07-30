//
//  ServerHistoryModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerHistorySummary: Equatable, Sendable {
  let weekly: ServerHistoryWeeklySummary
  let monthlyDays: [ServerHistoryMonthlyDay]
}

nonisolated struct ServerHistoryWeeklySummary: Equatable, Sendable {
  let completionRate: Double
  let completionRateChangePercentagePoints: Int
  let totalDurationSeconds: Int
  let dailyCompletions: [ServerHistoryWeekdayCompletion]
  let routineStats: [ServerHistoryRoutineStat]
}

nonisolated struct ServerHistoryWeekdayCompletion: Equatable, Sendable {
  let weekday: ServerHistoryWeekday
  /// A normalized value in `0...1`, or `nil` when the server has no data.
  let completionRate: Double?
}

nonisolated enum ServerHistoryWeekday:
  String,
  CaseIterable,
  Equatable,
  Hashable,
  Sendable {
  case monday = "MON"
  case tuesday = "TUE"
  case wednesday = "WED"
  case thursday = "THU"
  case friday = "FRI"
  case saturday = "SAT"
  case sunday = "SUN"
}

nonisolated struct ServerHistoryRoutineStat: Equatable, Sendable {
  let routineID: Int64
  let title: String
  /// A normalized value in `0...1`.
  let completionRate: Double
}

nonisolated struct ServerHistoryMonthlyDay: Equatable, Hashable, Sendable {
  let year: Int
  let month: Int
  let day: Int
  /// A normalized value in `0...1`.
  let completionRate: Double
}
