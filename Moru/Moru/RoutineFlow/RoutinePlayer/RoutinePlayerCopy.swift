//
//  RoutinePlayerCopy.swift
//  Moru
//

import Foundation

enum RoutinePlayerCopy {
  struct TimerSegment: Equatable {
    let title: String
    let duration: String?
    let durationSeconds: Int?
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
    guard step.type == .timer else {
      return nil
    }

    let instruction = step.instruction.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let seconds = max(step.estimatedSeconds ?? 60, 1)

    return [
      TimerSegment(
        title: instruction.isEmpty ? step.title : instruction,
        duration: durationText(seconds: seconds),
        durationSeconds: seconds
      ),
    ]
  }

  private static func durationText(seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60

    if minutes == 0 {
      return "\(remainingSeconds)초"
    }

    if remainingSeconds == 0 {
      return "\(minutes)분"
    }

    return "\(minutes)분 \(remainingSeconds)초"
  }
}
