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
extension HistoryRunStatus {
  var displayText: String {
    switch self {
    case .completed:
      return "완료"
    case .partial:
      return "일부 완료"
    case .endedEarly:
      return "중단됨"
    }
  }
}


struct HistoryOverview: Sendable, Equatable {
  let calendar: Calendar
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
extension HistoryStepResult {
  var displayText: String {
    if isCompleted {
      return "완료"
    }

    return isSkipped ? "건너뜀" : "미완료"
  }
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
