//
//  RoutineSyncSender.swift
//  Moru
//

import Foundation

nonisolated struct RoutineSyncTransportRequest: Equatable, Sendable {
  let serverNamespace: RoutineSyncServerNamespace
  let memberID: Int64
  let operation: RoutineSyncOperation
  let command: RoutineSyncCommand
  /// Exact Outbox generation ID. A future HTTP adapter sends this value as
  /// `Idempotency-Key` without generating another request identifier.
  let idempotencyKey: UUID
  let generation: Int
  let payloadVersion: Int
}

/// Key-only lookup for an ambiguous write. Keeping the original command out of
/// this type makes it impossible for a reconciliation adapter to resend the
/// mutation body by accident.
nonisolated struct RoutineSyncReconciliationRequest: Equatable, Sendable {
  let serverNamespace: RoutineSyncServerNamespace
  let memberID: Int64
  let operation: RoutineSyncOperation
  let idempotencyKey: UUID
  let generation: Int
}

nonisolated enum RoutineSyncTransportCommit: Equatable, Sendable {
  case createRoutineGroup(
    assignments: [RoutineServerBindingAssignment],
    childMappingsComplete: Bool
  )
  case mutation(assignments: [RoutineServerBindingAssignment])
  case completed
  case deleted
}

nonisolated enum RoutineSyncTransportOutcome: Equatable, Sendable {
  /// An authoritative write response or reconciliation lookup proved the exact
  /// generation committed and returned its server result.
  case committed(RoutineSyncTransportCommit)
  /// Server reconciliation proved the exact generation did not commit.
  case notCommitted
  /// Timeout, cancellation, decode failure, account change, or any other result
  /// where commit status cannot be proven.
  case ambiguous
}

nonisolated protocol RoutineSyncTransport: Sendable {
  func execute(
    _ request: RoutineSyncTransportRequest
  ) async throws -> RoutineSyncTransportOutcome

  func reconcile(
    _ request: RoutineSyncReconciliationRequest
  ) async throws -> RoutineSyncTransportOutcome
}

nonisolated enum RoutineSyncSenderError: Error, Equatable, Sendable {
  case invalidAttemptPayload
  case unexpectedCommit(operation: RoutineSyncOperation)
}

nonisolated enum RoutineSyncSendResult: Equatable, Sendable {
  case idle
  case completed(mutationID: UUID)
  case notCommitted(mutationID: UUID)
  case needsReconciliation(mutationID: UUID)
}

/// Contract-gated sender core. It has no production transport wiring while the
/// live server contract is unavailable, so adding this type cannot issue a
/// network request by itself.
@MainActor
final class RoutineSyncSender {
  private let repository: any RoutineSyncRepository
  private let transport: any RoutineSyncTransport
  private let contract: RoutineSyncServerContract

  init(
    repository: any RoutineSyncRepository,
    transport: any RoutineSyncTransport,
    contract: RoutineSyncServerContract
  ) {
    self.repository = repository
    self.transport = transport
    self.contract = contract
  }

  func sendNext(
    memberID: Int64,
    at date: Date = Date()
  ) async throws -> RoutineSyncSendResult {
    _ = try repository.admitEligibleMutations(
      memberID: memberID,
      contract: contract,
      at: date
    )
    guard let mutation = try repository.mutations(memberID: memberID).first(where: {
      $0.state == .queued
        && contract.serverNamespace == $0.serverNamespace
        && contract.supports($0.operation)
    }), let attempt = try repository.claimForDelivery(id: mutation.id, at: date) else {
      return .idle
    }

    let request: RoutineSyncTransportRequest
    do {
      request = try makeRequest(
        mutation: mutation,
        attempt: attempt,
        memberID: memberID
      )
    } catch {
      try repository.markNeedsReconciliation(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )
      throw error
    }

    let outcome: RoutineSyncTransportOutcome
    do {
      outcome = try await transport.execute(request)
    } catch {
      try repository.markNeedsReconciliation(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )
      return .needsReconciliation(mutationID: mutation.id)
    }

    return try resolve(
      outcome,
      mutation: mutation,
      attempt: attempt,
      at: date
    )
  }

  /// Looks up one ambiguous attempt by its idempotency key. This method never
  /// resends the original mutation; only a proven `notCommitted` result can
  /// release that generation for future admission.
  func reconcileNext(
    memberID: Int64,
    at date: Date = Date()
  ) async throws -> RoutineSyncSendResult {
    guard let mutation = try repository.mutations(memberID: memberID).first(where: {
      $0.state == .needsReconciliation
        && $0.attempt != nil
        && contract.serverNamespace == $0.serverNamespace
        && contract.supports($0.operation)
    }), let attempt = mutation.attempt else {
      return .idle
    }
    let attemptedRequest = try makeRequest(
      mutation: mutation,
      attempt: attempt,
      memberID: memberID
    )
    let request = RoutineSyncReconciliationRequest(
      serverNamespace: attemptedRequest.serverNamespace,
      memberID: attemptedRequest.memberID,
      operation: attemptedRequest.operation,
      idempotencyKey: attemptedRequest.idempotencyKey,
      generation: attemptedRequest.generation
    )
    let outcome: RoutineSyncTransportOutcome
    do {
      outcome = try await transport.reconcile(request)
    } catch {
      return .needsReconciliation(mutationID: mutation.id)
    }
    return try resolve(
      outcome,
      mutation: mutation,
      attempt: attempt,
      at: date
    )
  }

  private func makeRequest(
    mutation: RoutineSyncMutation,
    attempt: RoutineSyncAttempt,
    memberID: Int64
  ) throws -> RoutineSyncTransportRequest {
    let command = try JSONDecoder().decode(RoutineSyncCommand.self, from: attempt.payload)
    guard command.operation == mutation.operation,
          command.entityKind == mutation.entityKind,
          command.localEntityID == mutation.localEntityID else {
      throw RoutineSyncSenderError.invalidAttemptPayload
    }
    return RoutineSyncTransportRequest(
      serverNamespace: mutation.serverNamespace,
      memberID: memberID,
      operation: mutation.operation,
      command: command,
      idempotencyKey: attempt.generationID,
      generation: attempt.generation,
      payloadVersion: attempt.payloadVersion
    )
  }

  private func resolve(
    _ outcome: RoutineSyncTransportOutcome,
    mutation: RoutineSyncMutation,
    attempt: RoutineSyncAttempt,
    at date: Date
  ) throws -> RoutineSyncSendResult {
    switch outcome {
    case .ambiguous:
      try repository.markNeedsReconciliation(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )
      return .needsReconciliation(mutationID: mutation.id)

    case .notCommitted:
      try repository.resolveNotCommitted(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )
      return .notCommitted(mutationID: mutation.id)

    case .committed(let commit):
      do {
        try settle(
          commit,
          mutation: mutation,
          attempt: attempt,
          at: date
        )
        let remaining = try repository.mutations(memberID: mutation.memberID).first {
          $0.id == mutation.id
        }
        if remaining?.state == .needsReconciliation {
          return .needsReconciliation(mutationID: mutation.id)
        }
        return .completed(mutationID: mutation.id)
      } catch {
        try? repository.markNeedsReconciliation(
          id: mutation.id,
          expectedGenerationID: attempt.generationID,
          at: date
        )
        throw error
      }
    }
  }

  private func settle(
    _ commit: RoutineSyncTransportCommit,
    mutation: RoutineSyncMutation,
    attempt: RoutineSyncAttempt,
    at date: Date
  ) throws {
    switch (mutation.operation, commit) {
    case let (.createRoutineGroup, .createRoutineGroup(assignments, childMappingsComplete)):
      try repository.completeCreateRoutineGroup(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        assignments: assignments,
        childMappingsComplete: childMappingsComplete,
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

    case (.setRoutineGroupActive, .completed):
      try repository.removeCompleted(
        id: mutation.id,
        expectedGenerationID: attempt.generationID
      )

    case (.deleteRoutineGroup, .deleted), (.deleteRoutine, .deleted):
      try repository.completeDelete(
        id: mutation.id,
        expectedGenerationID: attempt.generationID,
        at: date
      )

    default:
      throw RoutineSyncSenderError.unexpectedCommit(operation: mutation.operation)
    }
  }
}
