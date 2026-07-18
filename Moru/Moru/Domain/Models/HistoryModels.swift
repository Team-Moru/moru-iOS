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

  nonisolated init(
    calendar: Calendar,
    recentDays: [HistoryDaySummary],
    week: HistoryWeekReport,
    wakeMetrics: HistoryWakeMetrics,
    monthlyHeatmap: HistoryMonthlyHeatmap
  ) {
    self.calendar = calendar
    self.recentDays = recentDays
    self.week = week
    self.wakeMetrics = wakeMetrics
    self.monthlyHeatmap = monthlyHeatmap
  }
}

enum HistoryDestination: Hashable, Sendable {
  case runDetail(UUID)
}

struct HistoryEvidence: Sendable, Equatable {
  let observations: [ScheduledAlarmStartObservationSnapshot]
  let rootChainStates: [AlarmRootChainStateSnapshot]

  static let empty = HistoryEvidence(observations: [], rootChainStates: [])
}

protocol HistoryEvidenceRepository: AnyObject {
  @MainActor
  func fetchEvidence() throws -> HistoryEvidence
}

enum HistoryWakeMetrics: Sendable, Equatable {
  case unavailable
  case insufficient(observationCount: Int)
  case calculated(
    observationCount: Int,
    averageWakeMinute: Int,
    averageDeviationMinutes: Int,
    consistencyScore: Int
  )

  var observationCount: Int {
    switch self {
    case .unavailable:
      0
    case .insufficient(let observationCount),
         .calculated(let observationCount, _, _, _):
      observationCount
    }
  }

  var averageWakeMinute: Int? {
    guard case .calculated(_, let averageWakeMinute, _, _) = self else {
      return nil
    }

    return averageWakeMinute
  }

  var averageDeviationMinutes: Int? {
    guard case .calculated(_, _, let averageDeviationMinutes, _) = self else {
      return nil
    }

    return averageDeviationMinutes
  }

  var consistencyScore: Int? {
    guard case .calculated(_, _, _, let consistencyScore) = self else {
      return nil
    }

    return consistencyScore
  }
}

struct HistoryMonthlyHeatmap: Sendable, Equatable {
  let monthStartDate: Date?
  let days: [HistoryHeatmapDay]

  nonisolated static let empty = HistoryMonthlyHeatmap(monthStartDate: nil, days: [])
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
    case ..<0.25:
      return .low
    case ..<0.5:
      return .medium
    case ..<0.75:
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
  case medium
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
