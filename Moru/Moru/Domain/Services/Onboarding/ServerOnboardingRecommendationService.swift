//
//  ServerOnboardingRecommendationService.swift
//  Moru
//

import Foundation

nonisolated enum OnboardingRecommendationGoal:
  String,
  Equatable,
  Sendable {
  case energy
  case health
  case mind
  case habit
}

/// Domain-owned port for fetching goal-based onboarding recommendation groups.
nonisolated protocol ServerOnboardingRecommendationFetching: Sendable {
  func fetchRecommendations(
    for goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> [ServerRoutineSuggestionResponse]
}

enum ServerOnboardingRecommendationError:
  Error,
  Equatable {
  case noValidRecommendation
}

@MainActor
protocol ServerOnboardingRecommendationServing: AnyObject {
  func makeRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> Routine
}

@MainActor
final class ServerOnboardingRecommendationService:
  ServerOnboardingRecommendationServing {
  private let remoteFetcher: any ServerOnboardingRecommendationFetching
  private let draftFactory: ServerRoutineDraftFactory

  init(
    remoteDataSource: any ServerOnboardingRecommendationFetching,
    now: @escaping () -> Date = Date.init
  ) {
    self.remoteFetcher = remoteDataSource
    self.draftFactory = ServerRoutineDraftFactory(now: now)
  }

  func makeRoutine(
    from input: RoutineSuggestionInput,
    goal: OnboardingRecommendationGoal,
    memberID: Int64
  ) async throws -> Routine {
    let responses = try await remoteFetcher.fetchRecommendations(
      for: goal,
      memberID: memberID
    )
    try Task.checkCancellation()

    for response in responses {
      do {
        return try draftFactory.makeRoutine(
          from: response,
          input: input
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch is ServerRoutineSuggestionError {
        continue
      }
    }

    throw ServerOnboardingRecommendationError.noValidRecommendation
  }
}
