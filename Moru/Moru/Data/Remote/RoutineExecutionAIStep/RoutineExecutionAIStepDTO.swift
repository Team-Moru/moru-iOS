//
//  RoutineExecutionAIStepDTO.swift
//  Moru
//

import Foundation

nonisolated struct RoutineExecutionAIStepRequestDTO:
  Encodable,
  Equatable,
  Sendable {
  let routineId: Int64
  let executedDate: String
  let durationSecond: Int?
  let memberInput: String
  let actualWakeTime: String?
}

nonisolated extension RoutineExecutionAIStepRequestDTO:
  CustomStringConvertible,
  CustomDebugStringConvertible {
  var description: String {
    "RoutineExecutionAIStepRequestDTO(body: <redacted>)"
  }

  var debugDescription: String { description }
}

nonisolated struct RoutineExecutionAIStepResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let aiResponse: String?
  let shouldProceed: Bool?
}

nonisolated extension RoutineExecutionAIStepResponseDTO:
  CustomStringConvertible,
  CustomDebugStringConvertible {
  var description: String {
    "RoutineExecutionAIStepResponseDTO(body: <redacted>)"
  }

  var debugDescription: String { description }
}
