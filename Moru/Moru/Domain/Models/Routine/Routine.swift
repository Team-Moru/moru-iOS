//
//  Routine.swift
//  Moru
//

import Foundation

enum RoutineStepType: String, Codable, CaseIterable, Hashable {
  case confirm
  case timer
  case input
}

struct RoutineStep: Identifiable, Codable, Hashable {
  var id: UUID
  var presetItemID: String?
  var type: RoutineStepType
  var title: String
  var instruction: String
  var order: Int
  var estimatedSeconds: Int?
  var isRequired: Bool

  init(
    id: UUID = UUID(),
    presetItemID: String? = nil,
    type: RoutineStepType,
    title: String,
    instruction: String = "",
    order: Int,
    estimatedSeconds: Int? = nil,
    isRequired: Bool = true
  ) {
    self.id = id
    self.presetItemID = presetItemID
    self.type = type
    self.title = title
    self.instruction = instruction
    self.order = order
    self.estimatedSeconds = estimatedSeconds
    self.isRequired = isRequired
  }
}

struct Routine: Identifiable, Codable, Hashable {
  var id: UUID
  var name: String
  var summary: String
  var goalTags: [String]
  var steps: [RoutineStep]
  var alarmSchedule: AlarmSchedule?
  var isActive: Bool
  var createdAt: Date
  var updatedAt: Date
  var sync: SyncMetadata?

  init(
    id: UUID = UUID(),
    name: String,
    summary: String = "",
    goalTags: [String] = [],
    steps: [RoutineStep],
    alarmSchedule: AlarmSchedule? = nil,
    isActive: Bool = true,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    sync: SyncMetadata? = .localOnly
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.goalTags = goalTags
    self.steps = steps
    self.alarmSchedule = alarmSchedule
    self.isActive = isActive
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.sync = sync
  }
}
