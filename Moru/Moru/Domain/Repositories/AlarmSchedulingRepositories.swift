//
//  AlarmSchedulingRepositories.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation

@MainActor
protocol AlarmPlatformStateRepository: AnyObject {
  func fetchRecords() throws -> [AlarmDeliveryRecord]
  func record(scheduleID: UUID) throws -> AlarmDeliveryRecord?
  func saveRecord(_ record: AlarmDeliveryRecord) throws
  func deleteRecord(scheduleID: UUID) throws
  func deleteAllRecords() throws
  func fetchSnoozedAlarms() throws -> [SnoozedAlarmRecord]
  func saveSnoozedAlarm(_ record: SnoozedAlarmRecord) throws
  func replaceSnoozedAlarm(
    scheduleID: UUID,
    with record: SnoozedAlarmRecord
  ) throws
  func deleteSnoozedAlarm(id: UUID) throws
  func deleteAllSnoozedAlarms() throws
}

@MainActor
protocol AlarmScheduling: AnyObject {
  var backend: AlarmDeliveryBackend { get }

  func authorizationState() async -> AlarmAuthorizationState
  func requestAuthorization() async throws -> AlarmAuthorizationState
  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String]
  func scheduleSnooze(_ request: AlarmSnoozeRequest) async throws -> [String]
  func stop(id: UUID) async throws
  func cancel(identifiers: [String]) async throws
  func snapshot() async throws -> AlarmPlatformSnapshot
}

@MainActor
protocol AlarmRuntimeHandling: AnyObject {
  func resolve(_ envelope: AlarmIngressEnvelope) async -> AlarmIngressResolution
  func startRoutine(from context: AlarmRingContext) async throws
  func snooze(
    context: AlarmRingContext,
    minutes: Int
  ) async throws -> SnoozedAlarmRecord
}

@MainActor
protocol AlarmScheduleMutating: AnyObject {
  func apply(_ mutation: AlarmScheduleMutation) async throws -> AlarmMutationResult
  func reconcile() async
  func cancelAllForReset() async throws
}
