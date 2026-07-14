//
//  HistoryModels.swift
//  Moru
//

import Foundation

enum HistoryRunStatus: Sendable, Equatable {
  case endedEarly
  case completed
  case partial
}

struct HistoryOverview: Sendable, Equatable {
  let recentDays: [HistoryDaySummary]
  let week: HistoryWeekReport
}

struct HistoryDaySummary: Sendable, Equatable {
  let date: Date
  let completedRunCount: Int
  let totalRunCount: Int
  let completionRate: Double
  let runs: [HistoryRun]
}

struct HistoryRun: Sendable, Equatable {
  let id: UUID
  let routineName: String
  let startedAt: Date
  let completedAt: Date?
  let status: HistoryRunStatus
  let completionRate: Double
  let stepResults: [HistoryStepResult]
}

struct HistoryStepResult: Sendable, Equatable {
  let stepID: UUID
  let stepTitle: String
  let isCompleted: Bool
  let isSkipped: Bool
  let transcript: String?
}

struct HistoryWeekReport: Sendable, Equatable {
  let weekStartDate: Date
  let weekEndDate: Date
  let completedRunCount: Int
  let totalRunCount: Int
  let completionRate: Double
  let dailyCompletionRates: [HistoryDailyCompletion]
}

struct HistoryDailyCompletion: Sendable, Equatable {
  let date: Date
  let completionRate: Double
}
