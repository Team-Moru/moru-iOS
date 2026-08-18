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
  private let geminiDataConsent: any GeminiDataConsentAuthorizing

  init(
    serverService: (any ServerOnboardingRecommendationServing)?,
    localService: any RoutineSuggestionService,
    signedInMemberProvider: (any SignedInMemberProviding)?,
    geminiDataConsent: any GeminiDataConsentAuthorizing
  ) {
    self.serverService = serverService
    self.localService = localService
    self.signedInMemberProvider = signedInMemberProvider
    self.geminiDataConsent = geminiDataConsent
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
      throw RoutineSuggestionRequestError.unsupportedOnboardingGoal
    }
    guard let serverService else {
      return try localResult(from: input, reason: .serverUnavailable)
    }

    switch try await RoutineSuggestionConsentPolicy.resolve(
      using: geminiDataConsent
    ) {
    case .useLocalFallbackAfterDecline:
      return try localResult(
        from: input,
        reason: .geminiConsentDeclined
      )
    case .useServer:
      break
    }

    try Task.checkCancellation()
    guard signedInMemberProvider?.signedInMemberID == memberID else {
      throw RoutineSuggestionRequestError.accountChanged
    }

    do {
      let routine = try await serverService.makeRoutine(
        from: input,
        goal: goal,
        memberID: memberID
      )
      try Task.checkCancellation()

      guard signedInMemberProvider?.signedInMemberID == memberID else {
        throw RoutineSuggestionRequestError.accountChanged
      }

      return RoutineSuggestionResult(routine: routine, source: .server)
    } catch is CancellationError {
      throw CancellationError()
    } catch RoutineSuggestionRemoteFailure.cancelled {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      guard signedInMemberProvider?.signedInMemberID == memberID else {
        throw RoutineSuggestionRequestError.accountChanged
      }

      throw error
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
