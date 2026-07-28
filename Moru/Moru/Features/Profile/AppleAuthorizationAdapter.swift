//
//  AppleAuthorizationAdapter.swift
//  Moru
//

import AuthenticationServices
import Foundation
import OSLog

nonisolated enum AppleAuthorizationErrorCategory:
  String,
  Equatable,
  Sendable {
  case authenticationServices
  case other
}

nonisolated enum AppleAuthorizationFailureReason: Equatable, Sendable {
  case missingRequestContext
  case authorizationError(
    category: AppleAuthorizationErrorCategory,
    code: Int
  )
  case unexpectedCredentialType
  case missingIdentityToken
  case invalidIdentityTokenEncoding
  case missingAuthorizationCode
  case invalidAuthorizationCodeEncoding
  case missingUserIdentifier
  case missingNonce

  var logMessage: String {
    switch self {
    case .missingRequestContext:
      "missing_request_context"
    case .authorizationError(let category, let code):
      "authorization_error category=\(category.rawValue) code=\(code)"
    case .unexpectedCredentialType:
      "unexpected_credential_type"
    case .missingIdentityToken:
      "missing_identity_token"
    case .invalidIdentityTokenEncoding:
      "invalid_identity_token_encoding"
    case .missingAuthorizationCode:
      "missing_authorization_code"
    case .invalidAuthorizationCodeEncoding:
      "invalid_authorization_code_encoding"
    case .missingUserIdentifier:
      "missing_user_identifier"
    case .missingNonce:
      "missing_nonce"
    }
  }
}

nonisolated protocol AppleAuthorizationFailureReporting: Sendable {
  func report(_ reason: AppleAuthorizationFailureReason)
}

nonisolated struct AppleAuthorizationFailureLogger:
  AppleAuthorizationFailureReporting {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "AppleAuthorization"
  )

  func report(_ reason: AppleAuthorizationFailureReason) {
    #if DEBUG
    logger.error(
      "Apple authorization failed: \(reason.logMessage, privacy: .public)"
    )
    #endif
  }
}

nonisolated protocol SocialAuthorizationAdapting {
  associatedtype Callback

  func outcome(for callback: Callback) -> SocialAuthorizationOutcome
}

nonisolated struct AppleAuthorizationAdapter {
  typealias Callback = (
    result: Result<ASAuthorization, Error>,
    rawNonce: String
  )

  private let failureReporter: any AppleAuthorizationFailureReporting

  init(
    failureReporter: any AppleAuthorizationFailureReporting =
      AppleAuthorizationFailureLogger()
  ) {
    self.failureReporter = failureReporter
  }

  func outcome(for callback: Callback) -> SocialAuthorizationOutcome {
    outcome(for: callback.result, rawNonce: callback.rawNonce)
  }

  func outcome(
    for result: Result<ASAuthorization, Error>,
    rawNonce: String
  ) -> SocialAuthorizationOutcome {
    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential
        as? ASAuthorizationAppleIDCredential else {
        return failed(.unexpectedCredentialType)
      }

      return outcome(
        identityToken: credential.identityToken,
        authorizationCode: credential.authorizationCode,
        userIdentifier: credential.user,
        rawNonce: rawNonce
      )
    case .failure(let error):
      let nsError = error as NSError
      guard nsError.domain == ASAuthorizationError.errorDomain,
            nsError.code == ASAuthorizationError.canceled.rawValue else {
        let category: AppleAuthorizationErrorCategory =
          nsError.domain == ASAuthorizationError.errorDomain
            ? .authenticationServices
            : .other
        return failed(
          .authorizationError(category: category, code: nsError.code)
        )
      }

      return .cancelled
    }
  }

  func outcome(
    identityToken: Data?,
    authorizationCode: Data?,
    userIdentifier: String?,
    rawNonce: String?
  ) -> SocialAuthorizationOutcome {
    let identityTokenValue: String
    switch string(from: identityToken) {
    case .missing:
      return failed(.missingIdentityToken)
    case .invalidEncoding:
      return failed(.invalidIdentityTokenEncoding)
    case .value(let value):
      identityTokenValue = value
    }

    let authorizationCodeValue: String
    switch string(from: authorizationCode) {
    case .missing:
      return failed(.missingAuthorizationCode)
    case .invalidEncoding:
      return failed(.invalidAuthorizationCodeEncoding)
    case .value(let value):
      authorizationCodeValue = value
    }

    guard let userIdentifier = normalized(userIdentifier) else {
      return failed(.missingUserIdentifier)
    }
    guard let rawNonce = normalized(rawNonce) else {
      return failed(.missingNonce)
    }

    return .authorized(
      SocialAuthorization(
        provider: .apple,
        token: identityTokenValue,
        authorizationCode: authorizationCodeValue,
        rawNonce: rawNonce,
        providerUserIdentifier: userIdentifier
      )
    )
  }

  private enum StringResult {
    case missing
    case invalidEncoding
    case value(String)
  }

  private func string(from data: Data?) -> StringResult {
    guard let data, !data.isEmpty else {
      return .missing
    }
    guard let value = String(data: data, encoding: .utf8) else {
      return .invalidEncoding
    }

    let normalizedValue = value.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalizedValue.isEmpty else {
      return .missing
    }

    return .value(normalizedValue)
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let normalizedValue = value.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return normalizedValue.isEmpty ? nil : normalizedValue
  }

  private func failed(
    _ reason: AppleAuthorizationFailureReason
  ) -> SocialAuthorizationOutcome {
    failureReporter.report(reason)
    return .failed
  }
}

extension AppleAuthorizationAdapter: SocialAuthorizationAdapting {}
