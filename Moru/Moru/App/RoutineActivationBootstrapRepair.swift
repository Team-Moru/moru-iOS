//
//  RoutineActivationBootstrapRepair.swift
//  Moru
//
//  Created by Codex on 8/10/26.
//

import Foundation

@MainActor
struct RoutineActivationBootstrapRepairResult: Equatable {
  let winnerID: UUID
  let deactivatedRoutineIDs: [UUID]
  let routines: [Routine]
}

/// Repairs only legacy local data that predates the single-active invariant.
/// It intentionally uses the normal local repository before session restoration,
/// so no account-scoped sync intent can be produced during app launch.
@MainActor
enum RoutineActivationBootstrapRepair {
  static func repairIfNeeded(
    in repository: any RoutineRepository,
    now: Date = Date()
  ) throws -> RoutineActivationBootstrapRepairResult? {
    let routines = try repository.fetchRoutines()
    guard let result = repair(routines: routines, now: now) else {
      return nil
    }

    try repository.saveRoutines(result.routines)
    return result
  }

  static func repair(
    routines: [Routine],
    now: Date = Date()
  ) -> RoutineActivationBootstrapRepairResult? {
    let activeRoutines = routines.filter(\.isActive)
    guard activeRoutines.count > 1,
          let winner = activeRoutines.sorted(by: Self.winsOver).first else {
      return nil
    }

    var repairedRoutines = routines
    var deactivatedRoutineIDs: [UUID] = []

    for index in repairedRoutines.indices where repairedRoutines[index].isActive {
      guard repairedRoutines[index].id != winner.id else {
        continue
      }

      repairedRoutines[index].isActive = false
      repairedRoutines[index].alarmSchedule?.isEnabled = false
      repairedRoutines[index].updatedAt = now
      deactivatedRoutineIDs.append(repairedRoutines[index].id)
    }

    return RoutineActivationBootstrapRepairResult(
      winnerID: winner.id,
      deactivatedRoutineIDs: deactivatedRoutineIDs,
      routines: repairedRoutines
    )
  }

  static func winsOver(_ lhs: Routine, _ rhs: Routine) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
      return lhs.updatedAt > rhs.updatedAt
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt > rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}
