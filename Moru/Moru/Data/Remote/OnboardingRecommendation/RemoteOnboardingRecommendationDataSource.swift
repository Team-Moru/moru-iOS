//
//  RemoteOnboardingRecommendationDataSource.swift
//  Moru
//

import Foundation

nonisolated protocol OnboardingRecommendationRemoteDataSource:
  ServerOnboardingRecommendationFetching {
  func fetchRecommendations(
    goalType: OnboardingRecommendationGoalType,
    memberID: Int64
  ) async throws -> [OnboardingRecommendationGroupDTO]
}

nonisolated enum OnboardingRecommendationRemoteDataSourceError:
  Error,
  Equatable,
  Sendable,
  RoutineSuggestionInvalidResponseError {
  case invalidMember
}

nonisolated extension OnboardingRecommendationRemoteDataSource {
  func fetchRecommendations(
    for goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> [ServerRoutineSuggestionResponse] {
    guard memberID > 0 else {
      throw RoutineSuggestionRemoteFailure.invalidResponse
    }

    do {
      return try await fetchRecommendations(
        goalType: OnboardingRecommendationGoalType(goal: goal),
        memberID: memberID
      ).map(\.domainModel)
    } catch {
      throw RoutineSuggestionRemoteFailureMapper.map(error)
    }
  }
}

nonisolated final class DefaultOnboardingRecommendationRemoteDataSource:
  OnboardingRecommendationRemoteDataSource {
  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func fetchRecommendations(
    goalType: OnboardingRecommendationGoalType,
    memberID: Int64
  ) async throws -> [OnboardingRecommendationGroupDTO] {
    guard memberID > 0 else {
      throw OnboardingRecommendationRemoteDataSourceError.invalidMember
    }

    return try await apiClient.request(
      OnboardingRecommendationTarget.recommendations(goalType: goalType),
      as: [OnboardingRecommendationGroupDTO].self,
      authorizedForMemberID: memberID
    )
  }
}

nonisolated private extension OnboardingRecommendationGroupDTO {
  var domainModel: ServerRoutineSuggestionResponse {
    ServerRoutineSuggestionResponse(
      title: title ?? "",
      description: description,
      steps: (routines ?? []).map(\.domainModel)
    )
  }
}

nonisolated private extension OnboardingRecommendationRoutineDTO {
  var domainModel: ServerRoutineSuggestionStep {
    ServerRoutineSuggestionStep(
      title: title ?? "",
      kind: domainKind,
      durationSeconds: durationSecond ?? 0
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
    case .some(let value):
      .unsupported(value)
    case nil:
      .unsupported("MISSING")
    }
  }
}
