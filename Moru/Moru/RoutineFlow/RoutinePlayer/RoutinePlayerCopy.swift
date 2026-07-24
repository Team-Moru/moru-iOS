//
//  RoutinePlayerCopy.swift
//  Moru
//

import Foundation

enum RoutinePlayerCopy {
  struct TimerSegment: Equatable {
    let title: String
    let duration: String?
  }

  private static let bedMakingPresetIDs: Set<String> = [
    "ENERGY-01",
    "HEALTH-02",
    "CALM-01",
    "HABIT-01",
  ]

  private static let meditationPresetIDs: Set<String> = [
    "CALM-07",
  ]

  private static let affirmationPresetIDs: Set<String> = [
    "ENERGY-16",
    "CALM-16",
    "HABIT-15",
  ]

  private static let stretchingPresetIDs: Set<String> = [
    "ENERGY-10",
    "HEALTH-08",
    "HABIT-07",
  ]

  static func guide(for step: RoutineStep) -> String {
    if let presetItemID = step.presetItemID {
      if bedMakingPresetIDs.contains(presetItemID) {
        return """
        이불 정리가 끝났나요? 완료됐으면
        말해주세요.
        """
      }

      if meditationPresetIDs.contains(presetItemID) {
        return "눈을 감고 천천히 호흡해봐요."
      }

      if affirmationPresetIDs.contains(presetItemID) {
        return """
        오늘의 다짐을 크게 말해봐요!
        어떤 하루를 만들고 싶나요?
        """
      }
    }

    let instruction = step.instruction.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if !instruction.isEmpty {
      return instruction
    }

    switch step.type {
    case .confirm:
      return "완료되었으면 말해주세요."
    case .timer:
      return "천천히 호흡하며 루틴에 집중해봐요."
    case .input:
      return """
      오늘의 생각을 크게 말해봐요!
      어떤 하루를 만들고 싶나요?
      """
    }
  }

  static func transcriptTitle(for step: RoutineStep) -> String {
    guard let presetItemID = step.presetItemID,
          affirmationPresetIDs.contains(presetItemID) else {
      return "인식한 내용"
    }

    return "오늘의 다짐"
  }

  static func timerSegments(for step: RoutineStep) -> [TimerSegment]? {
    guard let presetItemID = step.presetItemID,
          stretchingPresetIDs.contains(presetItemID) else {
      return nil
    }

    return [
      TimerSegment(title: "목 좌우로 천천히 돌리기", duration: nil),
      TimerSegment(title: "앞뒤로 어깨 돌리기", duration: "30초"),
      TimerSegment(title: "양팔 위로 쭉 뻗기", duration: "30초"),
      TimerSegment(title: "제자리 가볍게 걷기", duration: "1분"),
    ]
  }
}
