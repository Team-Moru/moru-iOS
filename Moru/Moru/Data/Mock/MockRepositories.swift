//
//  MockRepositories.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

#if DEBUG
import Foundation

final class MockRoutineRepository: RoutineRepository {
  private var routines: [Routine]

  init(routines: [Routine] = []) {
    self.routines = routines
  }

  @MainActor
  func fetchRoutines() throws -> [Routine] {
    routines.sorted { $0.createdAt < $1.createdAt }
  }

  @MainActor
  func fetchActiveRoutines() throws -> [Routine] {
    try fetchRoutines().filter(\.isActive)
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

final class MockRoutineRunRepository: RoutineRunRepository {
  private var runs: [RoutineRun]

  init(runs: [RoutineRun] = []) {
    self.runs = runs
  }

  @MainActor
  func fetchRuns() throws -> [RoutineRun] {
    runs.sorted { $0.startedAt > $1.startedAt }
  }

  @MainActor
  func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
    guard limit > 0 else {
      return []
    }

    return Array(try fetchRuns().prefix(limit))
  }

  @MainActor
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    try fetchRuns().filter { $0.routineID == routineID }
  }

  @MainActor
  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun] {
    try fetchRuns().filter { $0.startedAt >= startDate && $0.startedAt < endDate }
  }

  @MainActor
  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun] {
    try fetchRuns(for: routineID)
      .filter { $0.startedAt >= startDate && $0.startedAt < endDate }
  }

  @MainActor
  func latestRun(for routineID: UUID) throws -> RoutineRun? {
    try fetchRuns(for: routineID).first
  }

  @MainActor
  func run(id: UUID) throws -> RoutineRun? {
    runs.first { $0.id == id }
  }

  @MainActor
  func saveRun(_ run: RoutineRun) throws {
    guard !run.plannedSteps.isEmpty else {
      throw RepositoryContractError.routineRunSnapshotRequired
    }

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

final class MockLocalProfileRepository: LocalProfileRepository {
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

final class MockOnboardingRepository: OnboardingRepository {
  private let localProfileRepository: MockLocalProfileRepository
  private let routineRepository: MockRoutineRepository

  init(
    localProfileRepository: MockLocalProfileRepository,
    routineRepository: MockRoutineRepository
  ) {
    self.localProfileRepository = localProfileRepository
    self.routineRepository = routineRepository
  }

  @MainActor
  func fetchProfile() throws -> LocalProfile? {
    try localProfileRepository.fetchProfile()
  }

  @MainActor
  func saveCompletion(profile: LocalProfile, routine: Routine) throws {
    try localProfileRepository.saveProfile(profile)
    try routineRepository.saveRoutine(routine)
  }
}
#endif
