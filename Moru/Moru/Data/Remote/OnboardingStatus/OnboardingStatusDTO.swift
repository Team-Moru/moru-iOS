//
//  OnboardingStatusDTO.swift
//  Moru
//

import Foundation

nonisolated struct OnboardingStatusEnvelopeHeaderDTO:
  Decodable,
  Equatable,
  Sendable {
  let isSuccess: Bool
  let code: String
  let message: String
}

nonisolated struct OnboardingStatusEnvelopeDTO:
  Decodable,
  Equatable,
  Sendable {
  let isSuccess: Bool
  let code: String
  let message: String
  let result: OnboardingStatusResponseDTO?
}

nonisolated struct OnboardingStatusResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let onboardingCompleted: Bool
}
