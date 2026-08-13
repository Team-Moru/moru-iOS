//
//  RemoteRoutineExecutionAIStepService.swift
//  Moru
//

import Foundation

nonisolated final class DefaultRoutineExecutionAIStepRemoteService:
  RoutineExecutionAIStepRemoteServing {
  private static let maximumMemberInputLength = 500
  private static let maximumDurationSeconds = Int(Int32.max)

  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func evaluate(
    _ request: RoutineExecutionAIStepRequest,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> RoutineExecutionAIStepDecision {
    try Task.checkCancellation()
    try Self.validate(request, memberID: identity.memberID)

    let requestDTO = RoutineExecutionAIStepRequestDTO(
      routineId: request.routineID,
      executedDate: request.executedDate,
      durationSecond: request.durationSeconds,
      memberInput: request.memberInput,
      actualWakeTime: request.actualWakeTime
    )

    do {
      let response = try await apiClient.requestOnce(
        RoutineExecutionAIStepTarget.evaluate(requestDTO),
        as: RoutineExecutionAIStepResponseDTO.self,
        authorizedFor: identity
      )
      try Task.checkCancellation()
      return try response.makeDomainModel()
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      if error is AccountAuthorizationContextError {
        throw RoutineExecutionAIStepError.accountAuthorizationChanged
      }
      if let error = error as? RoutineExecutionAIStepError {
        throw error
      }
      if let error = error as? APIError {
        throw Self.map(error)
      }
      throw RoutineExecutionAIStepError.unavailable
    }
  }

  private static func validate(
    _ request: RoutineExecutionAIStepRequest,
    memberID: Int64
  ) throws {
    guard memberID > 0 else {
      throw RoutineExecutionAIStepError.invalidRequest(.memberID)
    }
    guard request.routineID > 0 else {
      throw RoutineExecutionAIStepError.invalidRequest(.routineID)
    }
    guard isValidDate(request.executedDate) else {
      throw RoutineExecutionAIStepError.invalidRequest(.executedDate)
    }
    if let durationSeconds = request.durationSeconds,
       !(0...maximumDurationSeconds).contains(durationSeconds) {
      throw RoutineExecutionAIStepError.invalidRequest(.durationSeconds)
    }
    guard request.memberInput.utf16.count
            <= maximumMemberInputLength else {
      throw RoutineExecutionAIStepError.invalidRequest(.memberInput)
    }
    if let actualWakeTime = request.actualWakeTime,
       !isValidTime(actualWakeTime) {
      throw RoutineExecutionAIStepError.invalidRequest(.actualWakeTime)
    }
  }

  private static func isValidDate(_ value: String) -> Bool {
    let parts = value.split(
      separator: "-",
      omittingEmptySubsequences: false
    )
    guard parts.count == 3,
          parts[0].count == 4,
          parts[1].count == 2,
          parts[2].count == 2,
          parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2]),
          (1...9_999).contains(year),
          (1...12).contains(month) else {
      return false
    }

    return (1...daysInMonth(year: year, month: month)).contains(day)
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2:
      return isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11:
      return 30
    default:
      return 31
    }
  }

  private static func isLeapYear(_ year: Int) -> Bool {
    year.isMultiple(of: 400)
      || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
  }

  private static func isValidTime(_ value: String) -> Bool {
    let parts = value.split(
      separator: ":",
      omittingEmptySubsequences: false
    )
    guard parts.count == 2,
          parts[0].count == 2,
          parts[1].count == 2,
          parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
          let hour = Int(parts[0]),
          let minute = Int(parts[1]) else {
      return false
    }

    return (0...23).contains(hour) && (0...59).contains(minute)
  }

  private static func map(
    _ error: APIError
  ) -> RoutineExecutionAIStepError {
    switch error {
    case .invalidRequest:
      return .invalidRequest(.encoding)
    case .authenticationRequired:
      return .accountSessionUnavailable
    case .capabilityDisabled:
      return .unavailable
    case .transport(let code, _):
      if code == URLError.timedOut.rawValue {
        return .timeout
      }
      if [
        URLError.notConnectedToInternet.rawValue,
        URLError.networkConnectionLost.rawValue,
        URLError.cannotConnectToHost.rawValue,
        URLError.cannotFindHost.rawValue,
      ].contains(code) {
        return .offline
      }
      return .unavailable
    case .server(let statusCode, let code, _):
      if statusCode == 408 {
        return .timeout
      }
      if statusCode == 429 || (500..<600).contains(statusCode) {
        return .serverUnavailable(statusCode: statusCode)
      }
      return .serverRejected(statusCode: statusCode, code: code)
    case .decoding, .missingResult:
      return .invalidResponse
    case .cancelled:
      return .unavailable
    }
  }
}

nonisolated private extension RoutineExecutionAIStepResponseDTO {
  func makeDomainModel() throws -> RoutineExecutionAIStepDecision {
    guard let aiResponse,
          !aiResponse.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty,
          let shouldProceed else {
      throw RoutineExecutionAIStepError.invalidResponse
    }

    return RoutineExecutionAIStepDecision(
      aiResponse: aiResponse,
      shouldProceed: shouldProceed
    )
  }
}
