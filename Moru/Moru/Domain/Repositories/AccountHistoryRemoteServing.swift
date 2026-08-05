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

  func fetchDaily(
    year: Int,
    month: Int,
    day: Int,
    memberID: Int64
  ) async throws -> ServerHistoryDailySummary
}

nonisolated enum AccountHistoryRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
