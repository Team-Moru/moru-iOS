//
//  OnboardingRecommendationCoordinator.swift
//  Moru
//

import Foundation

@MainActor
final class OnboardingRecommendationCoordinator:
  RoutineSuggestionCoordinating {
  private let serverService: (any ServerOnboardingRecommendationServing)?
  private let localService: any RoutineSuggestionService
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?

  init(
    serverService: (any ServerOnboardingRecommendationServing)?,
    localService: any RoutineSuggestionService,
    signedInMemberProvider: (any SignedInMemberProviding)?
  ) {
    self.serverService = serverService
    self.localService = localService
    self.signedInMemberProvider = signedInMemberProvider
  }

  func suggest(
    from input: RoutineSuggestionInput
  ) async throws -> RoutineSuggestionResult {
    guard let memberID = signedInMemberProvider?.signedInMemberID else {
      return try localResult(from: input, reason: .signedOut)
    }
    guard let primaryGoalTag = input.goalTags.first,
          let goal = OnboardingRecommendationGoal(
            rawValue: primaryGoalTag
          ) else {
      return try localResult(from: input, reason: .unavailable)
    }
    guard let serverService else {
      return try localResult(from: input, reason: .serverUnavailable)
    }

    do {
      let routine = try await serverService.makeRoutine(
        from: input,
        goal: goal,
        memberID: memberID
      )

      guard signedInMemberProvider?.signedInMemberID == memberID else {
        return try localResult(from: input, reason: .accountChanged)
      }

      return RoutineSuggestionResult(routine: routine, source: .server)
    } catch is CancellationError {
      throw CancellationError()
    } catch RoutineSuggestionRemoteFailure.cancelled {
      throw CancellationError()
    } catch {
      guard signedInMemberProvider?.signedInMemberID == memberID else {
        return try localResult(from: input, reason: .accountChanged)
      }

      return try localResult(
        from: input,
        reason: RoutineSuggestionFallbackPolicy.reason(for: error)
      )
    }
  }

  private func localResult(
    from input: RoutineSuggestionInput,
    reason: RoutineSuggestionFallbackReason
  ) throws -> RoutineSuggestionResult {
    RoutineSuggestionResult(
      routine: try localService.makeRoutine(from: input),
      source: .localFallback(reason)
    )
  }
}
