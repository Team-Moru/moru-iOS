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

protocol RoutineRepository: AnyObject {
  @MainActor
  func fetchRoutines() throws -> [Routine]
  @MainActor
  func fetchActiveRoutines() throws -> [Routine]
  @MainActor
  func routine(id: UUID) throws -> Routine?
  @MainActor
  func saveRoutine(_ routine: Routine) throws
  @MainActor
  func updateRoutineActivation(id: UUID, isActive: Bool) throws
  @MainActor
  func deleteRoutine(id: UUID) throws
}

protocol RoutineRunRepository: AnyObject {
  @MainActor
  func fetchRuns() throws -> [RoutineRun]
  @MainActor
  func fetchRecentRuns(limit: Int) throws -> [RoutineRun]
  @MainActor
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun]
  @MainActor
  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun]
  @MainActor
  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun]
  @MainActor
  func latestRun(for routineID: UUID) throws -> RoutineRun?
  @MainActor
  func run(id: UUID) throws -> RoutineRun?
  @MainActor
  func saveRun(_ run: RoutineRun) throws
  @MainActor
  func deleteAllRuns() throws
}

protocol LocalProfileRepository: AnyObject {
  @MainActor
  func fetchProfile() throws -> LocalProfile?
  @MainActor
  func loadOrCreateDefaultProfile() throws -> LocalProfile
  @MainActor
  func saveProfile(_ profile: LocalProfile) throws
  @MainActor
  func deleteProfile() throws
}
