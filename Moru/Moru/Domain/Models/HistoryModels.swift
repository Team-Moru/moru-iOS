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
  let wakeMetrics: HistoryWakeMetrics
  let monthlyHeatmap: HistoryMonthlyHeatmap
}

enum HistoryDestination: Hashable, Sendable {
  case runDetail(UUID)
}

enum HistoryStartTimeRegularity: Sendable, Equatable {
  case veryConsistent
  case consistent
  case variable
  case highlyVariable

  init(averageDeviationMinutes: Int) {
    switch averageDeviationMinutes {
    case ...10:
      self = .veryConsistent
    case ...20:
      self = .consistent
    case ...40:
      self = .variable
    default:
      self = .highlyVariable
    }
  }

  var score: Int {
    switch self {
    case .veryConsistent:
      return 96
    case .consistent:
      return 87
    case .variable:
      return 68
    case .highlyVariable:
      return 42
    }
  }

  var shortText: String {
    switch self {
    case .veryConsistent:
      return "매우 규칙적이에요"
    case .consistent:
      return "꽤 규칙적이에요"
    case .variable:
      return "조금 불규칙해요"
    case .highlyVariable:
      return "많이 불규칙해요"
    }
  }
}

enum HistoryWakeMetrics: Sendable, Equatable {
  case unavailable
  case insufficient(observationCount: Int)
  case calculated(
    observationCount: Int,
    averageWakeMinute: Int,
    averageDeviationMinutes: Int,
    regularity: HistoryStartTimeRegularity
  )

  var observationCount: Int {
    switch self {
    case .unavailable:
      return 0
    case .insufficient(let observationCount),
         .calculated(let observationCount, _, _, _):
      return observationCount
    }
  }
}

struct HistoryMonthlyHeatmap: Sendable, Equatable {
  let monthStartDate: Date
  let days: [HistoryHeatmapDay]
}

struct HistoryHeatmapDay: Identifiable, Sendable, Equatable {
  let id: String
  let date: Date?
  let completionRate: Double?

  var bucket: HistoryHeatmapBucket {
    guard let completionRate else {
      return .noData
    }

    let rate = min(max(completionRate, 0), 1)

    switch rate {
    case 0:
      return .zero
    case ..<0.5:
      return .low
    case ..<1:
      return .high
    default:
      return .complete
    }
  }
}

enum HistoryHeatmapBucket: Sendable, Equatable {
  case noData
  case zero
  case low
  case high
  case complete
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
