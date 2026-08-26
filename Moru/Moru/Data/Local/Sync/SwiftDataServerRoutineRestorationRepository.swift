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

  func localDataState() throws -> ServerRoutineRestorationLocalDataState {
    try provisionalStore.localDataState()
  }

  func persistServerRestoration(
    _ snapshot: ServerRoutineRestorationSnapshot,
    memberID: Int64,
    replacing source: ServerRoutineRestorationSource,
    at date: Date
  ) throws -> Bool {
    do {
      // Recheck the complete marker snapshot in the same main-actor
      // transaction after every remote read. Any user change wins the race.
      guard try localDataState().restorationSource == source else {
        return false
      }

      // Validate every local/remote identity pair before deleting a
      // relationship graph. This stage-only call inserts no durable row until
      // the one save below and avoids asking SwiftData to roll back a deleted
      // cascade for a known binding conflict.
      _ = try syncRepository.stageRecordRemoteIDs(
        snapshot.bindingAssignments,
        memberID: memberID,
        at: date
      )

      switch source {
      case .empty:
        // Clear only an orphan marker. There is no local content to delete.
        try provisionalStore.stageInvalidate()
      case .provisional(let generationID):
        guard try provisionalStore.stageDeleteValidatedProvisionalData(
          generationID: generationID
        ) else {
          modelContext.rollback()
          return false
        }
      }

      modelContext.insert(
        SwiftDataMapper.makePersistedProfile(from: snapshot.profile)
      )
      for routine in snapshot.routines {
        modelContext.insert(
          SwiftDataMapper.makePersistedRoutine(from: routine)
        )
      }
      try modelContext.save()
      return true
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func finalizeProvisionalDataAsEstablished(
    generationID: UUID
  ) throws -> Bool {
    try provisionalStore.finalizeAsEstablished(
      expectedGenerationID: generationID
    )
  }

  private var provisionalStore: SwiftDataProvisionalOnboardingDataStore {
    SwiftDataProvisionalOnboardingDataStore(modelContext: modelContext)
  }
}
