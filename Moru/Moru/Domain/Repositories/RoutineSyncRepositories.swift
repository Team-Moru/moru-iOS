//
//  RoutineSyncRepositories.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineSyncRepository: AnyObject {
  func binding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineServerBinding?

  /// Creates a binding after the server returns an ID. A different remote ID is
  /// treated as a conflict instead of silently
  /// replacing identity. Rebinding needs an explicit future reconciliation flow.
  func recordRemoteID(
    _ remoteID: Int64,
    revision: String?,
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID,
    at date: Date
  ) throws -> RoutineServerBinding

  /// Validates every forward and reverse identity pair before changing any
  /// row, then saves the complete aggregate in one SwiftData transaction.
  func recordRemoteIDs(
    _ assignments: [RoutineServerBindingAssignment],
    memberID: Int64,
    at date: Date
  ) throws -> [RoutineServerBinding]

  /// Stage-only variants intentionally never call save or rollback. Callers
  /// composing a local CRUD change with an Outbox intent own the one commit.
  func stageRecordRemoteIDs(
    _ assignments: [RoutineServerBindingAssignment],
    memberID: Int64,
    at date: Date
  ) throws -> [RoutineServerBinding]

  /// Exact duplicate payloads reuse one generationID. A changed payload for
  /// the same operation/entity coalesces and creates a new generation.
  @discardableResult
  func enqueue(
    _ mutation: EnqueuedRoutineSyncMutation,
    at date: Date
  ) throws -> RoutineSyncMutation

  @discardableResult
  func enqueue(
    command: RoutineSyncCommand,
    memberID: Int64,
    at date: Date
  ) throws -> RoutineSyncMutation

  @discardableResult
  func stageEnqueue(
    _ mutation: EnqueuedRoutineSyncMutation,
    at date: Date
  ) throws -> RoutineSyncMutation

  func mutations(memberID: Int64) throws -> [RoutineSyncMutation]

  /// Read and cancellation helpers are stage-only: they never save or roll
  /// back the shared context owned by a local CRUD repository.
  func mutation(
    memberID: Int64,
    operation: RoutineSyncOperation,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineSyncMutation?

  @discardableResult
  func stageCancel(
    memberID: Int64,
    operation: RoutineSyncOperation,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> Bool

  @discardableResult
  func stageCancelActiveSelection(
    memberID: Int64,
    selectedGroupLocalID: UUID
  ) throws -> Bool

  /// Only changes the generation that was actually attempted. A late result
  /// cannot overwrite a newer coalesced mutation.
  func markNeedsReconciliation(
    id: UUID,
    expectedGenerationID: UUID,
    at date: Date
  ) throws

  /// Claims only a row already admitted to delivery. Current production rows
  /// are never admitted, so this API cannot itself trigger network activity.
  func claimForDelivery(
    id: UUID,
    at date: Date
  ) throws -> RoutineSyncAttempt?

  func recoverInterruptedAttempts(at date: Date) throws

  /// Resolves a create response in the same save as its bindings. `false`
  /// permits a verified group-only binding but leaves the mutation requiring
  /// reconciliation instead of guessing child IDs.
  func completeCreateRoutineGroup(
    id: UUID,
    expectedGenerationID: UUID,
    assignments: [RoutineServerBindingAssignment],
    childMappingsComplete: Bool,
    at date: Date
  ) throws

  /// Settles a child creation or one RoutineStepResult execution binding and
  /// its outbox row together. It is not a server sender.
  func completeMutation(
    id: UUID,
    expectedGenerationID: UUID,
    assignments: [RoutineServerBindingAssignment],
    at date: Date
  ) throws

  /// Resolves a delete response in the same save as binding cleanup.
  func completeDelete(
    id: UUID,
    expectedGenerationID: UUID,
    at date: Date
  ) throws

  func removeCompleted(
    id: UUID,
    expectedGenerationID: UUID
  ) throws

  func removeAccountScopedData(memberID: Int64) throws

  func preparePendingAccountCleanup(memberID: Int64, at date: Date) throws
  func beginPendingAccountCleanupAttempt(memberID: Int64) throws
  func confirmPendingAccountCleanup(memberID: Int64) throws
  func cancelPendingAccountCleanup(memberID: Int64) throws
  func completePendingAccountCleanup(memberID: Int64) throws
  func finalizePendingAccountCleanup(memberID: Int64) throws
  func recoverPendingAccountCleanups() throws -> [Int64]
  func pendingAccountCleanupRecovery() throws -> PendingAccountCleanupRecovery
}
