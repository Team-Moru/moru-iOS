//
//  SocialLoginCoordinator.swift
//  Moru
//

import Foundation

nonisolated struct SocialAuthorization: Equatable, Sendable {
  let provider: AuthProvider
  let token: String
  let authorizationCode: String?
  let rawNonce: String?
  let providerUserIdentifier: String?

  init(
    provider: AuthProvider,
    token: String,
    authorizationCode: String? = nil,
    rawNonce: String? = nil,
    providerUserIdentifier: String? = nil
  ) {
    self.provider = provider
    self.token = token
    self.authorizationCode = authorizationCode
    self.rawNonce = rawNonce
    self.providerUserIdentifier = providerUserIdentifier
  }
}
nonisolated extension SocialAuthorization:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    """
    SocialAuthorization(\
    provider: \(provider.serverValue), \
    token: <redacted>, \
    authorizationCode: \(authorizationCode == nil ? "nil" : "<redacted>"), \
    rawNonce: \(rawNonce == nil ? "nil" : "<redacted>"), \
    providerUserIdentifier: \(providerUserIdentifier == nil ? "nil" : "<redacted>")\
    )
    """
  }

  var debugDescription: String {
    description
  }
}

nonisolated enum SocialAuthorizationOutcome: Equatable, Sendable {
  case authorized(SocialAuthorization)
  case cancelled
  case failed
}

nonisolated enum SocialLoginError: Error, Equatable, Sendable {
  case unavailable
  case unsupportedProvider(String)
  case invalidAuthorization
}

@MainActor
protocol SocialLoginCoordinating: AnyObject {
  func login(with authorization: SocialAuthorization) async throws
}

@MainActor
final class SocialLoginCoordinator: SocialLoginCoordinating {
  private let authRemoteDataSource: any AuthRemoteDataSource
  private let accountSessionStore: AccountSessionStore

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
  }

  func login(with authorization: SocialAuthorization) async throws {
    guard Self.supports(authorization.provider) else {
      throw SocialLoginError.unsupportedProvider(
        authorization.provider.serverValue
      )
    }
    guard !authorization.token
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SocialLoginError.invalidAuthorization
    }
    if authorization.provider == .apple {
      guard Self.hasValue(authorization.authorizationCode),
            Self.hasValue(authorization.rawNonce),
            Self.hasValue(authorization.providerUserIdentifier) else {
        throw SocialLoginError.invalidAuthorization
      }
    }

    // The 2026-07-27 OpenAPI contract accepts only token and
    // authorizationCode. Keep the locally bound raw nonce and Apple user
    // identifier out of the request until the server explicitly declares
    // those fields.
    let response = try await authRemoteDataSource.login(
      provider: authorization.provider,
      request: SocialLoginRequestDTO(
        token: authorization.token,
        authorizationCode: authorization.authorizationCode
      )
    )
    let credentials = AccountCredentials(
      memberID: response.memberId,
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      onboardingCompleted: response.onboardingCompleted,
      provider: authorization.provider,
      providerUserIdentifier: authorization.providerUserIdentifier
    )

    try accountSessionStore.establishSession(credentials: credentials)
  }

  nonisolated private static func supports(_ provider: AuthProvider) -> Bool {
    switch provider {
    case .apple, .google, .kakao:
      true
    case .unknown:
      false
    }
  }

  nonisolated private static func hasValue(_ value: String?) -> Bool {
    guard let value else {
      return false
    }

    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

@MainActor
final class UnavailableSocialLoginCoordinator: SocialLoginCoordinating {
  func login(with authorization: SocialAuthorization) async throws {
    throw SocialLoginError.unavailable
  }
}
