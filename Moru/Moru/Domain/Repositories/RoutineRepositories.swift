//
//  RoutineRepositories.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum RepositoryContractError: Error, Equatable, LocalizedError {
  case routineRunSnapshotRequired

  var errorDescription: String? {
    switch self {
    case .routineRunSnapshotRequired:
      return "RoutineRun must include planned step snapshots before it is saved."
    }
  }
}

@MainActor
protocol RoutineRepository: AnyObject {
  func fetchRoutines() throws -> [Routine]
  func fetchActiveRoutines() throws -> [Routine]
  func routine(id: UUID) throws -> Routine?
  func saveRoutine(_ routine: Routine) throws
  func updateRoutineActivation(id: UUID, isActive: Bool) throws
  func deleteRoutine(id: UUID) throws
}

@MainActor
protocol RoutineRunRepository: AnyObject {
  func fetchRuns() throws -> [RoutineRun]
  func fetchRecentRuns(limit: Int) throws -> [RoutineRun]
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun]
  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun]
  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun]
  func latestRun(for routineID: UUID) throws -> RoutineRun?
  func run(id: UUID) throws -> RoutineRun?
  func saveRun(_ run: RoutineRun) throws
  func deleteAllRuns() throws
}

@MainActor
protocol LocalProfileRepository: AnyObject {
  func fetchProfile() throws -> LocalProfile?
  func loadOrCreateDefaultProfile() throws -> LocalProfile
  func saveProfile(_ profile: LocalProfile) throws
  func deleteProfile() throws
}
