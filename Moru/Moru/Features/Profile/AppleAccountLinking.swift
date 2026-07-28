//
//  AppleAccountLinking.swift
//  Moru
//

import AuthenticationServices
import Foundation

nonisolated enum AppleAuthorizationOutcome: Equatable, Sendable {
  case authorized(identityToken: String, authorizationCode: String)
  case cancelled
  case failed
}

nonisolated enum AppleAccountLinkingError: Error, Equatable, Sendable {
  case unavailable
}

nonisolated struct AppleAuthorizationCallback {
  static func outcome(
    for result: Result<ASAuthorization, Error>
  ) -> AppleAuthorizationOutcome {
    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential
        as? ASAuthorizationAppleIDCredential else {
        return .failed
      }

      return outcome(
        identityToken: credential.identityToken,
        authorizationCode: credential.authorizationCode
      )
    case .failure(let error):
      let nsError = error as NSError
      guard nsError.domain == ASAuthorizationError.errorDomain,
            nsError.code == ASAuthorizationError.canceled.rawValue else {
        return .failed
      }

      return .cancelled
    }
  }

  static func outcome(
    identityToken: Data?,
    authorizationCode: Data?
  ) -> AppleAuthorizationOutcome {
    guard let identityToken = string(from: identityToken),
          let authorizationCode = string(from: authorizationCode) else {
      return .failed
    }

    return .authorized(
      identityToken: identityToken,
      authorizationCode: authorizationCode
    )
  }

  private static func string(from data: Data?) -> String? {
    guard let data,
          let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return nil
    }

    return value
  }
}

@MainActor
protocol AppleAccountLinking: AnyObject {
  func link(
    identityToken: String,
    authorizationCode: String
  ) async throws
}

@MainActor
final class DefaultAppleAccountLinkingService: AppleAccountLinking {
  private let authRemoteDataSource: any AuthRemoteDataSource
  private let accountSessionStore: AccountSessionStore

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
  }

  func link(
    identityToken: String,
    authorizationCode: String
  ) async throws {
    let response = try await authRemoteDataSource.login(
      provider: .apple,
      request: SocialLoginRequestDTO(
        token: identityToken,
        authorizationCode: authorizationCode
      )
    )
    let credentials = AccountCredentials(
      memberID: response.memberId,
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      onboardingCompleted: response.onboardingCompleted
    )

    try accountSessionStore.establishSession(credentials: credentials)
  }
}

@MainActor
final class UnavailableAppleAccountLinkingService: AppleAccountLinking {
  func link(
    identityToken: String,
    authorizationCode: String
  ) async throws {
    throw AppleAccountLinkingError.unavailable
  }
}
