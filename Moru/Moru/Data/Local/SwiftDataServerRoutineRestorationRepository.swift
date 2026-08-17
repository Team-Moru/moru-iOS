//
//  SwiftDataServerRoutineRestorationRepository.swift
//  Moru
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataServerRoutineRestorationRepository:
  ServerRoutineRestorationPersisting {
  private let modelContext: ModelContext
  private let syncRepository: any RoutineSyncRepository

  /// `syncRepository` must use this same `ModelContext`; its stage-only API is
  /// what lets local rows and all remote-ID bindings commit atomically.
  init(
    modelContext: ModelContext,
    syncRepository: any RoutineSyncRepository
  ) {
    self.modelContext = modelContext
    self.syncRepository = syncRepository
  }

  func isLocalProfileAndRoutineStoreEmpty() throws -> Bool {
    try hasNoRows(PersistedLocalProfile.self)
      && hasNoRows(PersistedRoutine.self)
  }

  func persistServerRestoration(
    _ snapshot: ServerRoutineRestorationSnapshot,
    memberID: Int64,
    at date: Date
  ) throws -> Bool {
    do {
      // Recheck in the same main-actor transaction after every remote read.
      // A local onboarding completion that won the race must always win.
      guard try isLocalProfileAndRoutineStoreEmpty() else {
        return false
      }

      modelContext.insert(
        SwiftDataMapper.makePersistedProfile(from: snapshot.profile)
      )
      for routine in snapshot.routines {
        modelContext.insert(
          SwiftDataMapper.makePersistedRoutine(from: routine)
        )
      }
      _ = try syncRepository.stageRecordRemoteIDs(
        snapshot.bindingAssignments,
        memberID: memberID,
        at: date
      )

      try modelContext.save()
      return true
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func hasNoRows<Model: PersistentModel>(
    _ modelType: Model.Type
  ) throws -> Bool {
    var descriptor = FetchDescriptor<Model>()
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).isEmpty
  }
}
