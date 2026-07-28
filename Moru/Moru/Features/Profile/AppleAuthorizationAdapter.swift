//
//  AppleAuthorizationAdapter.swift
//  Moru
//

import AuthenticationServices
import Foundation

nonisolated protocol SocialAuthorizationAdapting {
  associatedtype Callback

  func outcome(for callback: Callback) -> SocialAuthorizationOutcome
}

nonisolated struct AppleAuthorizationAdapter {
  typealias Callback = (
    result: Result<ASAuthorization, Error>,
    rawNonce: String
  )

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
        return .failed
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
        return .failed
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
    guard let identityToken = string(from: identityToken),
          let authorizationCode = string(from: authorizationCode),
          let userIdentifier = normalized(userIdentifier),
          let rawNonce = normalized(rawNonce) else {
      return .failed
    }

    return .authorized(
      SocialAuthorization(
        provider: .apple,
        token: identityToken,
        authorizationCode: authorizationCode,
        rawNonce: rawNonce,
        providerUserIdentifier: userIdentifier
      )
    )
  }

  private func string(from data: Data?) -> String? {
    guard let data,
          let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return nil
    }

    return value
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
}

extension AppleAuthorizationAdapter: SocialAuthorizationAdapting {}
