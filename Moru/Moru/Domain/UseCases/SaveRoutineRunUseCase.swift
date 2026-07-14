//
//  SaveRoutineRunUseCase.swift
//  Moru
//
//  Created by 김승겸 on 7/12/26.
//

import Foundation

struct SaveRoutineRunRequest: Hashable {
  let runID: UUID
  let routine: Routine
  let startedAt: Date
  let completedAt: Date
  let results: [RoutineStepResult]
  let endedEarly: Bool
}

protocol SaveRoutineRunUseCaseProtocol: AnyObject {
  @MainActor
  @discardableResult
  func execute(_ request: SaveRoutineRunRequest) throws -> RoutineRun
}

nonisolated final class SaveRoutineRunUseCase: SaveRoutineRunUseCaseProtocol {
  private let routineRunRepository: any RoutineRunRepository

  init(routineRunRepository: any RoutineRunRepository) {
    self.routineRunRepository = routineRunRepository
  }

  @MainActor
  @discardableResult
  func execute(_ request: SaveRoutineRunRequest) throws -> RoutineRun {
    let run = RoutineRun(
      id: request.runID,
      routine: request.routine,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    )

    try routineRunRepository.saveRun(run)

    return run
  }
}
