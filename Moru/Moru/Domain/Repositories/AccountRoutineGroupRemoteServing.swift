//
//  AccountRoutineGroupRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountRoutineGroupRemoteServing: Sendable {
  func createRoutineGroup(
    _ submission: ServerRoutineGroupCreateSubmission,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary]

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail
}

nonisolated enum AccountRoutineGroupRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
