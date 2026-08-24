//
//  OnboardingStatusRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol OnboardingStatusRemoteServing: Sendable {
  func fetchStatus(
    for identity: AccountSessionIdentity
  ) async throws -> ServerOnboardingStatus
}

nonisolated enum OnboardingStatusRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
