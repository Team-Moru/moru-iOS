//
//  SwiftDataLocalResetRepository.swift
//  Moru
//

import Foundation
import SwiftData

@MainActor
protocol LocalResetDataRepository: AnyObject {
  func inventoryScheduleIDs() throws -> [UUID]
  func deleteAll() throws
}

nonisolated
enum LocalResetRepositoryError: Error, Equatable, LocalizedError {
  case storage(String)

  var errorDescription: String? {
    switch self {
    case .storage(let reason):
      return "Local reset storage failed: \(reason)."
    }
  }
}

@MainActor
final class SwiftDataLocalResetRepository: LocalResetDataRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func inventoryScheduleIDs() throws -> [UUID] {
    do {
      let routines = try modelContext.fetch(FetchDescriptor<PersistedRoutine>())
      let platformStates = try modelContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>())
      let scheduleIDs = routines.compactMap(\.alarmSchedule?.id) + platformStates.map(\.scheduleID)
      return Self.canonicalScheduleIDs(scheduleIDs)
    } catch {
      throw LocalResetRepositoryError.storage(error.localizedDescription)
    }
  }

  func deleteAll() throws {
    do {
      let routines = try modelContext.fetch(FetchDescriptor<PersistedRoutine>())
      let profiles = try modelContext.fetch(FetchDescriptor<PersistedLocalProfile>())
      let runs = try modelContext.fetch(FetchDescriptor<PersistedRoutineRun>())
      let observations = try modelContext.fetch(
        FetchDescriptor<PersistedScheduledAlarmStartObservation>()
      )
      let weatherSnapshots = try modelContext.fetch(
        FetchDescriptor<PersistedHomeWeatherSnapshot>()
      )
      let settings = try modelContext.fetch(FetchDescriptor<PersistedLocalSettings>())
      let rootChainStates = try modelContext.fetch(FetchDescriptor<PersistedAlarmRootChainState>())
      let platformStates = try modelContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>())

      routines.forEach { modelContext.delete($0) }
      profiles.forEach { modelContext.delete($0) }
      runs.forEach { modelContext.delete($0) }
      observations.forEach { modelContext.delete($0) }
      weatherSnapshots.forEach { modelContext.delete($0) }
      settings.forEach { modelContext.delete($0) }
      rootChainStates.forEach { modelContext.delete($0) }
      platformStates.forEach { modelContext.delete($0) }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw LocalResetRepositoryError.storage(error.localizedDescription)
    }
  }

  private static func canonicalScheduleIDs(_ scheduleIDs: [UUID]) -> [UUID] {
    Array(Set(scheduleIDs)).sorted { left, right in
      left.uuidString.lowercased().utf8.lexicographicallyPrecedes(
        right.uuidString.lowercased().utf8
      )
    }
  }
}
