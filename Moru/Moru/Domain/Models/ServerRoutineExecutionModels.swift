//
//  ServerRoutineExecutionModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerRoutineExecutionSubmission:
  Equatable,
  Sendable
{
  let routineID: Int64
  let executedDate: String
  let durationSeconds: Int?
  let isCompleted: Bool
  let memberInput: String?
  let aiResponse: String?
  let actualWakeTime: String?

  init(
    routineID: Int64,
    executedDate: String,
    durationSeconds: Int? = nil,
    isCompleted: Bool,
    memberInput: String? = nil,
    aiResponse: String? = nil,
    actualWakeTime: String? = nil
  ) {
    self.routineID = routineID
    self.executedDate = executedDate
    self.durationSeconds = durationSeconds
    self.isCompleted = isCompleted
    self.memberInput = memberInput
    self.aiResponse = aiResponse
    self.actualWakeTime = actualWakeTime
  }
}

nonisolated struct ServerAIExecutionSubmission:
  Equatable,
  Sendable
{
  let routineID: Int64
  let executedDate: String
  let durationSeconds: Int?
  let memberInput: String
  let actualWakeTime: String?

  init(
    routineID: Int64,
    executedDate: String,
    durationSeconds: Int? = nil,
    memberInput: String,
    actualWakeTime: String? = nil
  ) {
    self.routineID = routineID
    self.executedDate = executedDate
    self.durationSeconds = durationSeconds
    self.memberInput = memberInput
    self.actualWakeTime = actualWakeTime
  }
}

nonisolated struct ServerRoutineExecutionResult:
  Equatable,
  Sendable
{
  let executionID: Int64
  let routineID: Int64
  let executedDate: String
  let durationSeconds: Int?
  let isCompleted: Bool
}

nonisolated struct ServerAIExecutionJudgment:
  Equatable,
  Sendable
{
  let aiResponse: String
  let shouldProceed: Bool
}
