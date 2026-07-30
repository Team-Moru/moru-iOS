//
//  HistoryDTO.swift
//  Moru
//

import Foundation

nonisolated struct HistoryWeeklyResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let completionRate: Int
  let completionRateDiff: Int
  let totalDurationSecond: Int
  let weeklyCompletionRate: [HistoryWeekdayCompletionDTO]
  let routineStats: [HistoryRoutineStatDTO]
}

nonisolated struct HistoryWeekdayCompletionDTO:
  Decodable,
  Equatable,
  Sendable {
  let day: String
  let completionRate: Int?
}

nonisolated struct HistoryRoutineStatDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineId: Int64
  let title: String
  let completionRate: Int
}

nonisolated struct HistoryMonthlyDayDTO:
  Decodable,
  Equatable,
  Sendable {
  let executedDate: String
  let completionRate: Int
}
