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
  private let localProfileRepository: (any LocalProfileRepository)?
  private let syncRepository: any RoutineSyncRepository

  init(
    routineRepository: any RoutineRepository,
    localProfileRepository: (any LocalProfileRepository)? = nil,
    syncRepository: any RoutineSyncRepository
  ) {
    self.routineRepository = routineRepository
    self.localProfileRepository = localProfileRepository
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

    let activeSelection = try routines.filter(\.isActive).sorted(by: isNewer).first(where: {
      try isServerProjectableGroup($0.id, memberID: memberID)
    })
    if didBackfillActiveGroup, let activeSelection {
      _ = try syncRepository.enqueue(
        command: .selectActiveRoutineGroup(selectedGroupLocalID: activeSelection.id),
        memberID: memberID,
        at: date
      )
    }

    // A LocalProfile exists only after local onboarding has been completed.
    // Backfill one stable active/projectable group for local-first login.
    let onboardingCandidate = try routines
      .sorted(by: isNewer)
      .first(where: { routine in
        try isServerProjectableGroup(routine.id, memberID: memberID)
      })
    guard try localProfileRepository?.fetchProfile() != nil,
          let onboardingGroup = activeSelection ?? onboardingCandidate else {
      return
    }
    _ = try syncRepository.enqueue(
      command: .completeOnboarding(groupLocalID: onboardingGroup.id),
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
