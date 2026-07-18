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

  static func isConfirmed(_ transcript: String) -> Bool {
    let normalized = normalizedTranscript(from: transcript)

    guard !normalized.isEmpty else {
      return false
    }

    guard !negativeExpressions.contains(where: normalized.contains) else {
      return false
    }

    if standaloneAffirmations.contains(normalized) {
      return true
    }

    return positiveExpressions.contains(where: normalized.contains)
  }

  private static func normalizedTranscript(from transcript: String) -> String {
    transcript
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .joined()
      .trimmingCharacters(in: .punctuationCharacters)
  }
}
