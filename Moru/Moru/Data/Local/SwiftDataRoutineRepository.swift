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
  func fetchRoutines(includeDeleted: Bool = false) throws -> [Routine] {
    let descriptor = FetchDescriptor<PersistedRoutine>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    let routines = try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRoutine)

    guard !includeDeleted else {
      return routines
    }

    return routines.filter { $0.deletedAt == nil }
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
    let descriptor = FetchDescriptor<PersistedRoutine>()
    return try modelContext.fetch(descriptor).first { $0.id == id }
  }
}
