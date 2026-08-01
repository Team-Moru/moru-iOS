//
//  TokenRefreshCoordinator.swift
//  Moru
//

import Foundation

nonisolated enum TokenRefreshCoordinatorError: Error, Equatable, Sendable {
  case sessionUnavailable
  case invalidResponse
}

actor TokenRefreshCoordinator: AccountBoundAccessTokenRefreshing {
  private struct RefreshKey: Hashable, Sendable {
    let failedAccessToken: String
    let memberID: Int64
    let sessionID: UUID
  }

  private struct Flight {
    let id: UUID
    let task: Task<AccessTokenRefreshResult, Error>
  }

  private struct TokenRotation {
    let key: RefreshKey
    let result: AccessTokenRefreshResult
  }

  private let authRemoteDataSource: any AuthRemoteDataSource
  private let accountSessionStore: AccountSessionStore
  private var flights: [RefreshKey: Flight] = [:]
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
  ) async throws -> AccessTokenRefreshResult {
    let normalizedToken = failedAccessToken.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    guard !normalizedToken.isEmpty,
          let currentContext = await accountSessionStore
            .currentAuthorizationContext() else {
      throw TokenRefreshCoordinatorError.sessionUnavailable
    }

    return try await refreshAccessToken(
      normalizedToken: normalizedToken,
      authorizationContext: currentContext
    )
  }

  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String,
    matching authorizationContext: AccountAuthorizationContext
  ) async throws -> AccessTokenRefreshResult {
    let normalizedToken = failedAccessToken.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    guard !normalizedToken.isEmpty,
          authorizationContext.accessToken == normalizedToken else {
      throw TokenRefreshCoordinatorError.sessionUnavailable
    }

    return try await refreshAccessToken(
      normalizedToken: normalizedToken,
      authorizationContext: authorizationContext
    )
  }

  private func refreshAccessToken(
    normalizedToken: String,
    authorizationContext: AccountAuthorizationContext
  ) async throws -> AccessTokenRefreshResult {
    guard let currentContext = await accountSessionStore
      .currentAuthorizationContext(),
      currentContext.memberID == authorizationContext.memberID,
      currentContext.sessionID == authorizationContext.sessionID else {
      throw TokenRefreshCoordinatorError.sessionUnavailable
    }

    let key = RefreshKey(
      failedAccessToken: normalizedToken,
      memberID: authorizationContext.memberID,
      sessionID: authorizationContext.sessionID
    )

    if let flight = flights[key] {
      let result = try await flight.task.value
      try await validateRefreshCompletion(
        result,
        for: key
      )
      recordSuccessfulRotation(
        for: key,
        result: result
      )
      return result
    }

    guard currentContext.accessToken == normalizedToken else {
      guard lastSuccessfulRotation?.key == key,
            lastSuccessfulRotation?.result.accessToken
              == currentContext.accessToken else {
        throw TokenRefreshCoordinatorError.sessionUnavailable
      }

      guard let result = lastSuccessfulRotation?.result else {
        throw TokenRefreshCoordinatorError.sessionUnavailable
      }

      return result
    }

    let flightID = UUID()
    let task = makeRefreshTask(
      authorizationContext: authorizationContext
    )
    flights[key] = Flight(id: flightID, task: task)

    do {
      let result = try await task.value
      try await validateRefreshCompletion(
        result,
        for: key
      )
      recordSuccessfulRotation(
        for: key,
        result: result
      )
      clearFlight(for: key, matching: flightID)
      return result
    } catch {
      clearFlight(for: key, matching: flightID)
      throw error
    }
  }

  private func makeRefreshTask(
    authorizationContext: AccountAuthorizationContext
  ) -> Task<AccessTokenRefreshResult, Error> {
    Task {
      let refreshContext: AccountTokenRefreshContext

      do {
        refreshContext = try await accountSessionStore
          .credentialsForTokenRefresh(
            matching: authorizationContext
          )
      } catch {
        if Self.invalidatesSessionBeforeRefreshRequest(error) {
          await accountSessionStore.invalidateAfterTokenRefreshFailure(
            matching: authorizationContext
          )
        }
        throw error
      }

      let previousCredentials = refreshContext.credentials
      let response: TokenReissueResponseDTO

      do {
        response = try await authRemoteDataSource.reissue(
          refreshToken: previousCredentials.refreshToken
        )
      } catch {
        if Self.invalidatesSessionAfterRefreshRequest(error) {
          await accountSessionStore.invalidateAfterTokenRefreshFailure(
            matching: authorizationContext
          )
        }
        throw error
      }

      do {
        let refreshedCredentials = try Self.makeCredentials(
          response: response,
          previousCredentials: previousCredentials
        )

        try await accountSessionStore.replaceCredentialsAfterTokenRefresh(
          refreshedCredentials,
          replacing: refreshContext
        )

        return AccessTokenRefreshResult(
          accessToken: refreshedCredentials.accessToken,
          refreshToken: refreshedCredentials.refreshToken
        )
      } catch {
        // The server may already have rotated the refresh token. Keeping the
        // old local credentials after a malformed success or save failure
        // would create a retry loop with credentials that may no longer work.
        await accountSessionStore.invalidateAfterTokenRefreshFailure(
          matching: authorizationContext
        )
        throw error
      }
    }
  }

  nonisolated private static func invalidatesSessionBeforeRefreshRequest(
    _ error: Error
  ) -> Bool {
    guard let credentialError = error as? CredentialStoreError else {
      return false
    }

    return switch credentialError {
    case .invalidCredentials, .invalidStoredData:
      true
    case .keychain:
      false
    }
  }

  nonisolated private static func invalidatesSessionAfterRefreshRequest(
    _ error: Error
  ) -> Bool {
    if error is AuthRemoteDataSourceError {
      return true
    }

    guard let apiError = error as? APIError else {
      return false
    }

    return switch apiError {
    case .server(let statusCode, _, _):
      statusCode == 401
    case .decoding, .missingResult:
      true
    case .invalidRequest,
         .authenticationRequired,
         .capabilityDisabled,
         .transport,
         .cancelled:
      false
    }
  }

  private func clearFlight(
    for key: RefreshKey,
    matching flightID: UUID
  ) {
    guard flights[key]?.id == flightID else {
      return
    }

    flights[key] = nil
  }

  private func recordSuccessfulRotation(
    for key: RefreshKey,
    result: AccessTokenRefreshResult
  ) {
    lastSuccessfulRotation = TokenRotation(
      key: key,
      result: result
    )
  }

  private func validateRefreshCompletion(
    _ result: AccessTokenRefreshResult,
    for key: RefreshKey
  ) async throws {
    guard let currentContext = await accountSessionStore
      .currentAuthorizationContext(),
      currentContext.memberID == key.memberID,
      currentContext.sessionID == key.sessionID,
      currentContext.accessToken == result.accessToken else {
      throw TokenRefreshCoordinatorError.sessionUnavailable
    }
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
      onboardingCompleted: response.onboardingCompleted,
      provider: previousCredentials.provider,
      providerUserIdentifier: previousCredentials.providerUserIdentifier
    )

    guard credentials.isValid else {
      throw TokenRefreshCoordinatorError.invalidResponse
    }

    return credentials
  }
}
