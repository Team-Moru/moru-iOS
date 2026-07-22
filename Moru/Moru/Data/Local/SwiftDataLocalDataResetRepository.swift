//
//  SwiftDataLocalDataResetRepository.swift
//  Moru
//
//  Created by Codex on 7/22/26.
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
      try deleteAll(PersistedHomeWeatherSnapshot.self)
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
  private func deleteAll<Model: PersistentModel>(_ modelType: Model.Type) throws {
    let descriptor = FetchDescriptor<Model>()
    try modelContext.fetch(descriptor).forEach(modelContext.delete)
  }
}
