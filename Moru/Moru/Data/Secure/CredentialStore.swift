//
//  CredentialStore.swift
//  Moru
//

import Foundation

nonisolated struct AccountCredentials: Codable, Equatable, Sendable {
  let memberID: Int64
  let accessToken: String
  let refreshToken: String
  let onboardingCompleted: Bool
  let provider: AuthProvider

  init(
    memberID: Int64,
    accessToken: String,
    refreshToken: String,
    onboardingCompleted: Bool,
    provider: AuthProvider = .apple
  ) {
    self.memberID = memberID
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.onboardingCompleted = onboardingCompleted
    self.provider = provider
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    memberID = try container.decode(Int64.self, forKey: .memberID)
    accessToken = try container.decode(String.self, forKey: .accessToken)
    refreshToken = try container.decode(String.self, forKey: .refreshToken)
    onboardingCompleted = try container.decode(
      Bool.self,
      forKey: .onboardingCompleted
    )
    // Credentials written before L0 could only have come from Sign in with Apple.
    provider = try container.decodeIfPresent(
      AuthProvider.self,
      forKey: .provider
    ) ?? .apple
  }

  var isValid: Bool {
    memberID > 0
      && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

nonisolated extension AccountCredentials:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    """
    AccountCredentials(\
    memberID: \(memberID), \
    accessToken: <redacted>, \
    refreshToken: <redacted>, \
    onboardingCompleted: \(onboardingCompleted), \
    provider: \(provider.serverValue)\
    )
    """
  }

  var debugDescription: String {
    description
  }
}

nonisolated protocol CredentialStore: Sendable {
  func load() throws -> AccountCredentials?
  func save(_ credentials: AccountCredentials) throws
  func remove() throws
}

nonisolated enum CredentialStoreError: Error, Equatable, Sendable {
  case invalidCredentials
  case invalidStoredData
  case keychain(status: Int32)
}
