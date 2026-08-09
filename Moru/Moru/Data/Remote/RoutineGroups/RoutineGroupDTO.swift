//
//  RoutineGroupDTO.swift
//  Moru
//

import Foundation

nonisolated struct RoutineGroupCreateRequestDTO:
  Encodable,
  Equatable,
  Sendable {
  let title: String
  let description: String?
  let alarmDays: String?
  let alarmTime: String?
  let weatherNotificationEnabled: Bool
  let routines: [RoutineGroupRoutineCreateRequestDTO]
}

nonisolated struct RoutineGroupRoutineCreateRequestDTO:
  Encodable,
  Equatable,
  Sendable {
  let title: String
  let type: String
  let durationSecond: Int
}

nonisolated struct RoutineGroupSummaryResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineGroupId: Int64?
  let title: String?
  let isActive: Bool?
  let routineCount: Int?
  let totalDurationSecond: Int?
}

nonisolated struct RoutineGroupDetailResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineGroupId: Int64?
  let title: String?
  let description: String?
  let alarmDays: String?
  let alarmTime: String?
  let weatherNotificationEnabled: Bool?
  let routines: [RoutineGroupRoutineResponseDTO]?
}

nonisolated struct RoutineGroupRoutineResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineId: Int64?
  let title: String?
  let type: String?
  let durationSecond: Int?
  let steps: [RoutineGroupStepResponseDTO]?
}

nonisolated struct RoutineGroupStepResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let stepId: Int64?
  let content: String?
  let orderIndex: Int?
}
