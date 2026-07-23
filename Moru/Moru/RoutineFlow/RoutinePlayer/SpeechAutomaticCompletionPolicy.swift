//
//  SpeechAutomaticCompletionPolicy.swift
//  Moru
//

import Foundation

enum SpeechAutomaticCompletionDisposition: Equatable {
  case none
  case immediately
  case afterDelay(Duration)
}

enum SpeechAutomaticCompletionPolicy {
  private static let explicitCompletionDelay: Duration = .milliseconds(400)
  private static let weakCompletionDelay: Duration = .milliseconds(600)

  static func disposition(
    for update: SpeechTranscriptUpdate,
    match: RoutineStepCompletionMatch
  ) -> SpeechAutomaticCompletionDisposition {
    guard match != .none else {
      return .none
    }

    if update.isFinal {
      return .immediately
    }

    switch match {
    case .explicit, .contextual:
      return .afterDelay(explicitCompletionDelay)
    case .weak:
      return .afterDelay(weakCompletionDelay)
    case .none:
      return .none
    }
  }
}
