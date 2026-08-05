//
//  RoutineSuggestionDTO.swift
//  Moru
//

import Foundation

nonisolated struct RoutineGroupAiGenerateRequestDTO:
  Encodable,
  Equatable,
  Sendable {
  let userInput: String
}

nonisolated extension RoutineGroupAiGenerateRequestDTO:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    "RoutineGroupAiGenerateRequestDTO(userInput: <redacted>)"
  }

  var debugDescription: String {
    description
  }
}

nonisolated struct RoutineGroupAiGenerateResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let title: String
  let description: String?
  let routines: [RoutineSuggestionStepDTO]
}

nonisolated struct RoutineSuggestionStepDTO:
  Decodable,
  Equatable,
  Sendable {
  let title: String
  let type: String
  let durationSecond: Int
}
