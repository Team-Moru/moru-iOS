//
//  PersistedModels.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

@Model
final class PersistedRoutine {
  @Attribute(.unique) var id: UUID
  var name: String
  var summary: String
  var goalTagsRawValue: String
  @Relationship(deleteRule: .cascade) var steps: [PersistedRoutineStep]
  @Relationship(deleteRule: .cascade) var alarmSchedule: PersistedAlarmSchedule?
  var isActive: Bool
  var createdAt: Date
  var updatedAt: Date
  var remoteID: String?
  var syncStatusRawValue: String
  var lastSyncedAt: Date?
  var remoteRevision: String?

  init(
    id: UUID,
    name: String,
    summary: String,
    goalTagsRawValue: String,
    steps: [PersistedRoutineStep],
    alarmSchedule: PersistedAlarmSchedule?,
    isActive: Bool,
    createdAt: Date,
    updatedAt: Date,
    remoteID: String?,
    syncStatusRawValue: String,
    lastSyncedAt: Date?,
    remoteRevision: String?
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.goalTagsRawValue = goalTagsRawValue
    self.steps = steps
    self.alarmSchedule = alarmSchedule
    self.isActive = isActive
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.remoteID = remoteID
    self.syncStatusRawValue = syncStatusRawValue
    self.lastSyncedAt = lastSyncedAt
    self.remoteRevision = remoteRevision
  }
}

@Model
final class PersistedRoutineStep {
  @Attribute(.unique) var id: UUID
  var presetItemID: String?
  var typeRawValue: String
  var title: String
  var instruction: String
  var order: Int
  var estimatedSeconds: Int?
  var isRequired: Bool

  init(
    id: UUID,
    presetItemID: String?,
    typeRawValue: String,
    title: String,
    instruction: String,
    order: Int,
    estimatedSeconds: Int?,
    isRequired: Bool
  ) {
    self.id = id
    self.presetItemID = presetItemID
    self.typeRawValue = typeRawValue
    self.title = title
    self.instruction = instruction
    self.order = order
    self.estimatedSeconds = estimatedSeconds
    self.isRequired = isRequired
  }
}

@Model
final class PersistedAlarmSchedule {
  @Attribute(.unique) var id: UUID
  var hour: Int
  var minute: Int
  var weekdaysRawValue: String
  var soundName: String
  var isEnabled: Bool
  var includeWeather: Bool
  var includeFortune: Bool

  init(
    id: UUID,
    hour: Int,
    minute: Int,
    weekdaysRawValue: String,
    soundName: String,
    isEnabled: Bool,
    includeWeather: Bool,
    includeFortune: Bool
  ) {
    self.id = id
    self.hour = hour
    self.minute = minute
    self.weekdaysRawValue = weekdaysRawValue
    self.soundName = soundName
    self.isEnabled = isEnabled
    self.includeWeather = includeWeather
    self.includeFortune = includeFortune
  }
}

@Model
final class PersistedRoutineRun {
  @Attribute(.unique) var id: UUID
  var routineID: UUID
  var routineName: String
  var startedAt: Date
  var completedAt: Date?
  @Relationship(deleteRule: .cascade) var results: [PersistedRoutineStepResult]
  @Relationship(deleteRule: .cascade) var plannedSteps: [PersistedRoutineStepSnapshot]
  var endedEarly: Bool
  var remoteID: String?
  var syncStatusRawValue: String
  var lastSyncedAt: Date?
  var remoteRevision: String?

  init(
    id: UUID,
    routineID: UUID,
    routineName: String,
    startedAt: Date,
    completedAt: Date?,
    results: [PersistedRoutineStepResult],
    plannedSteps: [PersistedRoutineStepSnapshot],
    endedEarly: Bool,
    remoteID: String?,
    syncStatusRawValue: String,
    lastSyncedAt: Date?,
    remoteRevision: String?
  ) {
    self.id = id
    self.routineID = routineID
    self.routineName = routineName
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.results = results
    self.plannedSteps = plannedSteps
    self.endedEarly = endedEarly
    self.remoteID = remoteID
    self.syncStatusRawValue = syncStatusRawValue
    self.lastSyncedAt = lastSyncedAt
    self.remoteRevision = remoteRevision
  }
}

@Model
final class PersistedRoutineStepSnapshot {
  @Attribute(.unique) var id: UUID
  var stepID: UUID
  var stepTitle: String
  var stepTypeRawValue: String
  var stepOrder: Int
  var estimatedSeconds: Int?
  var isRequired: Bool

  init(
    id: UUID,
    stepID: UUID,
    stepTitle: String,
    stepTypeRawValue: String,
    stepOrder: Int,
    estimatedSeconds: Int?,
    isRequired: Bool
  ) {
    self.id = id
    self.stepID = stepID
    self.stepTitle = stepTitle
    self.stepTypeRawValue = stepTypeRawValue
    self.stepOrder = stepOrder
    self.estimatedSeconds = estimatedSeconds
    self.isRequired = isRequired
  }
}

@Model
final class PersistedRoutineStepResult {
  @Attribute(.unique) var id: UUID
  var stepID: UUID
  var stepTitle: String
  var stepTypeRawValue: String
  var completedAt: Date?
  var skipped: Bool
  var inputText: String?
  var transcript: String?
  var durationSeconds: Int?

  init(
    id: UUID,
    stepID: UUID,
    stepTitle: String,
    stepTypeRawValue: String,
    completedAt: Date?,
    skipped: Bool,
    inputText: String?,
    transcript: String?,
    durationSeconds: Int?
  ) {
    self.id = id
    self.stepID = stepID
    self.stepTitle = stepTitle
    self.stepTypeRawValue = stepTypeRawValue
    self.completedAt = completedAt
    self.skipped = skipped
    self.inputText = inputText
    self.transcript = transcript
    self.durationSeconds = durationSeconds
  }
}

@Model
final class PersistedLocalProfile {
  @Attribute(.unique) var id: UUID
  var displayName: String
  var selectedVoiceID: String
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID,
    displayName: String,
    selectedVoiceID: String,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.displayName = displayName
    self.selectedVoiceID = selectedVoiceID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
