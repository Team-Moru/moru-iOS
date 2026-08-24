//
//  SwiftDataAlarmPlatformStateRepository.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation
import SwiftData

enum AlarmPlatformStateMappingError: Error, Equatable {
  case malformedValue(field: String)
  case unknownBackend(String)
  case unknownDeliveryState(String)
  case invalidWeekday(Int)
}

nonisolated final class SwiftDataAlarmPlatformStateRepository:
  AlarmPlatformStateRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func fetchRecords() throws -> [AlarmDeliveryRecord] {
    let descriptor = FetchDescriptor<PersistedAlarmPlatformState>(
      sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
    )
    return try modelContext.fetch(descriptor).map(makeDomainRecord)
  }

  @MainActor
  func record(scheduleID: UUID) throws -> AlarmDeliveryRecord? {
    try persistedRecord(scheduleID: scheduleID).map(makeDomainRecord)
  }

  @MainActor
  func saveRecord(_ record: AlarmDeliveryRecord) throws {
    do {
      if let persisted = try persistedRecord(scheduleID: record.scheduleID) {
        update(persisted, with: record)
      } else {
        modelContext.insert(makePersistedRecord(record))
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  func deleteRecord(scheduleID: UUID) throws {
    guard let persisted = try persistedRecord(scheduleID: scheduleID) else {
      return
    }
    modelContext.delete(persisted)
    try saveOrRollback()
  }

  @MainActor
  func deleteAllRecords() throws {
    try deleteAll(PersistedAlarmPlatformState.self)
  }

  @MainActor
  func fetchSnoozedAlarms() throws -> [SnoozedAlarmRecord] {
    let descriptor = FetchDescriptor<PersistedSnoozedAlarm>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    return try modelContext.fetch(descriptor).map(makeDomainSnoozedAlarm)
  }

  @MainActor
  func saveSnoozedAlarm(_ record: SnoozedAlarmRecord) throws {
    do {
      if let persisted = try persistedSnoozedAlarm(id: record.id) {
        update(persisted, with: record)
      } else {
        modelContext.insert(makePersistedSnoozedAlarm(record))
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  func replaceSnoozedAlarm(
    scheduleID: UUID,
    with record: SnoozedAlarmRecord
  ) throws {
    do {
      let descriptor = FetchDescriptor<PersistedSnoozedAlarm>(
        predicate: #Predicate { $0.scheduleID == scheduleID }
      )
      try modelContext.fetch(descriptor)
        .filter { $0.id != record.id }
        .forEach(modelContext.delete)

      if let persisted = try persistedSnoozedAlarm(id: record.id) {
        update(persisted, with: record)
      } else {
        modelContext.insert(makePersistedSnoozedAlarm(record))
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  func deleteSnoozedAlarm(id: UUID) throws {
    guard let persisted = try persistedSnoozedAlarm(id: id) else {
      return
    }
    modelContext.delete(persisted)
    try saveOrRollback()
  }

  @MainActor
  func deleteAllSnoozedAlarms() throws {
    try deleteAll(PersistedSnoozedAlarm.self)
  }

  @MainActor
  private func persistedRecord(
    scheduleID: UUID
  ) throws -> PersistedAlarmPlatformState? {
    var descriptor = FetchDescriptor<PersistedAlarmPlatformState>(
      predicate: #Predicate { $0.scheduleID == scheduleID }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  @MainActor
  private func persistedSnoozedAlarm(id: UUID) throws -> PersistedSnoozedAlarm? {
    var descriptor = FetchDescriptor<PersistedSnoozedAlarm>(
      predicate: #Predicate { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  @MainActor
  private func makePersistedRecord(
    _ record: AlarmDeliveryRecord
  ) -> PersistedAlarmPlatformState {
    PersistedAlarmPlatformState(
      scheduleID: record.scheduleID,
      routineID: record.routineID,
      routineName: record.request.routineName,
      hour: record.request.hour,
      minute: record.request.minute,
      weekdaysRawValue: encode(record.request.weekdays.map(\.rawValue)),
      soundName: record.request.soundName,
      fingerprint: record.request.fingerprint,
      backendRawValue: record.backend?.rawValue,
      deliveryStateRawValue: record.state.rawValue,
      platformIdentifiersRawValue: encode(record.platformIdentifiers),
      lastErrorMessage: record.lastErrorMessage,
      updatedAt: record.updatedAt
    )
  }

  @MainActor
  private func update(
    _ persisted: PersistedAlarmPlatformState,
    with record: AlarmDeliveryRecord
  ) {
    persisted.routineID = record.routineID
    persisted.routineName = record.request.routineName
    persisted.hour = record.request.hour
    persisted.minute = record.request.minute
    persisted.weekdaysRawValue = encode(record.request.weekdays.map(\.rawValue))
    persisted.soundName = record.request.soundName
    persisted.fingerprint = record.request.fingerprint
    persisted.backendRawValue = record.backend?.rawValue
    persisted.deliveryStateRawValue = record.state.rawValue
    persisted.platformIdentifiersRawValue = encode(record.platformIdentifiers)
    persisted.lastErrorMessage = record.lastErrorMessage
    persisted.updatedAt = record.updatedAt
  }

  @MainActor
  private func makeDomainRecord(
    _ persisted: PersistedAlarmPlatformState
  ) throws -> AlarmDeliveryRecord {
    let weekdayValues: [Int] = try decode(
      persisted.weekdaysRawValue,
      field: "PersistedAlarmPlatformState.weekdaysRawValue"
    )
    let weekdays = try weekdayValues.map { rawValue in
      guard let weekday = Weekday(rawValue: rawValue) else {
        throw AlarmPlatformStateMappingError.invalidWeekday(rawValue)
      }
      return weekday
    }
    let backend: AlarmDeliveryBackend?
    if let rawValue = persisted.backendRawValue {
      guard let value = AlarmDeliveryBackend(rawValue: rawValue) else {
        throw AlarmPlatformStateMappingError.unknownBackend(rawValue)
      }
      backend = value
    } else {
      backend = nil
    }
    guard let state = AlarmDeliveryState(
      rawValue: persisted.deliveryStateRawValue
    ) else {
      throw AlarmPlatformStateMappingError.unknownDeliveryState(
        persisted.deliveryStateRawValue
      )
    }
    let identifiers: [String] = try decode(
      persisted.platformIdentifiersRawValue,
      field: "PersistedAlarmPlatformState.platformIdentifiersRawValue"
    )
    return AlarmDeliveryRecord(
      request: AlarmScheduleRequest(
        routineID: persisted.routineID,
        scheduleID: persisted.scheduleID,
        routineName: persisted.routineName,
        hour: persisted.hour,
        minute: persisted.minute,
        weekdays: weekdays,
        soundName: persisted.soundName,
        fingerprint: persisted.fingerprint
      ),
      backend: backend,
      state: state,
      platformIdentifiers: identifiers,
      lastErrorMessage: persisted.lastErrorMessage,
      updatedAt: persisted.updatedAt
    )
  }

  @MainActor
  private func makePersistedSnoozedAlarm(
    _ record: SnoozedAlarmRecord
  ) -> PersistedSnoozedAlarm {
    PersistedSnoozedAlarm(
      id: record.id,
      scheduleID: record.scheduleID,
      routineID: record.routineID,
      fireDate: record.fireDate,
      backendRawValue: record.backend.rawValue,
      platformIdentifiersRawValue: encode(record.platformIdentifiers),
      createdAt: record.createdAt
    )
  }

  @MainActor
  private func update(
    _ persisted: PersistedSnoozedAlarm,
    with record: SnoozedAlarmRecord
  ) {
    persisted.scheduleID = record.scheduleID
    persisted.routineID = record.routineID
    persisted.fireDate = record.fireDate
    persisted.backendRawValue = record.backend.rawValue
    persisted.platformIdentifiersRawValue = encode(record.platformIdentifiers)
    persisted.createdAt = record.createdAt
  }

  @MainActor
  private func makeDomainSnoozedAlarm(
    _ persisted: PersistedSnoozedAlarm
  ) throws -> SnoozedAlarmRecord {
    guard let backend = AlarmDeliveryBackend(
      rawValue: persisted.backendRawValue
    ) else {
      throw AlarmPlatformStateMappingError.unknownBackend(
        persisted.backendRawValue
      )
    }
    let identifiers: [String] = try decode(
      persisted.platformIdentifiersRawValue,
      field: "PersistedSnoozedAlarm.platformIdentifiersRawValue"
    )
    return SnoozedAlarmRecord(
      id: persisted.id,
      scheduleID: persisted.scheduleID,
      routineID: persisted.routineID,
      fireDate: persisted.fireDate,
      backend: backend,
      platformIdentifiers: identifiers,
      createdAt: persisted.createdAt
    )
  }

  @MainActor
  private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
    do {
      try modelContext.fetch(FetchDescriptor<Model>()).forEach(modelContext.delete)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  private func saveOrRollback() throws {
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func encode<Value: Encodable>(_ value: Value) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let string = String(data: data, encoding: .utf8) else {
      return "[]"
    }
    return string
  }

  private func decode<Value: Decodable>(
    _ rawValue: String,
    field: String
  ) throws -> Value {
    guard let data = rawValue.data(using: .utf8),
          let value = try? JSONDecoder().decode(Value.self, from: data) else {
      throw AlarmPlatformStateMappingError.malformedValue(field: field)
    }
    return value
  }
}
