//
//  RemoteRoutineSuggestionDataSource.swift
//  Moru
//

import Foundation

nonisolated protocol RoutineSuggestionRemoteDataSource:
  ServerRoutineSuggestionFetching {
  func generate(
    request: RoutineGroupAiGenerateRequestDTO,
    memberID: Int64
  ) async throws -> RoutineGroupAiGenerateResponseDTO
}

nonisolated enum RoutineSuggestionRemoteDataSourceError:
  Error,
  Equatable,
  Sendable {
  case invalidUserInputLength
}

nonisolated extension RoutineSuggestionRemoteDataSource {
  func generate(
    userInput: String,
    memberID: Int64
  ) async throws -> ServerRoutineSuggestionResponse {
    guard memberID > 0,
          userInput.count
      <= RoutineSuggestionDraftValidation.maximumUserInputLength else {
      throw RoutineSuggestionRemoteFailure.invalidResponse
    }

    do {
      return try await generate(
        request: RoutineGroupAiGenerateRequestDTO(userInput: userInput),
        memberID: memberID
      ).domainModel
    } catch {
      throw Self.mapRemoteFailure(error)
    }
  }

  private static func mapRemoteFailure(
    _ error: Error
  ) -> RoutineSuggestionRemoteFailure {
    if let failure = error as? RoutineSuggestionRemoteFailure {
      return failure
    }
    if error is RoutineSuggestionRemoteDataSourceError {
      return .invalidResponse
    }
    if error is CancellationError {
      return .cancelled
    }

    guard let apiError = error as? APIError else {
      return .unavailable
    }

    switch apiError {
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
    case .server(let statusCode, _, _) where statusCode == 408:
      return .timeout
    case .server(let statusCode, _, _)
      where (500..<600).contains(statusCode):
      return .serverUnavailable
    case .decoding, .missingResult:
      return .invalidResponse
    case .cancelled:
      return .cancelled
    case .authenticationRequired,
         .capabilityDisabled,
         .invalidRequest,
         .server:
      return .unavailable
    }
  }
}

nonisolated final class DefaultRoutineSuggestionRemoteDataSource:
  RoutineSuggestionRemoteDataSource {
  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func generate(
    request: RoutineGroupAiGenerateRequestDTO,
    memberID: Int64
  ) async throws -> RoutineGroupAiGenerateResponseDTO {
    guard memberID > 0,
          request.userInput.count
      <= RoutineSuggestionDraftValidation.maximumUserInputLength else {
      throw RoutineSuggestionRemoteDataSourceError.invalidUserInputLength
    }

    return try await apiClient.request(
      RoutineSuggestionTarget.generate(request),
      as: RoutineGroupAiGenerateResponseDTO.self,
      authorizedForMemberID: memberID
    )
  }
}

nonisolated private extension RoutineGroupAiGenerateResponseDTO {
  var domainModel: ServerRoutineSuggestionResponse {
    ServerRoutineSuggestionResponse(
      title: title,
      description: description,
      steps: routines.map(\.domainModel)
    )
  }
}

nonisolated private extension RoutineSuggestionStepDTO {
  var domainModel: ServerRoutineSuggestionStep {
    ServerRoutineSuggestionStep(
      title: title,
      kind: domainKind,
      durationSeconds: durationSecond
    )
  }

  var domainKind: ServerRoutineSuggestionStepKind {
    switch type {
    case "CHECK":
      .check
    case "TIMER":
      .timer
    case "INPUT":
      .input
    default:
      .unsupported(type)
    }
  }
}
