//
//  DefaultOnboardingStatusRemoteService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultOnboardingStatusRemoteService:
  OnboardingStatusRemoteServing {
  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func fetchStatus(
    for identity: AccountSessionIdentity
  ) async throws -> ServerOnboardingStatus {
    guard identity.memberID > 0 else {
      throw OnboardingStatusRemoteError.invalidRequest
    }

    do {
      let data = try await apiClient.requestData(
        OnboardingStatusTarget.status,
        authorizedFor: identity
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()

      let header: OnboardingStatusEnvelopeHeaderDTO
      do {
        header = try JSONDecoder().decode(
          OnboardingStatusEnvelopeHeaderDTO.self,
          from: data
        )
      } catch {
        throw OnboardingStatusRemoteError.invalidResponse
      }

      guard header.isSuccess else {
        throw APIError.server(
          statusCode: 200,
          code: header.code,
          message: header.message
        )
      }

      let envelope: OnboardingStatusEnvelopeDTO
      do {
        envelope = try JSONDecoder().decode(
          OnboardingStatusEnvelopeDTO.self,
          from: data
        )
      } catch {
        throw OnboardingStatusRemoteError.invalidResponse
      }
      guard let result = envelope.result else {
        throw OnboardingStatusRemoteError.invalidResponse
      }

      try _Concurrency.Task<Never, Never>.checkCancellation()
      return ServerOnboardingStatus(
        isCompleted: result.onboardingCompleted
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch is AccountAuthorizationContextError {
      throw OnboardingStatusRemoteError.accountAuthorizationChanged
    }
  }
}
