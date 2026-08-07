//
//  RoutineTTSPreparationScheduling.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineTTSPreparationScheduling: AnyObject {
  /// Called only after the local routine transaction succeeds.
  func routineDidSave(_ routine: Routine)

  /// Local deletion remains successful even if remote cleanup later fails.
  func routineDidDelete(localRoutineID: UUID)

  /// Stops in-flight preparation before account-scoped data is removed.
  func cancelAllPreparations()
}

extension RoutineTTSPreparationScheduling {
  func cancelAllPreparations() {}
}
