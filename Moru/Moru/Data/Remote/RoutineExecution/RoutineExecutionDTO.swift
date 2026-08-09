//
//  RoutineExecutionDTO.swift
//  Moru
//

import Foundation

nonisolated struct RoutineExecutionResultRequestDTO:
  Encodable,
  Equatable,
  Sendable
{
  let executedDate: String
  let routineId: Int64
  let durationSecond: Int?
  let isCompleted: Bool
  let memberInput: String?
  let aiResponse: String?
  let actualWakeTime: String?
}

nonisolated extension RoutineExecutionResultRequestDTO:
  CustomDebugStringConvertible,
  CustomStringConvertible
{
  var description: String {
    "RoutineExecutionResultRequestDTO(memberInput: <redacted>, aiResponse: <redacted>)"
  }

  var debugDescription: String {
    description
  }
}

nonisolated struct RoutineExecutionResultResponseDTO:
  Decodable,
  Equatable,
  Sendable
{
  let executedDate: String?
  let executionId: Int64?
  let routineId: Int64?
  let durationSecond: Int?
  let isCompleted: Bool?
}

nonisolated struct RoutineExecutionAIRequestDTO:
  Encodable,
  Equatable,
  Sendable
{
  let routineId: Int64
  let executedDate: String
  let durationSecond: Int?
  let memberInput: String
  let actualWakeTime: String?
}

nonisolated extension RoutineExecutionAIRequestDTO:
  CustomDebugStringConvertible,
  CustomStringConvertible
{
  var description: String {
    "RoutineExecutionAIRequestDTO(memberInput: <redacted>)"
  }

  var debugDescription: String {
    description
  }
}

nonisolated struct RoutineExecutionAIResponseDTO:
  Decodable,
  Equatable,
  Sendable
{
  let aiResponse: String?
  let shouldProceed: Bool?
}
