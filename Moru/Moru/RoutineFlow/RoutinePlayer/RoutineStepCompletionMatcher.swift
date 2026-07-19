//
//  RoutineStepCompletionMatcher.swift
//  Moru
//

import Foundation

enum RoutineStepCompletionMatch: Equatable {
  case none
  case explicit
  case contextual
  case weak
}

enum RoutineStepCompletionMatcher {
  static func isCompleted(_ transcript: String, for step: RoutineStep) -> Bool {
    match(transcript, for: step) != .none
  }

  static func match(
    _ transcript: String,
    for step: RoutineStep
  ) -> RoutineStepCompletionMatch {
    guard !ConfirmTranscriptMatcher.hasNegativeIntent(transcript) else {
      return .none
    }

    if ConfirmTranscriptMatcher.isExplicitCompletionCommand(transcript) {
      return .explicit
    }

    if isWaterDrinkingCompletion(transcript, for: step) {
      return .contextual
    }

    return ConfirmTranscriptMatcher.isConfirmed(transcript) ? .weak : .none
  }

  private static func isWaterDrinkingCompletion(
    _ transcript: String,
    for step: RoutineStep
  ) -> Bool {
    let stepContext = ConfirmTranscriptMatcher.normalizedTranscript(
      from: "\(step.title) \(step.instruction)"
    )
    let normalizedTranscript = ConfirmTranscriptMatcher.normalizedTranscript(from: transcript)
    let isWaterStep = stepContext.contains("물")
      && (stepContext.contains("마시") || stepContext.contains("한잔"))
    let mentionsWater = normalizedTranscript.contains("물")
    let describesDrinking = normalizedTranscript.contains("마셨")

    return isWaterStep && mentionsWater && describesDrinking
  }
}
