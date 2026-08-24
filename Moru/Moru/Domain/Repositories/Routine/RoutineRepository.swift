//
//  RoutineRepository.swift
//  Moru
//

import Foundation

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
  func saveRoutines(_ routines: [Routine]) throws
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
