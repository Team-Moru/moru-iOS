//
//  SwiftDataRoutineRepository.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataRoutineRepository: RoutineRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func fetchRoutines() throws -> [Routine] {
    let descriptor = FetchDescriptor<PersistedRoutine>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRoutine)
  }

  @MainActor
  func fetchActiveRoutines() throws -> [Routine] {
    let descriptor = FetchDescriptor<PersistedRoutine>(
      predicate: #Predicate { $0.isActive },
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRoutine)
  }

  @MainActor
  func routine(id: UUID) throws -> Routine? {
    try persistedRoutine(id: id).map(SwiftDataMapper.makeDomainRoutine)
  }

  @MainActor
  func saveRoutine(_ routine: Routine) throws {
    if let persisted = try persistedRoutine(id: routine.id) {
      SwiftDataMapper.update(persisted, with: routine, in: modelContext)
    } else {
      modelContext.insert(SwiftDataMapper.makePersistedRoutine(from: routine))
    }

    try modelContext.save()
  }

  @MainActor
  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routine(id: id) else {
      return
    }

    routine.isActive = isActive
    routine.updatedAt = Date()
    try saveRoutine(routine)
  }

  @MainActor
  func deleteRoutine(id: UUID) throws {
    guard let persisted = try persistedRoutine(id: id) else {
      return
    }

    modelContext.delete(persisted)
    try modelContext.save()
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
