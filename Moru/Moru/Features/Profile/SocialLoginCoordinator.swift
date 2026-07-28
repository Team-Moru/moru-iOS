//
//  SocialLoginCoordinator.swift
//  Moru
//

import Foundation
import OSLog
import Security

nonisolated enum SocialLoginFailureStage: String, Equatable, Sendable {
  case remoteExchange = "remote_exchange"
  case sessionStorage = "session_storage"
}

nonisolated enum SocialLoginFailureKind: Equatable, Sendable {
  case server(statusCode: Int, code: String?)
  case transport(code: Int)
  case keychain(status: OSStatus)
  case invalidCredentials
  case api(category: String)
  case other
}

nonisolated struct SocialLoginFailureDiagnostic: Equatable, Sendable {
  let provider: AuthProvider
  let stage: SocialLoginFailureStage
  let kind: SocialLoginFailureKind

  var logMessage: String {
    let prefix = "provider=\(safeProvider) stage=\(stage.rawValue)"

    switch kind {
    case .server(let statusCode, let code):
      let safeCode = Self.safeServerCode(code) ?? "none"
      return "\(prefix) kind=server status=\(statusCode) code=\(safeCode)"
    case .transport(let code):
      return "\(prefix) kind=transport code=\(code)"
    case .keychain(let status):
      return "\(prefix) kind=keychain status=\(status)"
    case .invalidCredentials:
      return "\(prefix) kind=invalid_credentials"
    case .api(let category):
      return "\(prefix) kind=api category=\(category)"
    case .other:
      return "\(prefix) kind=other"
    }
  }

  static func make(
    provider: AuthProvider,
    stage: SocialLoginFailureStage,
    error: Error
  ) -> SocialLoginFailureDiagnostic {
    let kind: SocialLoginFailureKind

    switch error {
    case APIError.server(let statusCode, let code, _):
      kind = .server(statusCode: statusCode, code: safeServerCode(code))
    case APIError.transport(let code, _):
      kind = .transport(code: code)
    case APIError.invalidRequest:
      kind = .api(category: "invalid_request")
    case APIError.authenticationRequired:
      kind = .api(category: "authentication_required")
    case APIError.capabilityDisabled:
      kind = .api(category: "capability_disabled")
    case APIError.decoding:
      kind = .api(category: "decoding")
    case APIError.missingResult(let code, _):
      kind = .server(statusCode: 200, code: safeServerCode(code))
    case APIError.cancelled:
      kind = .api(category: "cancelled")
    case CredentialStoreError.keychain(let status):
      kind = .keychain(status: status)
    case CredentialStoreError.invalidCredentials,
         CredentialStoreError.invalidStoredData:
      kind = .invalidCredentials
    default:
      kind = .other
    }

    return SocialLoginFailureDiagnostic(
      provider: provider,
      stage: stage,
      kind: kind
    )
  }

  private static func safeServerCode(_ code: String?) -> String? {
    guard let code else {
      return nil
    }

    let normalized = code.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let allowedCharacters = CharacterSet(
      charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    )
    guard !normalized.isEmpty,
          normalized.count <= 64,
          normalized.unicodeScalars.allSatisfy({
            allowedCharacters.contains($0)
          }) else {
      return nil
    }

    return normalized
  }

  private var safeProvider: String {
    switch provider {
    case .apple:
      "apple"
    case .google:
      "google"
    case .kakao:
      "kakao"
    case .unknown:
      "unknown"
    }
  }
}

nonisolated protocol SocialLoginFailureReporting: Sendable {
  func report(_ diagnostic: SocialLoginFailureDiagnostic)
}

nonisolated struct SocialLoginFailureLogger: SocialLoginFailureReporting {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "SocialLogin"
  )

  func report(_ diagnostic: SocialLoginFailureDiagnostic) {
    #if DEBUG
    logger.error(
      "Social login failed: \(diagnostic.logMessage, privacy: .public)"
    )
    #endif
  }
}

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
  private let failureReporter: any SocialLoginFailureReporting

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore,
    failureReporter: any SocialLoginFailureReporting =
      SocialLoginFailureLogger()
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
    self.failureReporter = failureReporter
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
    let response: LoginResponseDTO
    do {
      response = try await authRemoteDataSource.login(
        provider: authorization.provider,
        request: SocialLoginRequestDTO(
          token: authorization.token,
          authorizationCode: authorization.authorizationCode
        )
      )
    } catch {
      failureReporter.report(
        SocialLoginFailureDiagnostic.make(
          provider: authorization.provider,
          stage: .remoteExchange,
          error: error
        )
      )
      throw error
    }

    let credentials = AccountCredentials(
      memberID: response.memberId,
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      onboardingCompleted: response.onboardingCompleted,
      provider: authorization.provider,
      providerUserIdentifier: authorization.providerUserIdentifier
    )

    do {
      try accountSessionStore.establishSession(credentials: credentials)
    } catch {
      failureReporter.report(
        SocialLoginFailureDiagnostic.make(
          provider: authorization.provider,
          stage: .sessionStorage,
          error: error
        )
      )
      throw error
    }
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
