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
  func deleteSnoozedAlarm(id: UUID) throws
  func deleteAllSnoozedAlarms() throws
}

@MainActor
protocol AlarmScheduling: AnyObject {
  var backend: AlarmDeliveryBackend { get }

  func authorizationState() async -> AlarmAuthorizationState
  func requestAuthorization() async throws -> AlarmAuthorizationState
  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String]
  func cancel(identifiers: [String]) async throws
  func snapshot() async throws -> AlarmPlatformSnapshot
}

@MainActor
protocol AlarmScheduleMutating: AnyObject {
  func apply(_ mutation: AlarmScheduleMutation) async throws -> AlarmMutationResult
  func reconcile() async
  func cancelAllForReset() async throws
}
