//
//  EvaluateRoutineExecutionAIStepUseCase.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineExecutionAIStepEvaluating: AnyObject {
  func evaluate(
    _ request: RoutineExecutionAIStepRequest
  ) async throws -> RoutineExecutionAIStepDecision
}

@MainActor
final class EvaluateRoutineExecutionAIStepUseCase:
  RoutineExecutionAIStepEvaluating {
  private let remoteService: any RoutineExecutionAIStepRemoteServing
  private let sessionIdentityProvider:
    any CurrentAccountSessionIdentityProviding
  private let geminiDataConsent: any GeminiDataConsentAuthorizing

  init(
    remoteService: any RoutineExecutionAIStepRemoteServing,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    geminiDataConsent: any GeminiDataConsentAuthorizing
  ) {
    self.remoteService = remoteService
    self.sessionIdentityProvider = sessionIdentityProvider
    self.geminiDataConsent = geminiDataConsent
  }

  func evaluate(
    _ request: RoutineExecutionAIStepRequest
  ) async throws -> RoutineExecutionAIStepDecision {
    try Task.checkCancellation()
    guard geminiDataConsent.hasExplicitGeminiDataConsent else {
      geminiDataConsent.requestGeminiDataConsentIfNeeded()
      throw RoutineExecutionAIStepError.geminiConsentRequired
    }

    guard let identity = sessionIdentityProvider
      .currentAccountSessionIdentity else {
      throw RoutineExecutionAIStepError.accountSessionUnavailable
    }

    do {
      let decision = try await remoteService.evaluate(
        request,
        authorizedFor: identity
      )
      try Task.checkCancellation()

      guard sessionIdentityProvider.currentAccountSessionIdentity
              == identity else {
        throw RoutineExecutionAIStepError.accountAuthorizationChanged
      }

      return decision
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      guard sessionIdentityProvider.currentAccountSessionIdentity
              == identity else {
        throw RoutineExecutionAIStepError.accountAuthorizationChanged
      }
      throw error
    }
  }
}
