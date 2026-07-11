//
//  SwiftDataOnboardingRepository.swift
//  Moru
//
//  Created by Codex on 7/11/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataOnboardingRepository: OnboardingRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func fetchProfile() throws -> LocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).first.map(SwiftDataMapper.makeDomainProfile)
  }

  @MainActor
  func saveCompletion(profile: LocalProfile, routine: Routine) throws {
    do {
      if let persistedProfile = try persistedProfile(id: profile.id) {
        SwiftDataMapper.update(persistedProfile, with: profile)
      } else {
        modelContext.insert(SwiftDataMapper.makePersistedProfile(from: profile))
      }

      if let persistedRoutine = try persistedRoutine(id: routine.id) {
        SwiftDataMapper.update(persistedRoutine, with: routine, in: modelContext)
      } else {
        modelContext.insert(SwiftDataMapper.makePersistedRoutine(from: routine))
      }

      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  private func persistedProfile(id: UUID) throws -> PersistedLocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>()
    return try modelContext.fetch(descriptor).first { $0.id == id }
  }

  @MainActor
  private func persistedRoutine(id: UUID) throws -> PersistedRoutine? {
    var descriptor = FetchDescriptor<PersistedRoutine>(
      predicate: #Predicate { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }
}
