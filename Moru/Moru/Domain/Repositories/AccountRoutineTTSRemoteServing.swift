//
//  AccountRoutineTTSRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountRoutineTTSRemoteServing: Sendable {
  func createRoutineGroup(
    _ request: ServerRoutineGroupCreationRequest,
    memberID: Int64
  ) async throws -> ServerRoutineGroupCreationResult

  func deleteRoutineGroup(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDeletionResult

  func fetchRoutineTTS(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineTTSManifest
}

nonisolated enum AccountRoutineTTSRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
