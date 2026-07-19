//
//  ConfirmTranscriptMatcher.swift
//  Moru
//

import Foundation

enum ConfirmTranscriptMatcher {
  private static let negativeExpressions = [
    "아직",
    "아니",
    "안했",
    "못했",
    "안끝",
    "덜했",
    "않았"
  ]

  private static let positiveExpressions = [
    "완료",
    "끝",
    "다했",
    "했어요",
    "됐어"
  ]

  private static let standaloneAffirmations = ["네", "응"]
  private static let explicitCompletionCommands = [
    "완료",
    "완료했어",
    "완료했어요",
    "다했어",
    "다했어요",
    "끝",
    "끝났어",
    "끝났어요",
    "됐어",
    "됐어요"
  ]

  static func isConfirmed(_ transcript: String) -> Bool {
    let normalized = normalizedTranscript(from: transcript)

    guard !normalized.isEmpty else {
      return false
    }

    guard !hasNegativeIntent(in: normalized) else {
      return false
    }

    if standaloneAffirmations.contains(normalized) {
      return true
    }

    return positiveExpressions.contains(where: normalized.contains)
  }

  static func isExplicitCompletionCommand(_ transcript: String) -> Bool {
    let normalized = normalizedTranscript(from: transcript)

    guard !normalized.isEmpty else {
      return false
    }

    guard !hasNegativeIntent(in: normalized) else {
      return false
    }

    return explicitCompletionCommands.contains(normalized)
  }

  static func hasNegativeIntent(_ transcript: String) -> Bool {
    hasNegativeIntent(in: normalizedTranscript(from: transcript))
  }

  static func normalizedTranscript(from transcript: String) -> String {
    transcript
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .joined()
      .trimmingCharacters(in: .punctuationCharacters)
  }

  private static func hasNegativeIntent(in normalizedTranscript: String) -> Bool {
    negativeExpressions.contains(where: normalizedTranscript.contains)
      || normalizedTranscript.contains("안마셨")
      || normalizedTranscript.contains("못마셨")
  }
}
