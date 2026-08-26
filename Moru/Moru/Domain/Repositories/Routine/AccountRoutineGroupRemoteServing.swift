//
//  AccountRoutineGroupRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountRoutineGroupRemoteServing: Sendable {
  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary]

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail

  func fetchActiveRoutineGroup(
    identity: AccountSessionIdentity
  ) async throws -> ServerActiveRoutineGroup?

  func fetchTodayRoutineGroupSummary(
    identity: AccountSessionIdentity
  ) async throws -> ServerTodayRoutineGroupSummary?
}

nonisolated enum AccountRoutineGroupRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  /// `reason` names the field/guard that rejected the response, to make a
  /// legacy or unexpectedly-shaped server payload diagnosable in logs.
  case invalidResponse(reason: String)
  case accountAuthorizationChanged
}
