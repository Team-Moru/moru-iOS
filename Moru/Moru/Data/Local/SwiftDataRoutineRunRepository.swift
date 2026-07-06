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
  func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
    guard limit > 0 else {
      return []
    }

    var descriptor = FetchDescriptor<PersistedRoutineRun>(
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
    )
    descriptor.fetchLimit = limit

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRun)
  }

  @MainActor
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    let descriptor = FetchDescriptor<PersistedRoutineRun>(
      predicate: #Predicate { $0.routineID == routineID },
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRun)
  }

  @MainActor
  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun] {
    let descriptor = FetchDescriptor<PersistedRoutineRun>(
      predicate: #Predicate {
        $0.startedAt >= startDate && $0.startedAt < endDate
      },
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRun)
  }

  @MainActor
  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun] {
    let descriptor = FetchDescriptor<PersistedRoutineRun>(
      predicate: #Predicate {
        $0.routineID == routineID && $0.startedAt >= startDate && $0.startedAt < endDate
      },
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRun)
  }

  @MainActor
  func latestRun(for routineID: UUID) throws -> RoutineRun? {
    var descriptor = FetchDescriptor<PersistedRoutineRun>(
      predicate: #Predicate { $0.routineID == routineID },
      sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    return try modelContext.fetch(descriptor).first.map(SwiftDataMapper.makeDomainRun)
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
    var descriptor = FetchDescriptor<PersistedRoutineRun>(
      predicate: #Predicate { $0.id == id }
    )
    descriptor.fetchLimit = 1

    return try modelContext.fetch(descriptor).first
  }
}
