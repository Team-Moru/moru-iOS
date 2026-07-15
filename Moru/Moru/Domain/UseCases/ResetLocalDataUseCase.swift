//
//  ResetLocalDataUseCase.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import Foundation

@MainActor
struct ResetLocalDataUseCase {
  private let routineRepository: any RoutineRepository
  private let routineRunRepository: any RoutineRunRepository
  private let localProfileRepository: any LocalProfileRepository

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
  }

  func reset() throws {
    let routines = try routineRepository.fetchRoutines()
    for routine in routines {
      try routineRepository.deleteRoutine(id: routine.id)
    }

    try routineRunRepository.deleteAllRuns()
    try localProfileRepository.deleteProfile()
  }
}
