//
//  DailyReportInputAnswerPolicy.swift
//  Moru
//

import Foundation

enum DailyReportInputAnswerPolicy {
  static func answer(for result: RoutineStepResult) -> String? {
    guard result.stepType == .input, result.isCompleted else {
      return nil
    }

    return normalized(result.transcript) ?? normalized(result.inputText)
  }

  static func answer(for routine: ServerHistoryDailyRoutine) -> String? {
    guard routine.type == .input, routine.isCompleted else {
      return nil
    }

    return normalized(routine.memberInput)
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
