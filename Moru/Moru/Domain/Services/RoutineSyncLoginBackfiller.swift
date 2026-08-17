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
    for routine in try routineRepository.fetchRoutines() {
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
    }
  }
}
