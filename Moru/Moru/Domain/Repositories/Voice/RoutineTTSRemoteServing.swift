//
//  RoutineTTSRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol RoutineTTSRemoteServing: Sendable {
  func fetchRoutineTTS(
    routineGroupID: Int64,
    identity: AccountSessionIdentity
  ) async throws -> [ServerRoutineTTSRoutine]
}

nonisolated enum RoutineTTSRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
