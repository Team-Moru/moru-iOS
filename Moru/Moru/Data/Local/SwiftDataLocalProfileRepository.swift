//
//  SwiftDataLocalProfileRepository.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataLocalProfileRepository: LocalProfileRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func fetchProfile() throws -> LocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    guard let persisted = try modelContext.fetch(descriptor).first else {
      return nil
    }

    let profile = SwiftDataMapper.makeDomainProfile(from: persisted)
    if persisted.selectedVoiceID != profile.selectedVoice.id {
      persisted.selectedVoiceID = profile.selectedVoice.id
      try modelContext.save()
    }

    return profile
  }

  @MainActor
  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile = try fetchProfile() {
      return profile
    }

    let profile = LocalProfile()
    try saveProfile(profile)
    return profile
  }

  @MainActor
  func saveProfile(_ profile: LocalProfile) throws {
    if let persisted = try persistedProfile(id: profile.id) {
      SwiftDataMapper.update(persisted, with: profile)
    } else {
      modelContext.insert(SwiftDataMapper.makePersistedProfile(from: profile))
    }

    try modelContext.save()
  }

  @MainActor
  func deleteProfile() throws {
    let descriptor = FetchDescriptor<PersistedLocalProfile>()
    try modelContext.fetch(descriptor).forEach { modelContext.delete($0) }
    try modelContext.save()
  }

  @MainActor
  private func persistedProfile(id: UUID) throws -> PersistedLocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>()
    return try modelContext.fetch(descriptor).first { $0.id == id }
  }
}
