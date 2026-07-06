//
//  SwiftDataRoutineRunRepository.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataRoutineRunRepository: RoutineRunRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func fetchRuns() throws -> [RoutineRun] {
    let descriptor = FetchDescriptor<PersistedRoutineRun>(
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRun)
  }

  @MainActor
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    try fetchRuns().filter { $0.routineID == routineID }
  }

  @MainActor
  func run(id: UUID) throws -> RoutineRun? {
    try persistedRun(id: id).map(SwiftDataMapper.makeDomainRun)
  }

  @MainActor
  func saveRun(_ run: RoutineRun) throws {
    if let persisted = try persistedRun(id: run.id) {
      SwiftDataMapper.update(persisted, with: run, in: modelContext)
    } else {
      modelContext.insert(SwiftDataMapper.makePersistedRun(from: run))
    }

    try modelContext.save()
  }

  @MainActor
  func deleteAllRuns() throws {
    let descriptor = FetchDescriptor<PersistedRoutineRun>()
    try modelContext.fetch(descriptor).forEach { modelContext.delete($0) }
    try modelContext.save()
  }

  @MainActor
  private func persistedRun(id: UUID) throws -> PersistedRoutineRun? {
    let descriptor = FetchDescriptor<PersistedRoutineRun>()
    return try modelContext.fetch(descriptor).first { $0.id == id }
  }
}
