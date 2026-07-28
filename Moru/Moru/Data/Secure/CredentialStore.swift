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
    onboardingCompleted: \(onboardingCompleted)\
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
