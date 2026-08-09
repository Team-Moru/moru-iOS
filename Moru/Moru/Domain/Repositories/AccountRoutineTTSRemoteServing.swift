//
//  AccountRoutineTTSRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountRoutineTTSRemoteServing: Sendable {
  func fetchRoutineTTS(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> [ServerRoutineTTSItem]
}

nonisolated enum AccountRoutineTTSRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
