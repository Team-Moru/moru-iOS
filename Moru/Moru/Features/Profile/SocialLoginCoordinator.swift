//
//  SocialLoginCoordinator.swift
//  Moru
//

import Foundation

nonisolated struct SocialAuthorization: Equatable, Sendable {
  let provider: AuthProvider
  let token: String
  let authorizationCode: String?

  init(
    provider: AuthProvider,
    token: String,
    authorizationCode: String? = nil
  ) {
    self.provider = provider
    self.token = token
    self.authorizationCode = authorizationCode
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
    authorizationCode: \(authorizationCode == nil ? "nil" : "<redacted>")\
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
      provider: authorization.provider
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
}

@MainActor
final class UnavailableSocialLoginCoordinator: SocialLoginCoordinating {
  func login(with authorization: SocialAuthorization) async throws {
    throw SocialLoginError.unavailable
  }
}
