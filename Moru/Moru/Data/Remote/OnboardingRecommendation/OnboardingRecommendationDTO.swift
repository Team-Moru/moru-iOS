//
//  OnboardingRecommendationDTO.swift
//  Moru
//

import Foundation

nonisolated struct OnboardingRecommendationGroupDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineGroupId: Int64?
  let title: String?
  let description: String?
  let alarmDays: String?
  let alarmTime: String?
  let weatherNotificationEnabled: Bool?
  let routines: [OnboardingRecommendationRoutineDTO]?
}

nonisolated struct OnboardingRecommendationRoutineDTO:
  Decodable,
  Equatable,
  Sendable {
  let routineId: Int64?
  let title: String?
  let type: String?
  let durationSecond: Int?
  let steps: [OnboardingRecommendationNestedStepDTO]?
}

nonisolated struct OnboardingRecommendationNestedStepDTO:
  Decodable,
  Equatable,
  Sendable {
  let stepId: Int64?
  let content: String?
  let orderIndex: Int?
}
