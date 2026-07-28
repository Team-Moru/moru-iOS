//
//  AccessTokenRefreshing.swift
//  Moru
//

import Foundation

nonisolated struct AccessTokenRefreshResult: Equatable, Sendable {
  let accessToken: String
  let refreshToken: String
}

nonisolated extension AccessTokenRefreshResult:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    "AccessTokenRefreshResult(accessToken: <redacted>, refreshToken: <redacted>)"
  }

  var debugDescription: String {
    description
  }
}

nonisolated protocol AccessTokenRefreshing: Sendable {
  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String
  ) async throws -> AccessTokenRefreshResult
}
