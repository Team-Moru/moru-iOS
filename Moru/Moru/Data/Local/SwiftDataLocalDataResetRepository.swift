//
//  SwiftDataLocalDataResetRepository.swift
//  Moru
//
//  Created by Codex on 7/21/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataLocalDataResetRepository: LocalDataResetRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func resetToFreshInstallState() throws {
    do {
      try deleteAll(PersistedRoutineRun.self)
      try deleteAll(PersistedRoutine.self)
      try deleteAll(PersistedLocalProfile.self)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  private func deleteAll<T: PersistentModel>(_ modelType: T.Type) throws {
    let descriptor = FetchDescriptor<T>()
    try modelContext.fetch(descriptor).forEach { modelContext.delete($0) }
  }
}
