//
//  AccessTokenRefreshing.swift
//  Moru
//

import Foundation

nonisolated protocol AccessTokenRefreshing: Sendable {
  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String
  ) async throws -> String
}
