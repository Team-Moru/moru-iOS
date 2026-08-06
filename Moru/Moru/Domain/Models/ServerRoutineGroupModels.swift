//
//  ServerRoutineGroupModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerRoutineGroupSummary: Equatable, Sendable {
  let routineGroupID: Int64
  let title: String?
  let isActive: Bool?
  let routineCount: Int?
  let totalDurationSeconds: Int?
}

nonisolated struct ServerRoutineGroupDetail: Equatable, Sendable {
  let routineGroupID: Int64
  let title: String?
  let description: String?

  /// Trimmed server values. They are not interpreted as local schedule data.
  let alarmDaysRaw: String?
  let alarmTimeRaw: String?

  let weatherNotificationEnabled: Bool?

  /// `nil` means that the server omitted the field. `[]` means no routines.
  let routines: [ServerRoutineItem]?
}

nonisolated struct ServerActiveRoutineGroup: Equatable, Sendable {
  let routineGroupID: Int64
  let title: String?
  let totalDurationSeconds: Int?

  /// A normalized value in `0...1`.
  let completionRate: Double?

  /// `nil` means that the server omitted the field. `[]` means no routines.
  let routines: [ServerActiveRoutineItem]?
}

nonisolated struct ServerActiveRoutineItem: Equatable, Sendable {
  let routineID: Int64
  let title: String?
  let isCompleted: Bool?
  let completedTimeSeconds: Int?
}

nonisolated struct ServerTodayRoutineProgress: Equatable, Sendable {
  let completedCount: Int
  let totalCount: Int

  /// A normalized value in `0...1`.
  let completionRate: Double
}

nonisolated struct ServerRoutineGroupActivation: Equatable, Sendable {
  let routineGroupID: Int64
  let isActive: Bool
}

nonisolated struct ServerRoutineItem: Equatable, Sendable {
  let routineID: Int64
  let title: String?
  let type: ServerRoutineItemType?
  let durationSeconds: Int?

  /// `nil` means that the server omitted the field. `[]` means no steps.
  let steps: [ServerRoutineNestedStep]?
}

nonisolated enum ServerRoutineItemType: Equatable, Sendable {
  case check
  case timer
  case input
  case unknown(String)
}

nonisolated struct ServerRoutineNestedStep: Equatable, Sendable {
  let stepID: Int64
  let content: String?
  let orderIndex: Int?
}
