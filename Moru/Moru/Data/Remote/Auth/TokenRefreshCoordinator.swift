//
//  TokenRefreshCoordinator.swift
//  Moru
//

import Foundation

nonisolated enum TokenRefreshCoordinatorError: Error, Equatable, Sendable {
  case sessionUnavailable
  case invalidResponse
}

actor TokenRefreshCoordinator: AccessTokenRefreshing {
  private struct Flight {
    let id: UUID
    let task: Task<String, Error>
  }

  private struct TokenRotation {
    let previousAccessToken: String
    let refreshedAccessToken: String
  }

  private let authRemoteDataSource: any AuthRemoteDataSource
  private let accountSessionStore: AccountSessionStore
  private var flights: [String: Flight] = [:]
  private var lastSuccessfulRotation: TokenRotation?

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
  }

  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String
  ) async throws -> String {
    let normalizedToken = failedAccessToken.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    guard !normalizedToken.isEmpty,
          let currentAccessToken = accountSessionStore
            .accessTokenProvider.accessToken else {
      throw TokenRefreshCoordinatorError.sessionUnavailable
    }

    if let flight = flights[normalizedToken] {
      let refreshedAccessToken = try await flight.task.value
      recordSuccessfulRotation(
        from: normalizedToken,
        to: refreshedAccessToken
      )
      return refreshedAccessToken
    }

    guard currentAccessToken == normalizedToken else {
      guard lastSuccessfulRotation?.previousAccessToken == normalizedToken,
            lastSuccessfulRotation?.refreshedAccessToken
              == currentAccessToken else {
        throw TokenRefreshCoordinatorError.sessionUnavailable
      }

      return currentAccessToken
    }

    let flightID = UUID()
    let task = makeRefreshTask(failedAccessToken: normalizedToken)
    flights[normalizedToken] = Flight(id: flightID, task: task)

    do {
      let accessToken = try await task.value
      recordSuccessfulRotation(
        from: normalizedToken,
        to: accessToken
      )
      clearFlight(for: normalizedToken, matching: flightID)
      return accessToken
    } catch {
      clearFlight(for: normalizedToken, matching: flightID)
      throw error
    }
  }

  private func makeRefreshTask(
    failedAccessToken: String
  ) -> Task<String, Error> {
    Task {
      do {
        let previousCredentials = try await accountSessionStore
          .credentialsForTokenRefresh(matching: failedAccessToken)
        let response = try await authRemoteDataSource.reissue(
          refreshToken: previousCredentials.refreshToken
        )
        let refreshedCredentials = try Self.makeCredentials(
          response: response,
          previousCredentials: previousCredentials
        )

        try await accountSessionStore.replaceCredentialsAfterTokenRefresh(
          refreshedCredentials,
          replacing: failedAccessToken
        )

        return refreshedCredentials.accessToken
      } catch {
        await accountSessionStore.invalidateAfterTokenRefreshFailure(
          matching: failedAccessToken
        )
        throw error
      }
    }
  }

  private func clearFlight(
    for accessToken: String,
    matching flightID: UUID
  ) {
    guard flights[accessToken]?.id == flightID else {
      return
    }

    flights[accessToken] = nil
  }

  private func recordSuccessfulRotation(
    from previousAccessToken: String,
    to refreshedAccessToken: String
  ) {
    lastSuccessfulRotation = TokenRotation(
      previousAccessToken: previousAccessToken,
      refreshedAccessToken: refreshedAccessToken
    )
  }

  nonisolated private static func makeCredentials(
    response: TokenReissueResponseDTO,
    previousCredentials: AccountCredentials
  ) throws -> AccountCredentials {
    guard response.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
          response.memberId == previousCredentials.memberID else {
      throw TokenRefreshCoordinatorError.invalidResponse
    }

    let credentials = AccountCredentials(
      memberID: response.memberId,
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      onboardingCompleted: response.onboardingCompleted
    )

    guard credentials.isValid else {
      throw TokenRefreshCoordinatorError.invalidResponse
    }

    return credentials
  }
}
