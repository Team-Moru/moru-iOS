//
//  RoutineRepositories.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

@MainActor
protocol RoutineRepository {
  func fetchRoutines(includeDeleted: Bool) throws -> [Routine]
  func routine(id: UUID) throws -> Routine?
  func saveRoutine(_ routine: Routine) throws
  func updateRoutineActivation(id: UUID, isActive: Bool) throws
  func deleteRoutine(id: UUID) throws
}

@MainActor
protocol RoutineRunRepository {
  func fetchRuns() throws -> [RoutineRun]
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun]
  func run(id: UUID) throws -> RoutineRun?
  func saveRun(_ run: RoutineRun) throws
  func deleteAllRuns() throws
}

@MainActor
protocol LocalProfileRepository {
  func fetchProfile() throws -> LocalProfile?
  func loadOrCreateDefaultProfile() throws -> LocalProfile
  func saveProfile(_ profile: LocalProfile) throws
  func deleteProfile() throws
}
