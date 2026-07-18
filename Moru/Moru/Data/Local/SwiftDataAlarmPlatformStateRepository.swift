//
//  SwiftDataAlarmPlatformStateRepository.swift
//  Moru
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataAlarmPlatformStateRepository: AlarmPlatformStateRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func fetchAll() throws -> [AlarmPlatformSnapshot] {
    let snapshots = try modelContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>())
      .map { try SwiftDataV2Mapper.makeAlarmPlatformSnapshot(from: $0) }

    var scheduleIDs = Set<UUID>()
    for snapshot in snapshots {
      guard scheduleIDs.insert(snapshot.scheduleID).inserted else {
        throw AlarmPlatformStateRepositoryError.duplicateSchedule(snapshot.scheduleID)
      }
    }

    return snapshots.sorted { left, right in
      left.scheduleID.uuidString.lowercased() < right.scheduleID.uuidString.lowercased()
    }
  }

  func fetch(scheduleID: UUID) throws -> AlarmPlatformSnapshot? {
    let matches = try modelContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>())
      .filter { $0.scheduleID == scheduleID }
    guard matches.count <= 1 else {
      throw AlarmPlatformStateRepositoryError.duplicateSchedule(scheduleID)
    }
    return try matches.first.map(SwiftDataV2Mapper.makeAlarmPlatformSnapshot)
  }

  func save(_ snapshot: AlarmPlatformSnapshot) throws {
    let matches = try modelContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>())
      .filter { $0.scheduleID == snapshot.scheduleID }
    guard matches.count <= 1 else {
      throw AlarmPlatformStateRepositoryError.duplicateSchedule(snapshot.scheduleID)
    }

    do {
      if let existing = matches.first {
        guard existing.id == snapshot.id,
              existing.routineID == snapshot.routineID else {
          throw AlarmPlatformStateRepositoryError.duplicateSchedule(snapshot.scheduleID)
        }
        existing.desiredScheduleFingerprint = snapshot.desiredScheduleFingerprint
        existing.platformRequestID = snapshot.platformRequestID
        existing.stateRawValue = snapshot.state.rawValue
        existing.updatedAt = snapshot.updatedAt
        existing.lastErrorCode = snapshot.lastErrorCode
      } else {
        modelContext.insert(
          try SwiftDataV2Mapper.makePersistedAlarmPlatformState(from: snapshot)
        )
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }
}
