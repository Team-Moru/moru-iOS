//
//  MockRepositories.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

#if DEBUG
import Foundation

nonisolated final class MockRoutineRepository: RoutineRepository {
  private var routines: [Routine]

  init(routines: [Routine] = []) {
    self.routines = routines
  }

  @MainActor
  func fetchRoutines(includeDeleted: Bool = false) throws -> [Routine] {
    guard !includeDeleted else {
      return routines
    }

    return routines.filter { $0.deletedAt == nil }
  }

  @MainActor
  func routine(id: UUID) throws -> Routine? {
    routines.first { $0.id == id }
  }

  @MainActor
  func saveRoutine(_ routine: Routine) throws {
    if let index = routines.firstIndex(where: { $0.id == routine.id }) {
      routines[index] = routine
    } else {
      routines.append(routine)
    }
  }

  @MainActor
  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routine(id: id) else {
      return
    }

    routine.isActive = isActive
    routine.updatedAt = Date()
    try saveRoutine(routine)
  }

  @MainActor
  func deleteRoutine(id: UUID) throws {
    routines.removeAll { $0.id == id }
  }
}

nonisolated final class MockRoutineRunRepository: RoutineRunRepository {
  private var runs: [RoutineRun]

  init(runs: [RoutineRun] = []) {
    self.runs = runs
  }

  @MainActor
  func fetchRuns() throws -> [RoutineRun] {
    runs.sorted { $0.startedAt > $1.startedAt }
  }

  @MainActor
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    try fetchRuns().filter { $0.routineID == routineID }
  }

  @MainActor
  func run(id: UUID) throws -> RoutineRun? {
    runs.first { $0.id == id }
  }

  @MainActor
  func saveRun(_ run: RoutineRun) throws {
    if let index = runs.firstIndex(where: { $0.id == run.id }) {
      runs[index] = run
    } else {
      runs.append(run)
    }
  }

  @MainActor
  func deleteAllRuns() throws {
    runs.removeAll()
  }
}

nonisolated final class MockLocalProfileRepository: LocalProfileRepository {
  private var profile: LocalProfile?

  init(profile: LocalProfile? = nil) {
    self.profile = profile
  }

  @MainActor
  func fetchProfile() throws -> LocalProfile? {
    profile
  }

  @MainActor
  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile {
      return profile
    }

    let profile = LocalProfile()
    self.profile = profile
    return profile
  }

  @MainActor
  func saveProfile(_ profile: LocalProfile) throws {
    self.profile = profile
  }

  @MainActor
  func deleteProfile() throws {
    profile = nil
  }
}
#endif
