//
//  OnboardingTrialRoutineStepLimit.swift
//  Moru
//

enum OnboardingTrialRoutineStepLimit {
  static let minimum = 1
  static let maximum = 2

  static func normalized(_ routine: Routine) -> Routine {
    var normalizedRoutine = routine
    normalizedRoutine.steps = routine.steps
      .sorted { $0.order < $1.order }
      .prefix(maximum)
      .enumerated()
      .map { index, step in
        var normalizedStep = step
        normalizedStep.order = index
        return normalizedStep
      }
    return normalizedRoutine
  }
}
