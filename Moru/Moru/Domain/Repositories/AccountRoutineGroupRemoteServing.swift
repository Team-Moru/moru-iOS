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
    memberID: Int64
  ) async throws -> ServerActiveRoutineGroup?

  func fetchTodayRoutineProgress(
    memberID: Int64
  ) async throws -> ServerTodayRoutineProgress?

  func updateRoutineGroupActivation(
    routineGroupID: Int64,
    isActive: Bool,
    memberID: Int64
  ) async throws -> ServerRoutineGroupActivation
}

nonisolated enum AccountRoutineGroupRemoteError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
