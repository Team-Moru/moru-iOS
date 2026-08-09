//
//  AccountRoutineExecutionRemoteServing.swift
//  Moru
//

import Foundation

nonisolated protocol AccountRoutineExecutionRemoteServing: Sendable {
  func saveExecution(
    _ submission: ServerRoutineExecutionSubmission,
    memberID: Int64
  ) async throws -> ServerRoutineExecutionResult

  func judgeCheckStep(
    _ submission: ServerAIExecutionSubmission,
    memberID: Int64
  ) async throws -> ServerAIExecutionJudgment
}

nonisolated enum AccountRoutineExecutionRemoteError:
  Error,
  Equatable,
  Sendable
{
  case invalidRequest
  case invalidResponse
  case accountAuthorizationChanged
}
