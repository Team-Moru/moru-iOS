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

nonisolated final class EmptyAccessTokenProvider: AccessTokenProviding {
  let accessToken: String? = nil
}
