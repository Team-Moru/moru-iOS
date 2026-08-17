//
//  RoutineSyncLoginBackfiller.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineSyncLoginBackfilling: AnyObject {
  func backfillLocalRoutineGroups(
    memberID: Int64,
    at date: Date
  ) throws
}

/// Seeds the account-scoped Outbox from routines that were created before an
/// account session existed. Re-enqueueing an unchanged pending snapshot is
/// intentional: the repository reuses its persisted generation UUID, so a
/// repeated login cannot rotate the request's `Idempotency-Key`.
@MainActor
final class RoutineSyncLoginBackfiller: RoutineSyncLoginBackfilling {
  private let routineRepository: any RoutineRepository
  private let syncRepository: any RoutineSyncRepository

  init(
    routineRepository: any RoutineRepository,
    syncRepository: any RoutineSyncRepository
  ) {
    self.routineRepository = routineRepository
    self.syncRepository = syncRepository
  }

  func backfillLocalRoutineGroups(
    memberID: Int64,
    at date: Date = Date()
  ) throws {
    let routines = try routineRepository.fetchRoutines()
    var didBackfillActiveGroup = false

    for routine in routines {
      guard (routine.sync?.status ?? .localOnly) == .localOnly,
            try syncRepository.binding(
              memberID: memberID,
              entityKind: .routineGroup,
              localEntityID: routine.id
            ) == nil else {
        continue
      }

      _ = try syncRepository.enqueue(
        command: .createRoutineGroup(
          RoutineSyncGroupSnapshot(routine: routine)
        ),
        memberID: memberID,
        at: date
      )
      didBackfillActiveGroup = didBackfillActiveGroup || routine.isActive
    }

    guard didBackfillActiveGroup,
          let selection = try routines.filter(\.isActive).sorted(by: isNewer).first(where: {
            try isServerProjectableGroup($0.id, memberID: memberID)
          }) else {
      return
    }

    _ = try syncRepository.enqueue(
      command: .selectActiveRoutineGroup(selectedGroupLocalID: selection.id),
      memberID: memberID,
      at: date
    )
  }

  private func isNewer(_ lhs: Routine, _ rhs: Routine) -> Bool {
    if lhs.updatedAt == rhs.updatedAt {
      if lhs.createdAt == rhs.createdAt {
        return lhs.id.uuidString < rhs.id.uuidString
      }
      return lhs.createdAt > rhs.createdAt
    }
    return lhs.updatedAt > rhs.updatedAt
  }

  private func isServerProjectableGroup(
    _ groupID: UUID,
    memberID: Int64
  ) throws -> Bool {
    if try syncRepository.binding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: groupID
    ) != nil {
      return true
    }
    return try syncRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: groupID
    ) != nil
  }
}
