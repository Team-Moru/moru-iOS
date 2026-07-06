//
//  SwiftDataMappers.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

enum SwiftDataMappingError: Error, Equatable, LocalizedError {
  case malformedStringArray(field: String, rawValue: String)
  case malformedIntArray(field: String, rawValue: String)
  case unknownStepType(field: String, rawValue: String)
  case unknownSyncStatus(rawValue: String)
  case nonLocalSyncMetadata(field: String)
  case invalidWeekdayRawValue(field: String, rawValue: Int)

  var errorDescription: String? {
    switch self {
    case .malformedStringArray(let field, _):
      return "Malformed string array in \(field)."
    case .malformedIntArray(let field, _):
      return "Malformed integer array in \(field)."
    case .unknownStepType(let field, let rawValue):
      return "Unknown routine step type '\(rawValue)' in \(field)."
    case .unknownSyncStatus(let rawValue):
      return "Unknown sync status '\(rawValue)'."
    case .nonLocalSyncMetadata(let field):
      return "Non-local sync metadata is not allowed in v1: \(field)."
    case .invalidWeekdayRawValue(let field, let rawValue):
      return "Invalid weekday raw value '\(rawValue)' in \(field)."
    }
  }
}

enum SwiftDataMapper {
  static func makePersistedRoutine(from routine: Routine) -> PersistedRoutine {
    let sync = v1Sync(for: routine.sync)

    return PersistedRoutine(
      id: routine.id,
      name: routine.name,
      summary: routine.summary,
      goalTagsRawValue: encodeStringArray(routine.goalTags),
      steps: routine.steps
        .sorted { $0.order < $1.order }
        .map(makePersistedRoutineStep),
      alarmSchedule: routine.alarmSchedule.map(makePersistedAlarmSchedule),
      isActive: routine.isActive,
      createdAt: routine.createdAt,
      updatedAt: routine.updatedAt,
      remoteID: sync.remoteID,
      syncStatusRawValue: sync.status.rawValue,
      lastSyncedAt: sync.lastSyncedAt,
      remoteRevision: sync.remoteRevision
    )
  }

  static func update(
    _ persisted: PersistedRoutine,
    with routine: Routine,
    in modelContext: ModelContext
  ) {
    persisted.steps.forEach { modelContext.delete($0) }

    if let alarmSchedule = persisted.alarmSchedule {
      modelContext.delete(alarmSchedule)
    }

    let sync = v1Sync(for: routine.sync)
    persisted.name = routine.name
    persisted.summary = routine.summary
    persisted.goalTagsRawValue = encodeStringArray(routine.goalTags)
    persisted.steps = routine.steps
      .sorted { $0.order < $1.order }
      .map(makePersistedRoutineStep)
    persisted.alarmSchedule = routine.alarmSchedule.map(makePersistedAlarmSchedule)
    persisted.isActive = routine.isActive
    persisted.createdAt = routine.createdAt
    persisted.updatedAt = routine.updatedAt
    persisted.remoteID = sync.remoteID
    persisted.syncStatusRawValue = sync.status.rawValue
    persisted.lastSyncedAt = sync.lastSyncedAt
    persisted.remoteRevision = sync.remoteRevision
  }

  static func makeDomainRoutine(from persisted: PersistedRoutine) throws -> Routine {
    return Routine(
      id: persisted.id,
      name: persisted.name,
      summary: persisted.summary,
      goalTags: try decodeStringArray(
        persisted.goalTagsRawValue,
        field: "PersistedRoutine.goalTagsRawValue"
      ),
      steps: try persisted.steps
        .map(makeDomainRoutineStep)
        .sorted { $0.order < $1.order },
      alarmSchedule: try persisted.alarmSchedule.map(makeDomainAlarmSchedule),
      isActive: persisted.isActive,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt,
      sync: try makeSyncMetadata(
        remoteID: persisted.remoteID,
        syncStatusRawValue: persisted.syncStatusRawValue,
        lastSyncedAt: persisted.lastSyncedAt,
        remoteRevision: persisted.remoteRevision
      )
    )
  }

  static func makePersistedRun(from run: RoutineRun) -> PersistedRoutineRun {
    let sync = v1Sync(for: run.sync)
    return PersistedRoutineRun(
      id: run.id,
      routineID: run.routineID,
      routineName: run.routineName,
      startedAt: run.startedAt,
      completedAt: run.completedAt,
      results: run.results.map(makePersistedStepResult),
      plannedSteps: run.plannedSteps
        .sorted { $0.stepOrder < $1.stepOrder }
        .map(makePersistedStepSnapshot),
      endedEarly: run.endedEarly,
      remoteID: sync.remoteID,
      syncStatusRawValue: sync.status.rawValue,
      lastSyncedAt: sync.lastSyncedAt,
      remoteRevision: sync.remoteRevision
    )
  }

  static func update(
    _ persisted: PersistedRoutineRun,
    with run: RoutineRun,
    in modelContext: ModelContext
  ) {
    persisted.results.forEach { modelContext.delete($0) }
    persisted.plannedSteps.forEach { modelContext.delete($0) }

    let sync = v1Sync(for: run.sync)
    persisted.routineID = run.routineID
    persisted.routineName = run.routineName
    persisted.startedAt = run.startedAt
    persisted.completedAt = run.completedAt
    persisted.results = run.results.map(makePersistedStepResult)
    persisted.plannedSteps = run.plannedSteps
      .sorted { $0.stepOrder < $1.stepOrder }
      .map(makePersistedStepSnapshot)
    persisted.endedEarly = run.endedEarly
    persisted.remoteID = sync.remoteID
    persisted.syncStatusRawValue = sync.status.rawValue
    persisted.lastSyncedAt = sync.lastSyncedAt
    persisted.remoteRevision = sync.remoteRevision
  }

  static func makeDomainRun(from persisted: PersistedRoutineRun) throws -> RoutineRun {
    RoutineRun(
      id: persisted.id,
      routineID: persisted.routineID,
      routineName: persisted.routineName,
      startedAt: persisted.startedAt,
      completedAt: persisted.completedAt,
      results: try persisted.results.map(makeDomainStepResult),
      plannedSteps: try persisted.plannedSteps
        .map(makeDomainStepSnapshot)
        .sorted { $0.stepOrder < $1.stepOrder },
      endedEarly: persisted.endedEarly,
      sync: try makeSyncMetadata(
        remoteID: persisted.remoteID,
        syncStatusRawValue: persisted.syncStatusRawValue,
        lastSyncedAt: persisted.lastSyncedAt,
        remoteRevision: persisted.remoteRevision
      )
    )
  }

  static func makePersistedProfile(from profile: LocalProfile) -> PersistedLocalProfile {
    PersistedLocalProfile(
      id: profile.id,
      displayName: profile.displayName,
      selectedVoiceID: profile.selectedVoice.id,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt
    )
  }

  static func update(_ persisted: PersistedLocalProfile, with profile: LocalProfile) {
    persisted.displayName = profile.displayName
    persisted.selectedVoiceID = profile.selectedVoice.id
    persisted.createdAt = profile.createdAt
    persisted.updatedAt = profile.updatedAt
  }

  static func makeDomainProfile(from persisted: PersistedLocalProfile) -> LocalProfile {
    LocalProfile(
      id: persisted.id,
      displayName: persisted.displayName,
      selectedVoice: VoiceProfile.fallback(id: persisted.selectedVoiceID),
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt
    )
  }

  private static func makePersistedRoutineStep(
    from step: RoutineStep
  ) -> PersistedRoutineStep {
    PersistedRoutineStep(
      id: step.id,
      typeRawValue: step.type.rawValue,
      title: step.title,
      instruction: step.instruction,
      order: step.order,
      estimatedSeconds: step.estimatedSeconds,
      isRequired: step.isRequired
    )
  }

  private static func makeDomainRoutineStep(
    from persisted: PersistedRoutineStep
  ) throws -> RoutineStep {
    let stepType = try makeStepType(
      rawValue: persisted.typeRawValue,
      field: "PersistedRoutineStep.typeRawValue"
    )

    return RoutineStep(
      id: persisted.id,
      type: stepType,
      title: persisted.title,
      instruction: persisted.instruction,
      order: persisted.order,
      estimatedSeconds: persisted.estimatedSeconds,
      isRequired: persisted.isRequired
    )
  }

  private static func makePersistedAlarmSchedule(
    from schedule: AlarmSchedule
  ) -> PersistedAlarmSchedule {
    PersistedAlarmSchedule(
      id: schedule.id,
      hour: schedule.hour,
      minute: schedule.minute,
      weekdaysRawValue: encodeIntArray(schedule.weekdays.map(\.rawValue)),
      soundName: schedule.soundName,
      isEnabled: schedule.isEnabled,
      includeWeather: schedule.includeWeather,
      includeFortune: schedule.includeFortune
    )
  }

  private static func makeDomainAlarmSchedule(
    from persisted: PersistedAlarmSchedule
  ) throws -> AlarmSchedule {
    let weekdaysRawValueField = "PersistedAlarmSchedule.weekdaysRawValue"
    let weekdayRawValues = try decodeIntArray(
      persisted.weekdaysRawValue,
      field: weekdaysRawValueField
    )

    return AlarmSchedule(
      id: persisted.id,
      hour: persisted.hour,
      minute: persisted.minute,
      weekdays: try makeWeekdays(
        rawValues: weekdayRawValues,
        field: weekdaysRawValueField
      ),
      soundName: persisted.soundName,
      isEnabled: persisted.isEnabled,
      includeWeather: persisted.includeWeather,
      includeFortune: persisted.includeFortune
    )
  }

  private static func makePersistedStepSnapshot(
    from snapshot: RoutineStepSnapshot
  ) -> PersistedRoutineStepSnapshot {
    PersistedRoutineStepSnapshot(
      id: snapshot.id,
      stepID: snapshot.stepID,
      stepTitle: snapshot.stepTitle,
      stepTypeRawValue: snapshot.stepType.rawValue,
      stepOrder: snapshot.stepOrder,
      estimatedSeconds: snapshot.estimatedSeconds,
      isRequired: snapshot.isRequired
    )
  }

  private static func makeDomainStepSnapshot(
    from persisted: PersistedRoutineStepSnapshot
  ) throws -> RoutineStepSnapshot {
    let stepType = try makeStepType(
      rawValue: persisted.stepTypeRawValue,
      field: "PersistedRoutineStepSnapshot.stepTypeRawValue"
    )

    return RoutineStepSnapshot(
      id: persisted.id,
      stepID: persisted.stepID,
      stepTitle: persisted.stepTitle,
      stepType: stepType,
      stepOrder: persisted.stepOrder,
      estimatedSeconds: persisted.estimatedSeconds,
      isRequired: persisted.isRequired
    )
  }

  private static func makePersistedStepResult(
    from result: RoutineStepResult
  ) -> PersistedRoutineStepResult {
    PersistedRoutineStepResult(
      id: result.id,
      stepID: result.stepID,
      stepTitle: result.stepTitle,
      stepTypeRawValue: result.stepType.rawValue,
      completedAt: result.completedAt,
      skipped: result.skipped,
      inputText: result.inputText,
      transcript: result.transcript,
      durationSeconds: result.durationSeconds
    )
  }

  private static func makeDomainStepResult(
    from persisted: PersistedRoutineStepResult
  ) throws -> RoutineStepResult {
    let stepType = try makeStepType(
      rawValue: persisted.stepTypeRawValue,
      field: "PersistedRoutineStepResult.stepTypeRawValue"
    )

    return RoutineStepResult(
      id: persisted.id,
      stepID: persisted.stepID,
      stepTitle: persisted.stepTitle,
      stepType: stepType,
      completedAt: persisted.completedAt,
      skipped: persisted.skipped,
      inputText: persisted.inputText,
      transcript: persisted.transcript,
      durationSeconds: persisted.durationSeconds
    )
  }

  private static func makeSyncMetadata(
    remoteID: String?,
    syncStatusRawValue: String,
    lastSyncedAt: Date?,
    remoteRevision: String?
  ) throws -> SyncMetadata {
    guard let syncStatus = SyncStatus(rawValue: syncStatusRawValue) else {
      throw SwiftDataMappingError.unknownSyncStatus(rawValue: syncStatusRawValue)
    }

    guard syncStatus == .localOnly else {
      throw SwiftDataMappingError.unknownSyncStatus(rawValue: syncStatusRawValue)
    }

    if remoteID != nil {
      throw SwiftDataMappingError.nonLocalSyncMetadata(field: "remoteID")
    }

    if lastSyncedAt != nil {
      throw SwiftDataMappingError.nonLocalSyncMetadata(field: "lastSyncedAt")
    }

    if remoteRevision != nil {
      throw SwiftDataMappingError.nonLocalSyncMetadata(field: "remoteRevision")
    }

    return .localOnly
  }

  private static func v1Sync(for sync: SyncMetadata?) -> SyncMetadata {
    return SyncMetadata(
      remoteID: nil,
      status: .localOnly,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
  }

  private static func makeStepType(
    rawValue: String,
    field: String
  ) throws -> RoutineStepType {
    guard let stepType = RoutineStepType(rawValue: rawValue) else {
      throw SwiftDataMappingError.unknownStepType(field: field, rawValue: rawValue)
    }

    return stepType
  }

  private static func makeWeekdays(
    rawValues: [Int],
    field: String
  ) throws -> [Weekday] {
    try rawValues.map { rawValue in
      guard let weekday = Weekday(rawValue: rawValue) else {
        throw SwiftDataMappingError.invalidWeekdayRawValue(
          field: field,
          rawValue: rawValue
        )
      }

      return weekday
    }
  }

  private static func encodeStringArray(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let rawValue = String(data: data, encoding: .utf8) else {
      return "[]"
    }

    return rawValue
  }

  private static func decodeStringArray(
    _ rawValue: String,
    field: String
  ) throws -> [String] {
    guard let data = rawValue.data(using: .utf8),
          let values = try? JSONDecoder().decode([String].self, from: data) else {
      throw SwiftDataMappingError.malformedStringArray(field: field, rawValue: rawValue)
    }

    return values
  }

  private static func encodeIntArray(_ values: [Int]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let rawValue = String(data: data, encoding: .utf8) else {
      return "[]"
    }

    return rawValue
  }

  private static func decodeIntArray(
    _ rawValue: String,
    field: String
  ) throws -> [Int] {
    guard let data = rawValue.data(using: .utf8),
          let values = try? JSONDecoder().decode([Int].self, from: data) else {
      throw SwiftDataMappingError.malformedIntArray(field: field, rawValue: rawValue)
    }

    return values
  }
}
