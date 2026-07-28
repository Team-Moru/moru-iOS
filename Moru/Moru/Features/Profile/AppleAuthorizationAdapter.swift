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
  func outcome(
    for result: Result<ASAuthorization, Error>
  ) -> SocialAuthorizationOutcome {
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

  func outcome(
    identityToken: Data?,
    authorizationCode: Data?
  ) -> SocialAuthorizationOutcome {
    guard let identityToken = string(from: identityToken),
          let authorizationCode = string(from: authorizationCode) else {
      return .failed
    }

    return .authorized(
      SocialAuthorization(
        provider: .apple,
        token: identityToken,
        authorizationCode: authorizationCode
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
}

extension AppleAuthorizationAdapter: SocialAuthorizationAdapting {}
