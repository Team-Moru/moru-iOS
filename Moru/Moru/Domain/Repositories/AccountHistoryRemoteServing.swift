//
//  AccountHistoryRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountHistoryRemoteServing: Sendable {
  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary
}

nonisolated enum AccountHistoryRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
