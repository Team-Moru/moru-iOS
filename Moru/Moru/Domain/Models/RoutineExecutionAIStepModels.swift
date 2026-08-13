//
//  RoutineExecutionAIStepModels.swift
//  Moru
//

import Foundation

nonisolated struct RoutineExecutionAIStepRequest:
  Equatable,
  Sendable {
  let routineID: Int64
  let executedDate: String
  let durationSeconds: Int?
  let memberInput: String
  let actualWakeTime: String?
}

nonisolated extension RoutineExecutionAIStepRequest:
  CustomStringConvertible,
  CustomDebugStringConvertible {
  var description: String {
    "RoutineExecutionAIStepRequest(body: <redacted>)"
  }

  var debugDescription: String { description }
}

nonisolated struct RoutineExecutionAIStepDecision:
  Equatable,
  Sendable {
  let aiResponse: String
  let shouldProceed: Bool
}

nonisolated extension RoutineExecutionAIStepDecision:
  CustomStringConvertible,
  CustomDebugStringConvertible {
  var description: String {
    "RoutineExecutionAIStepDecision(aiResponse: <redacted>, shouldProceed: \(shouldProceed))"
  }

  var debugDescription: String { description }
}
