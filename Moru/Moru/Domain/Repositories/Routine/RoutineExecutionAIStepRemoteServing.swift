//
//  RoutineExecutionAIStepRemoteServing.swift
//  Moru
//

import Foundation

/// Performs one account-session-bound AI-step submission.
///
/// The live endpoint may persist a successful decision but exposes no
/// idempotency or duplicate-reconciliation contract. Callers must treat a
/// timeout as ambiguous and must not automatically repeat the submission.
nonisolated protocol RoutineExecutionAIStepRemoteServing: Sendable {
  func evaluate(
    _ request: RoutineExecutionAIStepRequest,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> RoutineExecutionAIStepDecision
}

nonisolated enum RoutineExecutionAIStepInvalidRequest:
  Error,
  Equatable,
  Sendable {
  case memberID
  case routineID
  case executedDate
  case durationSeconds
  case memberInput
  case actualWakeTime
  case encoding
}

nonisolated enum RoutineExecutionAIStepError:
  Error,
  Equatable,
  Sendable {
  case invalidRequest(RoutineExecutionAIStepInvalidRequest)
  case invalidResponse
  /// The request may contain free-form routine input that is processed by
  /// Google Gemini through the MORU service. Never begin that transmission
  /// without the separate, explicit AI-data consent.
  case geminiConsentRequired
  case accountSessionUnavailable
  case accountAuthorizationChanged
  case timeout
  case offline
  case serverUnavailable(statusCode: Int)
  case serverRejected(statusCode: Int, code: String?)
  case unavailable
}
