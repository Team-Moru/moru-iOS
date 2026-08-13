//
//  HomeRoutineServerModels.swift
//  Moru
//

import Foundation

nonisolated struct HomeBoundActiveRoutineSnapshot: Equatable, Sendable {
  let localRoutineID: UUID
  let completionRate: Double
  let routines: [HomeBoundRoutineProgress]
  let today: HomeBoundTodayProgress
}

nonisolated struct HomeBoundRoutineProgress: Equatable, Sendable {
  let localStepID: UUID
  let isCompleted: Bool
  let completedTimeSeconds: Int?
}

nonisolated struct HomeBoundTodayProgress: Equatable, Sendable {
  let completedCount: Int
  let totalCount: Int
  let completionRate: Double
}

nonisolated enum HomeRoutineServerFallbackReason: Equatable, Sendable {
  case signedOut
  case remoteUnavailable
  case localActiveMissing
  case localActiveAmbiguous
  case remoteHasNoActiveLocalHasActive
  case activeGroupBindingMissing
  case activeGroupIdentityMismatch
  case activeRoutineBindingMissing
  case activeRoutineIdentityMismatch
  case inconsistentRemoteSnapshot
  case pendingLocalExecution
  case localSyncStateUnavailable
  case serverProjectionDayMismatch
}

nonisolated enum HomeRoutineServerEnrichment: Equatable, Sendable {
  case applied(HomeBoundActiveRoutineSnapshot)
  case noActive
  case fallback(HomeRoutineServerFallbackReason)
}
