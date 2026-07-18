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

@Model
final class PersistedScheduledAlarmStartObservation {
  @Attribute(.unique) var id: UUID
  @Attribute(.unique) var occurrenceID: String
  var rootOccurrenceID: String
  var parentOccurrenceID: String?
  var routineID: UUID
  var scheduleID: UUID
  var actionObservedAt: Date
  var scheduledFireAt: Date
  var resetGeneration: UInt64
  var sourceRawValue: String
  var immutableFingerprint: String
  var timeZoneIdentifier: String
  var utcOffsetSeconds: Int
  var localGregorianDayKey: String
  var localGregorianDayOrdinal: Int
  var localMinute: Int
  var receivedAt: Date

  init(
    id: UUID,
    occurrenceID: String,
    rootOccurrenceID: String,
    parentOccurrenceID: String?,
    routineID: UUID,
    scheduleID: UUID,
    actionObservedAt: Date,
    scheduledFireAt: Date,
    resetGeneration: UInt64,
    sourceRawValue: String,
    immutableFingerprint: String,
    timeZoneIdentifier: String,
    utcOffsetSeconds: Int,
    localGregorianDayKey: String,
    localGregorianDayOrdinal: Int,
    localMinute: Int,
    receivedAt: Date
  ) {
    self.id = id
    self.occurrenceID = occurrenceID
    self.rootOccurrenceID = rootOccurrenceID
    self.parentOccurrenceID = parentOccurrenceID
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.actionObservedAt = actionObservedAt
    self.scheduledFireAt = scheduledFireAt
    self.resetGeneration = resetGeneration
    self.sourceRawValue = sourceRawValue
    self.immutableFingerprint = immutableFingerprint
    self.timeZoneIdentifier = timeZoneIdentifier
    self.utcOffsetSeconds = utcOffsetSeconds
    self.localGregorianDayKey = localGregorianDayKey
    self.localGregorianDayOrdinal = localGregorianDayOrdinal
    self.localMinute = localMinute
    self.receivedAt = receivedAt
  }
}

@Model
final class PersistedHomeWeatherSnapshot {
  @Attribute(.unique) var id: UUID
  var conditionRawValue: String
  var temperatureCelsius: Double
  var latitudeE4: Int
  var longitudeE4: Int
  var fetchedAt: Date
  var fetchedTimeZoneIdentifier: String
  var fetchedUTCOffsetSeconds: Int

  init(
    id: UUID,
    conditionRawValue: String,
    temperatureCelsius: Double,
    latitudeE4: Int,
    longitudeE4: Int,
    fetchedAt: Date,
    fetchedTimeZoneIdentifier: String,
    fetchedUTCOffsetSeconds: Int
  ) {
    self.id = id
    self.conditionRawValue = conditionRawValue
    self.temperatureCelsius = temperatureCelsius
    self.latitudeE4 = latitudeE4
    self.longitudeE4 = longitudeE4
    self.fetchedAt = fetchedAt
    self.fetchedTimeZoneIdentifier = fetchedTimeZoneIdentifier
    self.fetchedUTCOffsetSeconds = fetchedUTCOffsetSeconds
  }
}

@Model
final class PersistedLocalSettings {
  @Attribute(.unique) var id: UUID
  @Attribute(.unique) var profileID: UUID
  var voiceMigrationStateRawValue: String
  var voiceMigrationOriginalVoiceID: String?
  var voiceMigrationResolvedVoiceID: String?
  var voiceMigrationUpdatedAt: Date?
  var schemaMigrationMarkerRawValue: String

  init(
    id: UUID,
    profileID: UUID,
    voiceMigrationStateRawValue: String = VoiceMigrationState.unresolved.rawValue,
    voiceMigrationOriginalVoiceID: String? = nil,
    voiceMigrationResolvedVoiceID: String? = nil,
    voiceMigrationUpdatedAt: Date? = nil,
    schemaMigrationMarkerRawValue: String = SchemaMigrationMarker.v2Unresolved.rawValue
  ) {
    self.id = id
    self.profileID = profileID
    self.voiceMigrationStateRawValue = voiceMigrationStateRawValue
    self.voiceMigrationOriginalVoiceID = voiceMigrationOriginalVoiceID
    self.voiceMigrationResolvedVoiceID = voiceMigrationResolvedVoiceID
    self.voiceMigrationUpdatedAt = voiceMigrationUpdatedAt
    self.schemaMigrationMarkerRawValue = schemaMigrationMarkerRawValue
  }
}

@Model
final class PersistedAlarmRootChainState {
  @Attribute(.unique) var id: UUID
  @Attribute(.unique) var rootOccurrenceID: String
  var routineID: UUID
  var scheduleID: UUID
  var resetGeneration: UInt64
  var rootFingerprint: String
  var earliestObservedOccurrenceID: String?
  var earliestObservedAt: Date?
  var latestObservedOccurrenceID: String?
  var latestObservedAt: Date?
  var terminalOccurrenceID: String?
  var terminalAt: Date?
  var stateRawValue: String
  var updatedAt: Date

  init(
    id: UUID,
    rootOccurrenceID: String,
    routineID: UUID,
    scheduleID: UUID,
    resetGeneration: UInt64,
    rootFingerprint: String,
    earliestObservedOccurrenceID: String?,
    earliestObservedAt: Date?,
    latestObservedOccurrenceID: String?,
    latestObservedAt: Date?,
    terminalOccurrenceID: String?,
    terminalAt: Date?,
    stateRawValue: String = AlarmRootChainState.open.rawValue,
    updatedAt: Date
  ) {
    self.id = id
    self.rootOccurrenceID = rootOccurrenceID
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.resetGeneration = resetGeneration
    self.rootFingerprint = rootFingerprint
    self.earliestObservedOccurrenceID = earliestObservedOccurrenceID
    self.earliestObservedAt = earliestObservedAt
    self.latestObservedOccurrenceID = latestObservedOccurrenceID
    self.latestObservedAt = latestObservedAt
    self.terminalOccurrenceID = terminalOccurrenceID
    self.terminalAt = terminalAt
    self.stateRawValue = stateRawValue
    self.updatedAt = updatedAt
  }
}

@Model
final class PersistedAlarmPlatformState {
  @Attribute(.unique) var id: UUID
  @Attribute(.unique) var scheduleID: UUID
  @Attribute(.unique) var routineID: UUID
  var desiredScheduleFingerprint: String
  var platformRequestID: UUID
  var stateRawValue: String
  var updatedAt: Date
  var lastErrorCode: String?

  init(
    id: UUID,
    scheduleID: UUID,
    routineID: UUID,
    desiredScheduleFingerprint: String,
    platformRequestID: UUID,
    stateRawValue: String,
    updatedAt: Date,
    lastErrorCode: String?
  ) {
    self.id = id
    self.scheduleID = scheduleID
    self.routineID = routineID
    self.desiredScheduleFingerprint = desiredScheduleFingerprint
    self.platformRequestID = platformRequestID
    self.stateRawValue = stateRawValue
    self.updatedAt = updatedAt
    self.lastErrorCode = lastErrorCode
  }
}
