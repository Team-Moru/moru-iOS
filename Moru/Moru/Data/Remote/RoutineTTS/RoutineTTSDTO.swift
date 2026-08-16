//
//  RoutineTTSDTO.swift
//  Moru
//

import Foundation

nonisolated struct RoutineTTSResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineId: Int64?
  let title: String?
  let type: String?
  let steps: [RoutineTTSStepResponseDTO]?
}

nonisolated struct RoutineTTSStepResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let stepId: Int64?
  let content: String?
  let ttsIntro: String?
  let ttsStatus: String?
  let s3Url: String?
  let selectionVersion: Int64?
}
