//
//  RemoteRoutineExecutionService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultAccountRoutineExecutionRemoteService:
  AccountRoutineExecutionRemoteServing
{
  private static let maximumTextLength = 500
  private static let validDurationRange = 0...Int(Int32.max)

  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func saveExecution(
    _ submission: ServerRoutineExecutionSubmission,
    memberID: Int64
  ) async throws -> ServerRoutineExecutionResult {
    guard memberID > 0,
      Self.isValidRoutineID(submission.routineID),
      Self.isValidDate(submission.executedDate),
      Self.isValidDuration(submission.durationSeconds),
      Self.isValidOptionalText(submission.memberInput),
      Self.isValidOptionalText(submission.aiResponse),
      Self.isValidOptionalWakeTime(submission.actualWakeTime)
    else {
      throw AccountRoutineExecutionRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineExecutionTarget.create(
          RoutineExecutionResultRequestDTO(
            executedDate: submission.executedDate,
            routineId: submission.routineID,
            durationSecond: submission.durationSeconds,
            isCompleted: submission.isCompleted,
            memberInput: submission.memberInput,
            aiResponse: submission.aiResponse,
            actualWakeTime: submission.actualWakeTime
          )
        ),
        as: RoutineExecutionResultResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel(expected: submission)
    }
  }

  func judgeCheckStep(
    _ submission: ServerAIExecutionSubmission,
    memberID: Int64
  ) async throws -> ServerAIExecutionJudgment {
    guard memberID > 0,
      Self.isValidRoutineID(submission.routineID),
      Self.isValidDate(submission.executedDate),
      Self.isValidDuration(submission.durationSeconds),
      Self.isValidText(submission.memberInput),
      Self.isValidOptionalWakeTime(submission.actualWakeTime)
    else {
      throw AccountRoutineExecutionRemoteError.invalidRequest
    }

    return try await performAccountRequest {
      let response = try await apiClient.request(
        RoutineExecutionTarget.aiStep(
          RoutineExecutionAIRequestDTO(
            routineId: submission.routineID,
            executedDate: submission.executedDate,
            durationSecond: submission.durationSeconds,
            memberInput: submission.memberInput,
            actualWakeTime: submission.actualWakeTime
          )
        ),
        as: RoutineExecutionAIResponseDTO.self,
        authorizedForMemberID: memberID
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()
      return try response.makeDomainModel()
    }
  }

  private func performAccountRequest<Output: Sendable>(
    _ operation: () async throws -> Output
  ) async throws -> Output {
    do {
      return try await operation()
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch is AccountAuthorizationContextError {
      throw AccountRoutineExecutionRemoteError.accountAuthorizationChanged
    }
  }

  private static func isValidRoutineID(_ routineID: Int64) -> Bool {
    routineID > 0
  }

  private static func isValidDuration(_ duration: Int?) -> Bool {
    duration.map(validDurationRange.contains) ?? true
  }

  private static func isValidOptionalText(_ value: String?) -> Bool {
    value.map(isValidText) ?? true
  }

  private static func isValidText(_ value: String) -> Bool {
    value.count <= maximumTextLength
  }

  private static func isValidOptionalWakeTime(_ value: String?) -> Bool {
    value.map(isValidWakeTime) ?? true
  }

  private static func isValidDate(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      (1...9999).contains(year),
      (1...12).contains(month)
    else {
      return false
    }

    return (1...daysInMonth(year: year, month: month)).contains(day)
  }

  private static func isValidWakeTime(_ value: String) -> Bool {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      parts[0].count == 2,
      parts[1].count == 2,
      parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
      let hour = Int(parts[0]),
      let minute = Int(parts[1])
    else {
      return false
    }

    return (0...23).contains(hour) && (0...59).contains(minute)
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2:
      isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11:
      30
    default:
      31
    }
  }

  private static func isLeapYear(_ year: Int) -> Bool {
    year.isMultiple(of: 400)
      || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
  }
}

nonisolated extension RoutineExecutionResultResponseDTO {
  fileprivate func makeDomainModel(
    expected submission: ServerRoutineExecutionSubmission
  ) throws -> ServerRoutineExecutionResult {
    guard let executionId,
      executionId > 0,
      let routineId,
      routineId == submission.routineID,
      let executedDate,
      executedDate == submission.executedDate,
      let isCompleted,
      isCompleted == submission.isCompleted,
      durationSecond.map({ (0...Int(Int32.max)).contains($0) })
        ?? true
    else {
      throw AccountRoutineExecutionRemoteError.invalidResponse
    }

    return ServerRoutineExecutionResult(
      executionID: executionId,
      routineID: routineId,
      executedDate: executedDate,
      durationSeconds: durationSecond,
      isCompleted: isCompleted
    )
  }
}

nonisolated extension RoutineExecutionAIResponseDTO {
  fileprivate func makeDomainModel() throws -> ServerAIExecutionJudgment {
    guard let aiResponse,
      let shouldProceed
    else {
      throw AccountRoutineExecutionRemoteError.invalidResponse
    }

    return ServerAIExecutionJudgment(
      aiResponse: aiResponse,
      shouldProceed: shouldProceed
    )
  }
}
