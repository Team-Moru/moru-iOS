//
//  SwiftDataMappers.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

enum SwiftDataMapper {
  static func makePersistedRoutine(from routine: Routine) -> PersistedRoutine {
    PersistedRoutine(
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
      deletedAt: routine.deletedAt,
      remoteID: v1Sync(for: routine.sync).remoteID,
      syncStatusRawValue: v1Sync(for: routine.sync).status.rawValue,
      lastSyncedAt: v1Sync(for: routine.sync).lastSyncedAt,
      remoteRevision: v1Sync(for: routine.sync).remoteRevision
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
    persisted.deletedAt = routine.deletedAt
    persisted.remoteID = sync.remoteID
    persisted.syncStatusRawValue = sync.status.rawValue
    persisted.lastSyncedAt = sync.lastSyncedAt
    persisted.remoteRevision = sync.remoteRevision
  }

  static func makeDomainRoutine(from persisted: PersistedRoutine) -> Routine {
    Routine(
      id: persisted.id,
      name: persisted.name,
      summary: persisted.summary,
      goalTags: decodeStringArray(persisted.goalTagsRawValue),
      steps: persisted.steps
        .map(makeDomainRoutineStep)
        .sorted { $0.order < $1.order },
      alarmSchedule: persisted.alarmSchedule.map(makeDomainAlarmSchedule),
      isActive: persisted.isActive,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt,
      deletedAt: persisted.deletedAt,
      sync: makeSyncMetadata(
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

    let sync = v1Sync(for: run.sync)
    persisted.routineID = run.routineID
    persisted.routineName = run.routineName
    persisted.startedAt = run.startedAt
    persisted.completedAt = run.completedAt
    persisted.results = run.results.map(makePersistedStepResult)
    persisted.endedEarly = run.endedEarly
    persisted.remoteID = sync.remoteID
    persisted.syncStatusRawValue = sync.status.rawValue
    persisted.lastSyncedAt = sync.lastSyncedAt
    persisted.remoteRevision = sync.remoteRevision
  }

  static func makeDomainRun(from persisted: PersistedRoutineRun) -> RoutineRun {
    RoutineRun(
      id: persisted.id,
      routineID: persisted.routineID,
      routineName: persisted.routineName,
      startedAt: persisted.startedAt,
      completedAt: persisted.completedAt,
      results: persisted.results.map(makeDomainStepResult),
      endedEarly: persisted.endedEarly,
      sync: makeSyncMetadata(
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

  private static func makeDomainRoutineStep(from persisted: PersistedRoutineStep) -> RoutineStep {
    RoutineStep(
      id: persisted.id,
      type: RoutineStepType.fallback(rawValue: persisted.typeRawValue),
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
  ) -> AlarmSchedule {
    AlarmSchedule(
      id: persisted.id,
      hour: persisted.hour,
      minute: persisted.minute,
      weekdays: decodeIntArray(persisted.weekdaysRawValue).compactMap(Weekday.init(rawValue:)),
      soundName: persisted.soundName,
      isEnabled: persisted.isEnabled,
      includeWeather: persisted.includeWeather,
      includeFortune: persisted.includeFortune
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
  ) -> RoutineStepResult {
    RoutineStepResult(
      id: persisted.id,
      stepID: persisted.stepID,
      stepTitle: persisted.stepTitle,
      stepType: RoutineStepType.fallback(rawValue: persisted.stepTypeRawValue),
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
  ) -> SyncMetadata {
    SyncMetadata(
      remoteID: remoteID,
      status: SyncStatus.fallback(rawValue: syncStatusRawValue),
      lastSyncedAt: lastSyncedAt,
      remoteRevision: remoteRevision
    )
  }

  private static func v1Sync(for sync: SyncMetadata?) -> SyncMetadata {
    SyncMetadata(
      remoteID: nil,
      status: .localOnly,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
  }

  private static func encodeStringArray(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let rawValue = String(data: data, encoding: .utf8) else {
      return "[]"
    }

    return rawValue
  }

  private static func decodeStringArray(_ rawValue: String) -> [String] {
    guard let data = rawValue.data(using: .utf8),
          let values = try? JSONDecoder().decode([String].self, from: data) else {
      return []
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

  private static func decodeIntArray(_ rawValue: String) -> [Int] {
    guard let data = rawValue.data(using: .utf8),
          let values = try? JSONDecoder().decode([Int].self, from: data) else {
      return []
    }

    return values
  }
}
