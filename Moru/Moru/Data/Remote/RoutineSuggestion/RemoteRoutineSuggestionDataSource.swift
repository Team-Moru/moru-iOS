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
  Sendable,
  RoutineSuggestionInvalidResponseError {
  case invalidUserInput
}

nonisolated extension RoutineSuggestionRemoteDataSource {
  func generate(
    userInput: String,
    memberID: Int64
  ) async throws -> ServerRoutineSuggestionResponse {
    guard memberID > 0,
          RoutineSuggestionDraftValidation.isValidUserInput(
            userInput
          ) else {
      throw RoutineSuggestionRemoteFailure.invalidResponse
    }

    do {
      return try await generate(
        request: RoutineGroupAiGenerateRequestDTO(userInput: userInput),
        memberID: memberID
      ).domainModel
    } catch {
      throw RoutineSuggestionRemoteFailureMapper.map(error)
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
          RoutineSuggestionDraftValidation.isValidUserInput(
            request.userInput
          ) else {
      throw RoutineSuggestionRemoteDataSourceError.invalidUserInput
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
