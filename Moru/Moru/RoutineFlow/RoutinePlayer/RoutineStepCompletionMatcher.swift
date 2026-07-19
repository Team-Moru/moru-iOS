//
//  RoutineStepCompletionMatcher.swift
//  Moru
//

import Foundation

enum RoutineStepCompletionMatcher {
  static func isCompleted(_ transcript: String, for step: RoutineStep) -> Bool {
    if ConfirmTranscriptMatcher.isConfirmed(transcript)
      || ConfirmTranscriptMatcher.isExplicitCompletionCommand(transcript) {
      return true
    }

    guard !ConfirmTranscriptMatcher.hasNegativeIntent(transcript) else {
      return false
    }

    return isWaterDrinkingCompletion(transcript, for: step)
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
