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

    // 키워드가 먼저다. "마쳤어"·"끝냈어" 같은 일반 완료 동사는 어느 단계에서나
    // 같은 뜻이라, 아래 음절 대조가 "마쳤"의 마를 "마시기"로 오해하기 전에 잡는다.
    if ConfirmTranscriptMatcher.isConfirmed(transcript) {
      return .weak
    }

    return describesThisStepsAction(transcript, for: step) ? .contextual : .none
  }

  /// "완료되었으면 말해주세요"에 과거형으로 답하면 한 것이다. 단계마다 동사
  /// 사전을 두는 대신 두 가지만 본다. 받침 ㅆ이 시제를 말하고, 그 동사의 음절이
  /// 단계 제목·안내에 있으면 이 단계의 행동이다. "마셨어"는 물 단계에서 통하고
  /// 스트레칭 단계에서는 통하지 않는다. 활용하며 모음이 바뀐 동사("썼"←쓰,
  /// "봤"←보)는 사전형 모음으로 되돌려 대조한다.
  private static func describesThisStepsAction(
    _ transcript: String,
    for step: RoutineStep
  ) -> Bool {
    let normalizedTranscript = ConfirmTranscriptMatcher.normalizedTranscript(from: transcript)
    let verbSyllables = ConfirmTranscriptMatcher.pastTenseVerbSyllables(in: normalizedTranscript)
      .flatMap(ConfirmTranscriptMatcher.dictionaryFormCandidates)
    guard !verbSyllables.isEmpty else {
      return false
    }

    var stepText = ConfirmTranscriptMatcher.normalizedTranscript(
      from: "\(step.title) \(step.instruction)"
    )
    for phrase in instructionBoilerplate {
      stepText = stepText.replacingOccurrences(of: phrase, with: "")
    }
    let stepSyllables = Set(stepText.compactMap(ConfirmTranscriptMatcher.syllableIgnoringFinal))
    return verbSyllables.contains(where: stepSyllables.contains)
  }

  /// 안내문 상투구. 남겨 두면 "말해주세요"의 말이 "마셨어"의 마와 부딪혀
  /// 아무 단계나 통과시킨다.
  private static let instructionBoilerplate = [
    "말씀해주세요", "말해주세요", "알려주세요", "눌러주세요", "말해줘"
  ]
}
