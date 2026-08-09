//
//  ServerRoutineGroupModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerRoutineGroupCreateSubmission: Equatable, Sendable {
  let title: String
  let description: String?

  /// Raw server values. The caller composes the comma-separated weekdays and time string.
  let alarmDaysRaw: String?
  let alarmTimeRaw: String?

  let weatherNotificationEnabled: Bool
  let routines: [ServerRoutineCreateSubmission]
}

nonisolated struct ServerRoutineCreateSubmission: Equatable, Sendable {
  let title: String
  let type: ServerRoutineCreateType
  let durationSeconds: Int
}

nonisolated enum ServerRoutineCreateType: Equatable, Sendable {
  case check
  case timer
  case input
}

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
