//
//  RepositoryContractError.swift
//  Moru
//

import Foundation

enum RepositoryContractError: Error, Equatable, LocalizedError {
  case routineRunSnapshotRequired
  case overlappingActiveRoutineWeekdays

  var errorDescription: String? {
    switch self {
    case .routineRunSnapshotRequired:
      return "RoutineRun must include planned step snapshots before it is saved."
    case .overlappingActiveRoutineWeekdays:
      return "Active routines cannot share scheduled weekdays."
    }
  }
}
