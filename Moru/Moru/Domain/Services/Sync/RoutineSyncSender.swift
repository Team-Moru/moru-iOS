//
//  RoutineSyncSender.swift
//  Moru
//

import Foundation
import OSLog

nonisolated struct RoutineSyncTransportRequest: Equatable, Sendable {
  let serverNamespace: RoutineSyncServerNamespace
  let memberID: Int64
  let operation: RoutineSyncOperation
  let command: RoutineSyncCommand
  /// Exact Outbox generation. Production sends this value verbatim as the
  /// `Idempotency-Key` header.
  let idempotencyKey: UUID
  let generation: Int
  let payloadVersion: Int
  /// Stored method/path/body. A replay must never rebuild this artifact
  /// from current SwiftData or from `command`.
  let wireRequest: RoutineSyncWireRequest
  /// Non-secret session generation captured before the attempt is claimed.
  let sessionIdentity: AccountSessionIdentity?
}

nonisolated extension RoutineSyncTransportRequest:
  CustomStringConvertible,
  CustomDebugStringConvertible {
  var description: String {
    "RoutineSyncTransportRequest(\(wireRequest.method.rawValue) \(wireRequest.path), body: <redacted>)"
  }

  var debugDescription: String { description }
}

nonisolated enum RoutineSyncTransportCommit: Equatable, Sendable {
  case createRoutineGroup(assignments: [RoutineServerBindingAssignment])
  case mutation(assignments: [RoutineServerBindingAssignment])
  case deleted
  case onboardingCompleted
}

nonisolated enum RoutineSyncTransportOutcome: Equatable, Sendable {
  case committed(RoutineSyncTransportCommit)
  /// HTTP 409 + stable machine code COMMON409.
  case processingConflict
  /// Timeout, cancellation, transport failure, retryable HTTP status, or a
  /// successful write whose response cannot prove the committed result.
  case ambiguous
  /// A classified fail-closed outcome. No automatic key rotation is allowed.
  case blocked(RoutineSyncBlockReason)
}

nonisolated protocol RoutineSyncTransport: Sendable {
  func execute(
    _ request: RoutineSyncTransportRequest
  ) async -> RoutineSyncTransportOutcome
}

@MainActor
protocol RoutineSyncWireRequestPreparing: AnyObject {
  func makeWireRequest(
    for command: RoutineSyncCommand,
    mutation: RoutineSyncMutation
  ) throws -> RoutineSyncWireRequest
}

nonisolated struct RoutineSyncProcessingRetryPolicy: Equatable, Sendable {
  let maximumConflicts: Int
  let baseDelay: TimeInterval

  init(maximumConflicts: Int = 3, baseDelay: TimeInterval = 1) {
    precondition(maximumConflicts > 0)
    precondition(baseDelay > 0)
    self.maximumConflicts = maximumConflicts
    self.baseDelay = baseDelay
  }

  func retryDate(after conflictCount: Int, from date: Date) -> Date {
    let exponent = max(0, min(conflictCount, 6))
    return date.addingTimeInterval(baseDelay * pow(2, Double(exponent)))
  }
}

nonisolated enum RoutineSyncSenderError: Error, Equatable, Sendable {
  case invalidAttemptPayload
  case invalidWireRequest
  case unexpectedCommit(operation: RoutineSyncOperation)
}

nonisolated enum RoutineSyncSendResult: Equatable, Sendable {
  case idle
  case completed(mutationID: UUID)
  case retryScheduled(mutationID: UUID, nextAttemptAt: Date?)
  case blocked(mutationID: UUID, reason: RoutineSyncBlockReason)
  /// A command that may lead to Google Gemini processing is held locally
  /// until the user has made an explicit, affirmative choice.
  case consentRequired(mutationID: UUID)
  case staleSession(mutationID: UUID)
}

/// Serial sender core. The attempt and exact HTTP artifact are durably saved
/// before transport starts. Ambiguous results can only reuse that artifact and
/// key during the server's 24-hour completed-result retention window.
@MainActor
final class RoutineSyncSender {
  private let repository: any RoutineSyncRepository
  private let requestPreparer: any RoutineSyncWireRequestPreparing
  private let transport: any RoutineSyncTransport
  private let contract: RoutineSyncServerContract
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let geminiDataConsent: any GeminiDataConsentAuthorizing
  private let retryPolicy: RoutineSyncProcessingRetryPolicy
  private let onOnboardingCompletionCommitted:
    @MainActor (AccountSessionIdentity) -> Void
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineSyncSender"
  )

  init(
    repository: any RoutineSyncRepository,
    requestPreparer: any RoutineSyncWireRequestPreparing,
    transport: any RoutineSyncTransport,
    contract: RoutineSyncServerContract,
    sessionIdentityProvider:
      (any CurrentAccountSessionIdentityProviding)? = nil,
    geminiDataConsent: any GeminiDataConsentAuthorizing,
    retryPolicy: RoutineSyncProcessingRetryPolicy = .init(),
    onOnboardingCompletionCommitted:
      @escaping @MainActor (AccountSessionIdentity) -> Void = { _ in }
  ) {
    self.repository = repository
    self.requestPreparer = requestPreparer
    self.transport = transport
    self.contract = contract
    self.sessionIdentityProvider = sessionIdentityProvider
    self.geminiDataConsent = geminiDataConsent
    self.retryPolicy = retryPolicy
    self.onOnboardingCompletionCommitted = onOnboardingCompletionCommitted
  }

  func sendNext(
    memberID: Int64,
    at date: Date = Date()
  ) async throws -> RoutineSyncSendResult {
    // A stale account response deliberately leaves `.attempting` untouched.
    // Only a later sender turn performs this response-independent recovery.
    try repository.recoverInterruptedAttempts(at: date)
    _ = try repository.admitEligibleMutations(
      memberID: memberID,
      contract: contract,
      at: date
    )

    if let pendingReplay = try repository.mutations(memberID: memberID)
      .first(where: {
        $0.state == .needsReconciliation
          && $0.attempt != nil
          && contract.serverNamespace == $0.serverNamespace
          && contract.supports($0.operation)
      }) {
      guard isAuthorizedToTransmit(pendingReplay) else {
        return .consentRequired(mutationID: pendingReplay.id)
      }
      let prepared = try repository.prepareExactReplay(
        id: pendingReplay.id,
        expectedGenerationID: pendingReplay.attempt!.generationID,
        at: date
      )
      guard prepared else {
        let current = try repository.mutations(memberID: memberID).first {
          $0.id == pendingReplay.id
        }
        if let reason = current?.blockReason {
          return .blocked(mutationID: pendingReplay.id, reason: reason)
        }
        return .retryScheduled(
          mutationID: pendingReplay.id,
          nextAttemptAt: current?.nextAttemptAt
        )
      }
    }

    guard let mutation = try repository.mutations(memberID: memberID)
      .first(where: {
        $0.state == .queued
          && contract.serverNamespace == $0.serverNamespace
          && contract.supports($0.operation)
      }) else {
      return .idle
    }

    guard isAuthorizedToTransmit(mutation) else {
      return .consentRequired(mutationID: mutation.id)
    }

    let capturedIdentity = sessionIdentityProvider?.currentAccountSessionIdentity
    if sessionIdentityProvider != nil,
       capturedIdentity?.memberID != memberID {
      return .idle
    }

    let attempt: RoutineSyncAttempt?
    if let storedAttempt = mutation.attempt {
      attempt = try repository.claimForExactReplay(
        id: mutation.id,
        expectedGenerationID: storedAttempt.generationID,
        at: date
      )
    } else {
      let command = try decodedCommand(from: mutation.payload)
      let wireRequest: RoutineSyncWireRequest
      do {
        wireRequest = try requestPreparer.makeWireRequest(
          for: command,
          mutation: mutation
        )
      } catch {
        try repository.blockAttempt(
          id: mutation.id,
          expectedGenerationID: mutation.generationID,
          reason: .invalidStoredRequest,
          at: date
        )
        return .blocked(
          mutationID: mutation.id,
          reason: .invalidStoredRequest
        )
      }
      attempt = try repository.claimForDelivery(
        id: mutation.id,
        wireRequest: wireRequest,
        at: date
      )
    }
    guard let attempt else { return .idle }

    let request = try makeRequest(
      mutation: mutation,
      attempt: attempt,
      memberID: memberID,
      sessionIdentity: capturedIdentity
    )
    let outcome = await transport.execute(request)

    guard sessionIdentityProvider == nil
      || sessionIdentityProvider?.currentAccountSessionIdentity
        == capturedIdentity else {
      return .staleSession(mutationID: mutation.id)
    }

    return try resolve(
      outcome,
      mutation: mutation,
      attempt: attempt,
      sessionIdentity: capturedIdentity,
      at: date
    )
  }

  private func decodedCommand(from payload: Data) throws -> RoutineSyncCommand {
    do {
      return try JSONDecoder().decode(RoutineSyncCommand.self, from: payload)
    } catch {
      throw RoutineSyncSenderError.invalidAttemptPayload
    }
  }

  /// Group creation and routine addition can cause the server to derive
  /// timer steps or other routine content using Gemini. Do not even claim an
  /// Outbox attempt before consent: a claimed attempt is eligible for an
  /// automatic exact replay after an interruption.
  private func isAuthorizedToTransmit(_ mutation: RoutineSyncMutation) -> Bool {
    guard mutation.operation.requiresGeminiDataConsent else {
      return true
    }

    guard geminiDataConsent.hasExplicitGeminiDataConsent else {
      geminiDataConsent.requestGeminiDataConsentIfNeeded()
      return false
    }
    return true
  }

  private func makeRequest(
    mutation: RoutineSyncMutation,
    attempt: RoutineSyncAttempt,
    memberID: Int64,
    sessionIdentity: AccountSessionIdentity?
  ) throws -> RoutineSyncTransportRequest {
    let command = try decodedCommand(from: attempt.payload)
    guard command.operation == mutation.operation,
          command.entityKind == mutation.entityKind,
          command.localEntityID == mutation.localEntityID else {
      throw RoutineSyncSenderError.invalidAttemptPayload
    }
    guard let wireRequest = attempt.wireRequest else {
      throw RoutineSyncSenderError.invalidWireRequest
    }
    return RoutineSyncTransportRequest(
      serverNamespace: mutation.serverNamespace,
      memberID: memberID,
      operation: mutation.operation,
      command: command,
      idempotencyKey: attempt.generationID,
      generation: attempt.generation,
      payloadVersion: attempt.payloadVersion,
      wireRequest: wireRequest,
      sessionIdentity: sessionIdentity
    )
  }

  private func resolve(
    _ outcome: RoutineSyncTransportOutcome,
    mutation: RoutineSyncMutation,
    attempt: RoutineSyncAttempt,
    sessionIdentity: AccountSessionIdentity?,
    at date: Date
  ) throws -> RoutineSyncSendResult {
    switch outcome {
    case .ambiguous:
      try repository.markNeedsReconciliation(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )
      return .retryScheduled(mutationID: mutation.id, nextAttemptAt: nil)

    case .processingConflict:
      let retryAt = retryPolicy.retryDate(
        after: mutation.processingConflictCount,
        from: date
      )
      let scheduled = try repository.scheduleProcessingConflictReplay(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        retryAt: retryAt,
        maximumConflicts: retryPolicy.maximumConflicts,
        at: date
      )
      if scheduled {
        return .retryScheduled(
          mutationID: mutation.id,
          nextAttemptAt: retryAt
        )
      }
      return .blocked(
        mutationID: mutation.id,
        reason: .processingRetryExhausted
      )

    case .blocked(let reason):
      try repository.blockAttempt(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        reason: reason,
        at: date
      )
      return .blocked(mutationID: mutation.id, reason: reason)

    case .committed(let commit):
      try settle(
        commit,
        mutation: mutation,
        attempt: attempt,
        at: date
      )
      if mutation.operation == .completeOnboarding,
         let sessionIdentity {
        onOnboardingCompletionCommitted(sessionIdentity)
      }
      let remaining = try repository.mutations(memberID: mutation.memberID)
        .first { $0.id == mutation.id }
      if let reason = remaining?.blockReason {
        return .blocked(mutationID: mutation.id, reason: reason)
      }
      return .completed(mutationID: mutation.id)
    }
  }

  private func settle(
    _ commit: RoutineSyncTransportCommit,
    mutation: RoutineSyncMutation,
    attempt: RoutineSyncAttempt,
    at date: Date
  ) throws {
    switch (mutation.operation, commit) {
    case let (.createRoutineGroup, .createRoutineGroup(assignments)):
      try repository.completeCreateRoutineGroup(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        assignments: assignments,
        childMappingsComplete: true,
        at: date
      )

    case let (.addRoutine, .mutation(assignments)),
         let (.saveRoutineExecution, .mutation(assignments)):
      try repository.completeMutation(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        assignments: assignments,
        at: date
      )

    case let (.setRoutineGroupActive, .mutation(assignments)):
      try repository.completeMutation(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        assignments: assignments,
        at: date
      )
      logger.notice("setRoutineGroupActive committed")

    case (.deleteRoutineGroup, .deleted), (.deleteRoutine, .deleted):
      try repository.completeDelete(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )

    case (.completeOnboarding, .onboardingCompleted):
      try repository.removeCompleted(
        id: mutation.id,
        expectedGenerationID: attempt.generationID
      )

    default:
      throw RoutineSyncSenderError.unexpectedCommit(operation: mutation.operation)
    }
  }
}

nonisolated private extension RoutineSyncOperation {
  var requiresGeminiDataConsent: Bool {
    switch self {
    case .createRoutineGroup, .addRoutine:
      true
    case .deleteRoutineGroup,
         .deleteRoutine,
         .saveRoutineExecution,
         .setRoutineGroupActive,
         .completeOnboarding:
      false
    }
  }
}
