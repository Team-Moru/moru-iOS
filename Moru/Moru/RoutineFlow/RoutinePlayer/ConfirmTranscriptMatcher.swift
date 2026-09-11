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
    "못끝",
    "덜했",
    "않았",
    "안됐",
    "못됐",
    "안마셨",
    "못마셨",
    "안마쳤",
    "못마쳤"
  ]

  private static let positiveExpressions = [
    "완료",
    "끝",
    "다했",
    "했어",
    "했어요",
    "했다",
    "했음",
    "마쳤",
    "끝냈",
    "됐어",
    "됐다"
  ]

  private static let standaloneAffirmations = [
    "네",
    "넵",
    "예",
    "응",
    "그래",
    "맞아",
    "좋아",
    "다음",
    "오케이",
    "okay",
    "ok"
  ]
  private static let explicitCompletionCommands = [
    "완료",
    "완료했어",
    "완료했어요",
    "다했어",
    "다했어요",
    "다했습니다",
    "끝",
    "끝났어",
    "끝났어요",
    "끝냈어",
    "끝냈어요",
    "마쳤어",
    "마쳤어요",
    "다음",
    "됐어",
    "됐어요",
    "완료했습니다"
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
  }

  // MARK: - 과거형 판별

  /// 긴 것부터 떼야 "마셨어요"에서 "요"만 떼는 일이 없다.
  private static let sentenceEndings = [
    "습니다", "거든요",
    "네요", "지요", "어요", "거든",
    "죠", "네", "지", "어", "다", "음", "요"
  ]

  /// 받침 ㅆ이지만 시제가 아닌 것. "있어"는 상태, "겠어"는 의지다.
  private static let nonTenseDoubleSiotSyllables: Set<Character> = ["있", "겠"]

  /// 순수 시제 접미사. "먹었"의 었은 동사가 아니라 시제라 대조 후보에서 뺀다.
  /// "마셨"의 셨은 "마시+었"이 줄어든 것이라 어간의 일부로 남긴다.
  private static let pureTenseSuffixSyllables: Set<Character> = ["었", "았", "였", "했"]

  /// 문장 끝을 떼고 남은 마지막 음절에 받침 ㅆ이 있으면 과거형이다. "마셨어",
  /// "씻었어요", "폈다"처럼 동사가 무엇이든 받침이 시제를 말한다.
  ///
  /// 돌려주는 값은 어간으로 보이는 마지막 두 음절이다. 형태소 분석 없이는 어간이
  /// 어디서 시작하는지 알 수 없으므로, 호출자가 단계 텍스트와 대조할 후보로 쓴다.
  /// "안"·"못"이 어디에든 있으면 빈 배열이다 — "안 먹었어"를 놓치는 쪽이
  /// 완료로 잘못 넘기는 쪽보다 싸다.
  static func pastTenseVerbSyllables(in normalizedTranscript: String) -> [Character] {
    guard !normalizedTranscript.contains("안"),
          !normalizedTranscript.contains("못") else {
      return []
    }

    var stem = Substring(normalizedTranscript.precomposedStringWithCanonicalMapping)
    if let ending = sentenceEndings.first(where: { stem.hasSuffix($0) }) {
      stem = stem.dropLast(ending.count)
    }

    guard let last = stem.last,
          hasDoubleSiotFinal(last),
          !nonTenseDoubleSiotSyllables.contains(last) else {
      return []
    }

    var candidates = Array(stem.suffix(3))
    if pureTenseSuffixSyllables.contains(last) {
      candidates.removeLast()
    }
    return Array(candidates.suffix(2))
  }

  /// 받침을 뗀 초성+중성. "마셨"의 마와 "마시기"의 마가 같은 음절이 된다.
  static func syllableIgnoringFinal(_ character: Character) -> Character? {
    guard let scalar = hangulSyllableScalar(character) else {
      return nil
    }

    let withoutFinal = (scalar.value - hangulSyllableBase) / 28 * 28 + hangulSyllableBase
    return Unicode.Scalar(withoutFinal).map(Character.init)
  }

  private static let hangulSyllableBase: UInt32 = 0xAC00
  private static let hangulSyllableRange: ClosedRange<UInt32> = 0xAC00...0xD7A3
  private static let doubleSiotFinalIndex: UInt32 = 20

  private static func hasDoubleSiotFinal(_ character: Character) -> Bool {
    guard let scalar = hangulSyllableScalar(character) else {
      return false
    }

    return (scalar.value - hangulSyllableBase) % 28 == doubleSiotFinalIndex
  }

  private static func hangulSyllableScalar(_ character: Character) -> Unicode.Scalar? {
    let scalars = character.unicodeScalars
    guard scalars.count == 1,
          let scalar = scalars.first,
          hangulSyllableRange.contains(scalar.value) else {
      return nil
    }

    return scalar
  }
}
