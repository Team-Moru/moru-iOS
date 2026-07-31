//
//  AuthenticationRequirement.swift
//  Moru
//

import Foundation

nonisolated enum AuthenticationRequirement: Equatable, Sendable {
  case none
  case bearer
}

nonisolated protocol AccessTokenProviding: AnyObject, Sendable {
  var accessToken: String? { get }
}

nonisolated struct AccountAuthorizationContext: Equatable, Sendable {
  let memberID: Int64
  let accessToken: String
  let sessionID: UUID
}

nonisolated protocol AccountBoundAccessTokenProviding:
  AccessTokenProviding {
  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext?
}

nonisolated enum AccountAuthorizationContextError:
  Error,
  Equatable,
  Sendable {
  case memberMismatch
}

nonisolated final class EmptyAccessTokenProvider: AccessTokenProviding {
  let accessToken: String? = nil
}
