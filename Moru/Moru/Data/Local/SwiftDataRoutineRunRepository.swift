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
  private let routineSyncRepository: (any RoutineSyncRepository)?
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?

  init(
    modelContext: ModelContext,
    routineSyncRepository: (any RoutineSyncRepository)? = nil,
    signedInMemberProvider: (any SignedInMemberProviding)? = nil
  ) {
    self.modelContext = modelContext
    self.routineSyncRepository = routineSyncRepository
    self.signedInMemberProvider = signedInMemberProvider
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
    try validateRunForPersistence(run)
    do {
      let previous = try persistedRun(id: run.id).map(SwiftDataMapper.makeDomainRun(from:))
      if let persisted = try persistedRun(id: run.id) {
        SwiftDataMapper.update(persisted, with: run, in: modelContext)
      } else {
        modelContext.insert(SwiftDataMapper.makePersistedRun(from: run))
      }

      if let memberID = signedInMemberProvider?.signedInMemberID,
         let routineSyncRepository {
        let previousResults = Dictionary(
          uniqueKeysWithValues: (previous?.results ?? []).map { ($0.id, $0) }
        )
        let runContextChanged = previous?.startedAt != run.startedAt
          || previous?.completedAt != run.completedAt
        for result in run.results {
          guard previousResults[result.id] != result || runContextChanged else {
            continue
          }
          guard try isServerProjectable(
            result: result,
            in: run,
            memberID: memberID,
            repository: routineSyncRepository
          ) else {
            continue
          }
          try routineSyncRepository.stageEnqueue(
            EnqueuedRoutineSyncMutation(
              memberID: memberID,
              command: .saveRoutineExecution(
                RoutineSyncExecutionSnapshot(
                  run: run,
                  result: result,
                  timeZone: .current
                )
              )
            ),
            at: Date()
          )
        }
      }

      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
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

  private func validateRunForPersistence(_ run: RoutineRun) throws {
    guard !run.plannedSteps.isEmpty else {
      throw RepositoryContractError.routineRunSnapshotRequired
    }
  }

  @MainActor
  private func isServerProjectable(
    result: RoutineStepResult,
    in run: RoutineRun,
    memberID: Int64,
    repository: any RoutineSyncRepository
  ) throws -> Bool {
    if let binding = try repository.binding(
      memberID: memberID,
      entityKind: .routine,
      localEntityID: result.stepID
    ), binding.parentEntityKind == .routineGroup,
       binding.parentLocalEntityID == run.routineID {
      return true
    }
    if let add = try repository.mutation(
      memberID: memberID,
      operation: .addRoutine,
      entityKind: .routine,
      localEntityID: result.stepID
    ), case .addRoutine(let groupLocalID, let routine) = try JSONDecoder().decode(
      RoutineSyncCommand.self,
      from: add.payload
    ), groupLocalID == run.routineID, routine.localID == result.stepID {
      return true
    }
    guard let create = try repository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: run.routineID
    ),
    case .createRoutineGroup(let group) = try JSONDecoder().decode(
      RoutineSyncCommand.self,
      from: create.payload
    ) else {
      return false
    }
    return group.routines.contains { $0.localID == result.stepID }
  }
}
