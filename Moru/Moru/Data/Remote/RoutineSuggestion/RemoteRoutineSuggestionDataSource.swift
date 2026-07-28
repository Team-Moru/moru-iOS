//
//  RemoteRoutineSuggestionDataSource.swift
//  Moru
//

import Foundation

nonisolated protocol RoutineSuggestionRemoteDataSource: Sendable {
  func generate(
    request: RoutineGroupAiGenerateRequestDTO
  ) async throws -> RoutineGroupAiGenerateResponseDTO
}

nonisolated enum RoutineSuggestionRemoteDataSourceError:
  Error,
  Equatable,
  Sendable {
  case invalidUserInputLength
}

nonisolated final class DefaultRoutineSuggestionRemoteDataSource:
  RoutineSuggestionRemoteDataSource {
  private let apiClient: any APIClient

  init(apiClient: any APIClient) {
    self.apiClient = apiClient
  }

  func generate(
    request: RoutineGroupAiGenerateRequestDTO
  ) async throws -> RoutineGroupAiGenerateResponseDTO {
    guard request.userInput.count <= 200 else {
      throw RoutineSuggestionRemoteDataSourceError.invalidUserInputLength
    }

    return try await apiClient.request(
      RoutineSuggestionTarget.generate(request),
      as: RoutineGroupAiGenerateResponseDTO.self
    )
  }
}
