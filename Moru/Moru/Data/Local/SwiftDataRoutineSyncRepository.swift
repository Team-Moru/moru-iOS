//
//  SwiftDataRoutineSyncRepository.swift
//  Moru
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataRoutineSyncRepository: RoutineSyncRepository {
  private let modelContext: ModelContext
  private let retainedModelContainer: ModelContainer?
  private let serverNamespace: RoutineSyncServerNamespace

  init(
    modelContext: ModelContext,
    serverNamespace: RoutineSyncServerNamespace = .production
  ) {
    self.modelContext = modelContext
    retainedModelContainer = nil
    self.serverNamespace = serverNamespace
  }

  init(
    modelContainer: ModelContainer,
    serverNamespace: RoutineSyncServerNamespace = .production
  ) {
    modelContext = modelContainer.mainContext
    retainedModelContainer = modelContainer
    self.serverNamespace = serverNamespace
  }

  func binding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineServerBinding? {
    try validate(memberID: memberID)
    return try persistedBinding(
      key: bindingKey(
        memberID: memberID,
        entityKind: entityKind,
        localEntityID: localEntityID
      )
    ).map(makeBinding)
  }

  func recordRemoteID(
    _ remoteID: Int64,
    revision: String?,
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID,
    at date: Date = Date()
  ) throws -> RoutineServerBinding {
    guard let binding = try recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: entityKind,
          localEntityID: localEntityID,
          remoteID: remoteID,
          remoteRevision: revision
        )
      ],
      memberID: memberID,
      at: date
    ).first else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "RoutineServerBindingAssignment"
      )
    }
    return binding
  }

  func recordRemoteIDs(
    _ assignments: [RoutineServerBindingAssignment],
    memberID: Int64,
    at date: Date = Date()
  ) throws -> [RoutineServerBinding] {
    do {
      let bindings = try stageRecordRemoteIDs(assignments, memberID: memberID, at: date)
      try modelContext.save()
      return bindings
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  /// This method is deliberately save-free. It is used by a future CRUD
  /// composer so local SwiftData rows and their intent share one transaction.
  func stageRecordRemoteIDs(
    _ assignments: [RoutineServerBindingAssignment],
    memberID: Int64,
    at date: Date = Date()
  ) throws -> [RoutineServerBinding] {
    try validate(memberID: memberID)
    guard !assignments.isEmpty else { return [] }

    var assignmentsByLocalKey: [String: RoutineServerBindingAssignment] = [:]
    var assignmentsByRemoteKey: [String: RoutineServerBindingAssignment] = [:]
    for assignment in assignments {
      try validate(assignment: assignment)
      let localKey = bindingKey(
        memberID: memberID,
        entityKind: assignment.entityKind,
        localEntityID: assignment.localEntityID
      )
      guard assignmentsByLocalKey[localKey] == nil else {
        throw RoutineSyncRepositoryError.duplicateBindingAssignment(
          entityKind: assignment.entityKind,
          localEntityID: assignment.localEntityID
        )
      }
      assignmentsByLocalKey[localKey] = assignment

      let remoteKey = remoteBindingKey(
        memberID: memberID,
        entityKind: assignment.entityKind,
        remoteID: assignment.remoteID
      )
      if let existing = assignmentsByRemoteKey[remoteKey],
         existing.localEntityID != assignment.localEntityID {
        throw RoutineSyncRepositoryError.remoteIDAlreadyBound(
          remoteID: assignment.remoteID,
          localEntityID: existing.localEntityID
        )
      }
      assignmentsByRemoteKey[remoteKey] = assignment
    }

    let stored = try persistedBindings(memberID: memberID)
    _ = try stored.map(makeBinding)
    let storedByLocalKey = Dictionary(uniqueKeysWithValues: stored.map { ($0.bindingKey, $0) })
    let storedByRemoteKey = Dictionary(uniqueKeysWithValues: stored.map { ($0.remoteBindingKey, $0) })

    for assignment in assignments {
      let localKey = bindingKey(
        memberID: memberID,
        entityKind: assignment.entityKind,
        localEntityID: assignment.localEntityID
      )
      if let existing = storedByLocalKey[localKey], existing.remoteID != assignment.remoteID {
        throw RoutineSyncRepositoryError.remoteIDConflict(
          existing: existing.remoteID,
          incoming: assignment.remoteID
        )
      }
      let remoteKey = remoteBindingKey(
        memberID: memberID,
        entityKind: assignment.entityKind,
        remoteID: assignment.remoteID
      )
      if let existing = storedByRemoteKey[remoteKey],
         existing.localEntityID != assignment.localEntityID {
        throw RoutineSyncRepositoryError.remoteIDAlreadyBound(
          remoteID: assignment.remoteID,
          localEntityID: existing.localEntityID
        )
      }
    }

    var results: [PersistedRoutineServerBinding] = []
    for assignment in assignments {
      let localKey = bindingKey(
        memberID: memberID,
        entityKind: assignment.entityKind,
        localEntityID: assignment.localEntityID
      )
      let persisted: PersistedRoutineServerBinding
      if let existing = storedByLocalKey[localKey] {
        persisted = existing
      } else {
        persisted = PersistedRoutineServerBinding(
          bindingKey: localKey,
          remoteBindingKey: remoteBindingKey(
            memberID: memberID,
            entityKind: assignment.entityKind,
            remoteID: assignment.remoteID
          ),
          id: UUID(),
          serverNamespaceRawValue: serverNamespace.rawValue,
          memberID: memberID,
          entityKindRawValue: assignment.entityKind.rawValue,
          localEntityID: assignment.localEntityID,
          remoteID: assignment.remoteID,
          remoteRevision: normalized(assignment.remoteRevision),
          parentEntityKindRawValue: assignment.parentEntityKind?.rawValue,
          parentLocalEntityID: assignment.parentLocalEntityID,
          createdAt: date,
          updatedAt: date
        )
        modelContext.insert(persisted)
      }
      // nil is intentionally "no new revision", not "erase the revision".
      if let revision = normalized(assignment.remoteRevision) {
        persisted.remoteRevision = revision
      }
      if let parentKind = assignment.parentEntityKind {
        persisted.parentEntityKindRawValue = parentKind.rawValue
        persisted.parentLocalEntityID = assignment.parentLocalEntityID
      }
      persisted.updatedAt = date
      results.append(persisted)
    }
    return try results.map(makeBinding)
  }

  @discardableResult
  func enqueue(
    _ mutation: EnqueuedRoutineSyncMutation,
    at date: Date = Date()
  ) throws -> RoutineSyncMutation {
    do {
      let result = try stageEnqueue(mutation, at: date)
      try modelContext.save()
      return result
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @discardableResult
  func enqueue(
    command: RoutineSyncCommand,
    memberID: Int64,
    at date: Date = Date()
  ) throws -> RoutineSyncMutation {
    try enqueue(
      EnqueuedRoutineSyncMutation(memberID: memberID, command: command),
      at: date
    )
  }

  @discardableResult
  func stageEnqueue(
    _ mutation: EnqueuedRoutineSyncMutation,
    at date: Date = Date()
  ) throws -> RoutineSyncMutation {
    try validate(memberID: mutation.memberID)
    guard mutation.payloadVersion > 0 else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    guard mutation.operation.accepts(mutation.entityKind) else {
      throw RoutineSyncRepositoryError.invalidOperationEntityCombination
    }
    let payload = try canonicalPayload(mutation.payload)
    let key = operationKey(
      memberID: mutation.memberID,
      operation: mutation.operation,
      entityKind: mutation.entityKind,
      localEntityID: mutation.localEntityID
    )

    if let persisted = try persistedMutation(key: key) {
      if persisted.payloadVersion == mutation.payloadVersion, persisted.payload == payload {
        return try makeMutation(persisted)
      }
      if persisted.stateRawValue == RoutineSyncMutationState.needsReconciliation.rawValue,
         try makeAttempt(persisted) == nil {
        throw RoutineSyncRepositoryError.reconciliationRequired(existingMutationID: persisted.id)
      }

      persisted.payload = payload
      persisted.payloadVersion = mutation.payloadVersion
      persisted.generationID = UUID()
      persisted.generation = max(1, persisted.generation + 1)
      // An older snapshot is still in-flight. Do not overwrite it or make the
      // newer desired value deliverable until that result is settled.
      if persisted.stateRawValue != RoutineSyncMutationState.attempting.rawValue,
         persisted.stateRawValue != RoutineSyncMutationState.needsReconciliation.rawValue {
        persisted.stateRawValue = initialState(for: mutation.operation).rawValue
      }
      persisted.updatedAt = date
      return try makeMutation(persisted)
    }

    let persisted = PersistedRoutineSyncMutation(
      operationKey: key,
      id: UUID(),
      serverNamespaceRawValue: serverNamespace.rawValue,
      memberID: mutation.memberID,
      operationRawValue: mutation.operation.rawValue,
      entityKindRawValue: mutation.entityKind.rawValue,
      localEntityID: mutation.localEntityID,
      generationID: UUID(),
      generation: 1,
      payloadVersion: mutation.payloadVersion,
      payload: payload,
      stateRawValue: initialState(for: mutation.operation).rawValue,
      createdAt: date,
      updatedAt: date
    )
    modelContext.insert(persisted)
    return try makeMutation(persisted)
  }

  func mutations(memberID: Int64) throws -> [RoutineSyncMutation] {
    try validate(memberID: memberID)
    return try persistedMutations(memberID: memberID).map(makeMutation).sorted {
      $0.createdAt == $1.createdAt
        ? $0.id.uuidString < $1.id.uuidString
        : $0.createdAt < $1.createdAt
    }
  }

  func mutation(
    memberID: Int64,
    operation: RoutineSyncOperation,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineSyncMutation? {
    try validate(memberID: memberID)
    let key = operationKey(
      memberID: memberID,
      operation: operation,
      entityKind: entityKind,
      localEntityID: localEntityID
    )
    return try persistedMutation(key: key).map(makeMutation)
  }

  @discardableResult
  func stageCancel(
    memberID: Int64,
    operation: RoutineSyncOperation,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> Bool {
    try validate(memberID: memberID)
    guard operation.accepts(entityKind) else {
      throw RoutineSyncRepositoryError.invalidOperationEntityCombination
    }
    let key = operationKey(
      memberID: memberID,
      operation: operation,
      entityKind: entityKind,
      localEntityID: localEntityID
    )
    guard let persisted = try persistedMutation(key: key) else { return false }
    switch try makeMutation(persisted).state {
    case .waitingForServerContract, .queued:
      modelContext.delete(persisted)
      return true
    case .attempting, .needsReconciliation:
      throw RoutineSyncRepositoryError.reconciliationRequired(
        existingMutationID: persisted.id
      )
    }
  }

  @discardableResult
  func stageCancelActiveSelection(
    memberID: Int64,
    selectedGroupLocalID: UUID
  ) throws -> Bool {
    try validate(memberID: memberID)
    let key = operationKey(
      memberID: memberID,
      operation: .setRoutineGroupActive,
      entityKind: .account,
      localEntityID: RoutineSyncCommand.accountSelectionID
    )
    guard let persisted = try persistedMutation(key: key) else { return false }
    guard case .selectActiveRoutineGroup(let selected) = try typedCommand(
      from: persisted.payload
    ), selected == selectedGroupLocalID else {
      return false
    }
    switch try makeMutation(persisted).state {
    case .waitingForServerContract, .queued:
      modelContext.delete(persisted)
      return true
    case .attempting, .needsReconciliation:
      throw RoutineSyncRepositoryError.reconciliationRequired(
        existingMutationID: persisted.id
      )
    }
  }

  func claimForDelivery(id: UUID, at date: Date = Date()) throws -> RoutineSyncAttempt? {
    guard let persisted = try persistedMutation(id: id),
          persisted.stateRawValue == RoutineSyncMutationState.queued.rawValue else {
      return nil
    }
    let attempt = RoutineSyncAttempt(
      generationID: persisted.generationID,
      generation: persisted.generation,
      payloadVersion: persisted.payloadVersion,
      payload: persisted.payload,
      attemptedAt: date
    )
    persisted.attemptedGenerationID = attempt.generationID
    persisted.attemptedGeneration = attempt.generation
    persisted.attemptedPayloadVersion = attempt.payloadVersion
    persisted.attemptedPayload = attempt.payload
    persisted.attemptedAt = attempt.attemptedAt
    persisted.stateRawValue = RoutineSyncMutationState.attempting.rawValue
    persisted.updatedAt = date
    try saveOrRollback()
    return attempt
  }

  func admitEligibleMutations(
    memberID: Int64,
    contract: RoutineSyncServerContract,
    at date: Date = Date()
  ) throws -> [RoutineSyncMutation] {
    try validate(memberID: memberID)
    guard contract.serverNamespace == serverNamespace else { return [] }
    let persisted = try persistedMutations(memberID: memberID)
    _ = try persisted.map(makeMutation)
    var admitted: [PersistedRoutineSyncMutation] = []
    do {
      for mutation in persisted {
        guard mutation.stateRawValue == RoutineSyncMutationState.waitingForServerContract.rawValue,
              let operation = RoutineSyncOperation(rawValue: mutation.operationRawValue),
              contract.supports(operation),
              try dependenciesAreSatisfied(for: mutation, among: persisted, memberID: memberID)
        else { continue }
        mutation.stateRawValue = RoutineSyncMutationState.queued.rawValue
        mutation.updatedAt = date
        admitted.append(mutation)
      }
      guard !admitted.isEmpty else { return [] }
      try modelContext.save()
      return try admitted.map(makeMutation).sorted {
        $0.createdAt == $1.createdAt
          ? $0.id.uuidString < $1.id.uuidString
          : $0.createdAt < $1.createdAt
      }
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func recoverInterruptedAttempts(at date: Date = Date()) throws {
    let attempting = try allPersistedMutations().filter {
      $0.stateRawValue == RoutineSyncMutationState.attempting.rawValue
    }
    guard !attempting.isEmpty else { return }
    do {
      for mutation in attempting {
        _ = try makeAttempt(mutation)
        mutation.stateRawValue = RoutineSyncMutationState.needsReconciliation.rawValue
        mutation.updatedAt = date
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func markNeedsReconciliation(
    id: UUID,
    expectedGenerationID: UUID,
    at date: Date = Date()
  ) throws {
    guard let persisted = try persistedMutation(id: id),
          matchesAttemptOrCurrent(persisted, expectedGenerationID: expectedGenerationID)
    else { return }
    persisted.stateRawValue = RoutineSyncMutationState.needsReconciliation.rawValue
    persisted.updatedAt = date
    try saveOrRollback()
  }

  func resolveNotCommitted(
    id: UUID,
    expectedGenerationID: UUID,
    at date: Date = Date()
  ) throws {
    guard let persisted = try persistedMutation(id: id),
          persisted.attemptedGenerationID == expectedGenerationID,
          try makeAttempt(persisted) != nil else { return }
    do {
      let operation = try operation(of: persisted)
      switch operation {
      case .createRoutineGroup:
        if try hasDeleteSuccessor(
          operation: .deleteRoutineGroup,
          localEntityID: persisted.localEntityID,
          among: try persistedMutations(memberID: persisted.memberID)
        ) {
          try stageDiscardNeverCommittedGroup(
            memberID: persisted.memberID,
            groupLocalID: persisted.localEntityID
          )
          try modelContext.save()
          return
        }
        guard case .createRoutineGroup(let desired) = try typedCommand(
          from: persisted.payload
        ) else {
          throw RoutineSyncRepositoryError.invalidPayload
        }
        try stageDiscardUnprojectableExecutions(
          memberID: persisted.memberID,
          groupLocalID: desired.localID,
          desiredRoutineLocalIDs: Set(desired.routines.map(\.localID))
        )
      case .addRoutine:
        if try hasDeleteSuccessor(
          operation: .deleteRoutine,
          localEntityID: persisted.localEntityID,
          among: try persistedMutations(memberID: persisted.memberID)
        ) {
          try stageDiscardNeverCommittedRoutine(
            memberID: persisted.memberID,
            routineLocalID: persisted.localEntityID
          )
          try modelContext.save()
          return
        }
      case .setRoutineGroupActive, .deleteRoutineGroup, .deleteRoutine,
           .saveRoutineExecution:
        break
      }
      clearAttempt(persisted)
      persisted.stateRawValue = initialState(for: operation).rawValue
      persisted.updatedAt = date
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func removeCompleted(id: UUID, expectedGenerationID: UUID) throws {
    guard let persisted = try persistedMutation(id: id) else { return }
    guard matchesAttemptOrCurrent(persisted, expectedGenerationID: expectedGenerationID) else {
      return
    }
    do {
      try stageResolveCompleted(persisted, expectedGenerationID: expectedGenerationID)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func completeCreateRoutineGroup(
    id: UUID,
    expectedGenerationID: UUID,
    assignments: [RoutineServerBindingAssignment],
    childMappingsComplete: Bool,
    at date: Date = Date()
  ) throws {
    guard let persisted = try persistedMutation(id: id),
          persisted.operationRawValue == RoutineSyncOperation.createRoutineGroup.rawValue,
          matchesAttemptOrCurrent(persisted, expectedGenerationID: expectedGenerationID)
    else { return }
    do {
      let bindings = try stageRecordRemoteIDs(assignments, memberID: persisted.memberID, at: date)
      try validateCreateRoutineGroupSettlement(
        mutation: persisted,
        expectedGenerationID: expectedGenerationID,
        bindings: bindings,
        childMappingsComplete: childMappingsComplete
      )
      if childMappingsComplete {
        try stageCreateSuccessorIntents(
          mutation: persisted,
          expectedGenerationID: expectedGenerationID,
          at: date
        )
        try stageResolveCompleted(persisted, expectedGenerationID: expectedGenerationID)
      } else {
        // A group ID alone is useful, but title/order matching child IDs would
        // be a guess. Keep this row for server-backed reconciliation.
        persisted.stateRawValue = RoutineSyncMutationState.needsReconciliation.rawValue
        persisted.updatedAt = date
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func completeDelete(
    id: UUID,
    expectedGenerationID: UUID,
    at date: Date = Date()
  ) throws {
    guard let persisted = try persistedMutation(id: id),
          let operation = RoutineSyncOperation(rawValue: persisted.operationRawValue),
          operation == .deleteRoutineGroup || operation == .deleteRoutine,
          matchesAttemptOrCurrent(persisted, expectedGenerationID: expectedGenerationID)
    else { return }
    do {
      switch operation {
      case .deleteRoutineGroup:
        try stageDeleteGroupBindingTree(memberID: persisted.memberID, groupLocalID: persisted.localEntityID)
      case .deleteRoutine:
        try stageDeleteBinding(
          memberID: persisted.memberID,
          entityKind: .routine,
          localEntityID: persisted.localEntityID
        )
      default:
        break
      }
      try stageResolveCompleted(persisted, expectedGenerationID: expectedGenerationID)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func completeMutation(
    id: UUID,
    expectedGenerationID: UUID,
    assignments: [RoutineServerBindingAssignment],
    at date: Date = Date()
  ) throws {
    guard let persisted = try persistedMutation(id: id),
          let operation = RoutineSyncOperation(rawValue: persisted.operationRawValue),
          operation == .addRoutine || operation == .saveRoutineExecution,
          matchesAttemptOrCurrent(persisted, expectedGenerationID: expectedGenerationID)
    else { return }
    do {
      let bindings = try stageRecordRemoteIDs(assignments, memberID: persisted.memberID, at: date)
      try validateAtomicSettlement(
        operation: operation,
        mutation: persisted,
        expectedGenerationID: expectedGenerationID,
        bindings: bindings
      )
      try stageResolveCompleted(persisted, expectedGenerationID: expectedGenerationID)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func removeAccountScopedData(memberID: Int64) throws {
    try validate(memberID: memberID)
    do {
      try stageDeleteAccountScopedData(memberID: memberID)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func preparePendingAccountCleanup(memberID: Int64, at date: Date = Date()) throws {
    try validate(memberID: memberID)
    do {
      if let existing = try pendingCleanup(memberID: memberID) {
        guard existing.phaseRawValue == PendingAccountCleanupPhase.cancelled.rawValue else {
          return
        }
        modelContext.delete(existing)
      }
      modelContext.insert(
        PersistedPendingAccountCleanup(
          cleanupKey: cleanupKey(memberID: memberID),
          id: UUID(),
          serverNamespaceRawValue: serverNamespace.rawValue,
          memberID: memberID,
          phaseRawValue: PendingAccountCleanupPhase.prepared.rawValue,
          createdAt: date
        )
      )
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func beginPendingAccountCleanupAttempt(memberID: Int64) throws {
    guard let marker = try pendingCleanup(memberID: memberID),
          marker.phaseRawValue == PendingAccountCleanupPhase.prepared.rawValue else {
      throw RoutineSyncRepositoryError.missingPendingAccountCleanup
    }
    marker.phaseRawValue = PendingAccountCleanupPhase.attempting.rawValue
    try saveOrRollback()
  }

  func confirmPendingAccountCleanup(memberID: Int64) throws {
    guard let marker = try pendingCleanup(memberID: memberID),
          marker.phaseRawValue == PendingAccountCleanupPhase.attempting.rawValue else {
      throw RoutineSyncRepositoryError.missingPendingAccountCleanup
    }
    marker.phaseRawValue = PendingAccountCleanupPhase.remoteConfirmed.rawValue
    try saveOrRollback()
  }

  func cancelPendingAccountCleanup(memberID: Int64) throws {
    guard let marker = try pendingCleanup(memberID: memberID) else { return }
    guard marker.phaseRawValue == PendingAccountCleanupPhase.prepared.rawValue
      || marker.phaseRawValue == PendingAccountCleanupPhase.attempting.rawValue
    else { return }
    marker.phaseRawValue = PendingAccountCleanupPhase.cancelled.rawValue
    try saveOrRollback()
  }

  func completePendingAccountCleanup(memberID: Int64) throws {
    guard let marker = try pendingCleanup(memberID: memberID),
          marker.phaseRawValue == PendingAccountCleanupPhase.remoteConfirmed.rawValue else {
      throw RoutineSyncRepositoryError.missingPendingAccountCleanup
    }
    do {
      try stageDeleteAccountScopedData(memberID: memberID)
      // Keep the durable handoff until the matching Keychain credentials are
      // actually gone. Deleting it here creates a crash restoration window.
      marker.phaseRawValue = PendingAccountCleanupPhase.localDataCleaned.rawValue
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func finalizePendingAccountCleanup(memberID: Int64) throws {
    guard let marker = try pendingCleanup(memberID: memberID),
          marker.phaseRawValue == PendingAccountCleanupPhase.localDataCleaned.rawValue else {
      throw RoutineSyncRepositoryError.missingPendingAccountCleanup
    }
    modelContext.delete(marker)
    try saveOrRollback()
  }

  func recoverPendingAccountCleanups() throws -> [Int64] {
    let markers = try pendingCleanups()
    let confirmed = markers.filter {
      $0.phaseRawValue == PendingAccountCleanupPhase.remoteConfirmed.rawValue
    }
    let localDataCleaned = markers.filter {
      $0.phaseRawValue == PendingAccountCleanupPhase.localDataCleaned.rawValue
    }
    let safeToDiscard = markers.filter {
      $0.phaseRawValue == PendingAccountCleanupPhase.prepared.rawValue
        || $0.phaseRawValue == PendingAccountCleanupPhase.cancelled.rawValue
    }
    guard !confirmed.isEmpty || !safeToDiscard.isEmpty else {
      return localDataCleaned.map(\.memberID).sorted()
    }
    do {
      for marker in confirmed {
        try stageDeleteAccountScopedData(memberID: marker.memberID)
        marker.phaseRawValue = PendingAccountCleanupPhase.localDataCleaned.rawValue
      }
      safeToDiscard.forEach(modelContext.delete)
      try modelContext.save()
      return (confirmed.map(\.memberID) + localDataCleaned.map(\.memberID)).sorted()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func pendingAccountCleanupRecovery() throws -> PendingAccountCleanupRecovery {
    let before = try pendingCleanups()
    let hasAmbiguousAttempt = before.contains {
      $0.phaseRawValue == PendingAccountCleanupPhase.attempting.rawValue
    }
    let ambiguousMemberIDs = before.filter {
      $0.phaseRawValue == PendingAccountCleanupPhase.attempting.rawValue
    }.map(\.memberID).sorted()
    let completed = try recoverPendingAccountCleanups()
    return PendingAccountCleanupRecovery(
      completedMemberIDs: completed,
      ambiguousMemberIDs: hasAmbiguousAttempt ? ambiguousMemberIDs : []
    )
  }

  private func stageResolveCompleted(
    _ persisted: PersistedRoutineSyncMutation,
    expectedGenerationID: UUID
  ) throws {
    if persisted.generationID == expectedGenerationID {
      modelContext.delete(persisted)
      return
    }
    guard persisted.attemptedGenerationID == expectedGenerationID else { return }
    let operation = try operation(of: persisted)
    if operation == .createRoutineGroup || operation == .addRoutine {
      // The old create committed remotely. A newer local title/schedule/step
      // snapshot has no PATCH contract, so never send a second create. Local
      // SwiftData remains the projection; the attempted successor is dropped.
      modelContext.delete(persisted)
      return
    }
    clearAttempt(persisted)
    // The old request settled. The newer coalesced desired value is now the
    // only outstanding intent, even if a prior ambiguity had paused it.
    persisted.stateRawValue = initialState(for: operation).rawValue
  }

  private func validateCreateRoutineGroupSettlement(
    mutation: PersistedRoutineSyncMutation,
    expectedGenerationID: UUID,
    bindings: [RoutineServerBinding],
    childMappingsComplete: Bool
  ) throws {
    let payload = try payload(for: mutation, expectedGenerationID: expectedGenerationID)
    guard let command = try? JSONDecoder().decode(RoutineSyncCommand.self, from: payload) else {
      return // Compatibility rows have no child UUID contract to validate.
    }
    guard case .createRoutineGroup(let group) = command else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    guard group.localID == mutation.localEntityID else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    let groupBindings = bindings.filter { $0.entityKind == .routineGroup }
    guard groupBindings.count == 1,
          groupBindings[0].localEntityID == group.localID,
          groupBindings[0].parentEntityKind == nil,
          groupBindings[0].parentLocalEntityID == nil else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    guard childMappingsComplete else {
      // A partial response may record only the group. Anything more would
      // falsely look like a complete child identity map.
      guard bindings.count == 1 else {
        throw RoutineSyncRepositoryError.incompleteChildMapping
      }
      return
    }
    let expectedChildIDs = Set(group.routines.map(\.localID))
    let childBindings = bindings.filter { $0.entityKind == .routine }
    guard group.routines.count == expectedChildIDs.count,
          bindings.count == 1 + expectedChildIDs.count,
          childBindings.count == expectedChildIDs.count,
          Set(childBindings.map(\.localEntityID)) == expectedChildIDs else {
      throw RoutineSyncRepositoryError.incompleteChildMapping
    }
    guard childBindings.allSatisfy({
      $0.parentEntityKind == .routineGroup && $0.parentLocalEntityID == group.localID
    }) else {
      throw RoutineSyncRepositoryError.invalidParentBinding
    }
  }

  private func validateAtomicSettlement(
    operation: RoutineSyncOperation,
    mutation: PersistedRoutineSyncMutation,
    expectedGenerationID: UUID,
    bindings: [RoutineServerBinding]
  ) throws {
    let payload = try payload(for: mutation, expectedGenerationID: expectedGenerationID)
    guard let command = try? JSONDecoder().decode(RoutineSyncCommand.self, from: payload) else {
      return // Legacy compatibility rows are never used by production CRUD.
    }
    switch (operation, command) {
    case (.addRoutine, .addRoutine(let groupLocalID, let routine)):
      guard bindings.count == 1,
            bindings[0].entityKind == .routine,
            bindings[0].localEntityID == routine.localID,
            bindings[0].parentEntityKind == .routineGroup,
            bindings[0].parentLocalEntityID == groupLocalID else {
        throw RoutineSyncRepositoryError.invalidParentBinding
      }
    case (.saveRoutineExecution, .saveRoutineExecution(let execution)):
      guard bindings.count == 1,
            bindings[0].entityKind == .routineExecution,
            bindings[0].localEntityID == execution.result.localID,
            bindings[0].parentEntityKind == .routine,
            bindings[0].parentLocalEntityID == execution.routineLocalID else {
        throw RoutineSyncRepositoryError.invalidParentBinding
      }
    default:
      throw RoutineSyncRepositoryError.invalidPayload
    }
  }

  /// A completed old create cannot be sent again merely because local state
  /// changed while it was in flight. Preserve only child structural drift that
  /// the server can express: additions become add requests and removed mapped
  /// children become deletes. All other edits remain local-only until PATCH.
  private func stageCreateSuccessorIntents(
    mutation: PersistedRoutineSyncMutation,
    expectedGenerationID: UUID,
    at date: Date
  ) throws {
    guard mutation.generationID != expectedGenerationID else { return }
    let attemptedPayload = try payload(
      for: mutation,
      expectedGenerationID: expectedGenerationID
    )
    guard case .createRoutineGroup(let attempted) = try typedCommand(
      from: attemptedPayload
    ), case .createRoutineGroup(let desired) = try typedCommand(
      from: mutation.payload
    ), attempted.localID == mutation.localEntityID,
      desired.localID == attempted.localID else {
      throw RoutineSyncRepositoryError.invalidPayload
    }

    let attemptedChildren = Dictionary(
      uniqueKeysWithValues: attempted.routines.map { ($0.localID, $0) }
    )
    let desiredChildren = Dictionary(
      uniqueKeysWithValues: desired.routines.map { ($0.localID, $0) }
    )
    for child in desired.routines where attemptedChildren[child.localID] == nil {
      _ = try stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: mutation.memberID,
          command: .addRoutine(groupLocalID: attempted.localID, routine: child)
        ),
        at: date
      )
    }
    for child in attempted.routines where desiredChildren[child.localID] == nil {
      guard let binding = try binding(
        memberID: mutation.memberID,
        entityKind: .routine,
        localEntityID: child.localID
      ), binding.parentEntityKind == .routineGroup,
         binding.parentLocalEntityID == attempted.localID else {
        throw RoutineSyncRepositoryError.incompleteChildMapping
      }
      _ = try stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: mutation.memberID,
          command: .deleteRoutine(
            groupLocalID: attempted.localID,
            routineLocalID: child.localID
          )
        ),
        at: date
      )
    }
  }

  private func dependenciesAreSatisfied(
    for mutation: PersistedRoutineSyncMutation,
    among mutations: [PersistedRoutineSyncMutation],
    memberID: Int64
  ) throws -> Bool {
    guard let command = try? typedCommand(from: mutation.payload) else {
      return false
    }
    let others = mutations.filter { $0.id != mutation.id }

    func hasMutation(
      operation: RoutineSyncOperation,
      entityKind: RoutineSyncEntityKind,
      localEntityID: UUID
    ) -> Bool {
      others.contains {
        $0.operationRawValue == operation.rawValue
          && $0.entityKindRawValue == entityKind.rawValue
          && $0.localEntityID == localEntityID
      }
    }

    func hasCreate(_ groupLocalID: UUID) -> Bool {
      hasMutation(
        operation: .createRoutineGroup,
        entityKind: .routineGroup,
        localEntityID: groupLocalID
      )
    }

    func hasExecution(groupLocalID: UUID? = nil, routineLocalID: UUID? = nil) -> Bool {
      others.contains { candidate in
        guard candidate.operationRawValue == RoutineSyncOperation.saveRoutineExecution.rawValue,
              case .saveRoutineExecution(let execution) = try? typedCommand(
                from: candidate.payload
              ) else { return false }
        return (groupLocalID == nil || execution.groupLocalID == groupLocalID)
          && (routineLocalID == nil || execution.routineLocalID == routineLocalID)
      }
    }

    switch command {
    case .createRoutineGroup(let group):
      return try binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: group.localID
      ) == nil

    case .addRoutine(let groupLocalID, _):
      guard !hasCreate(groupLocalID) else { return false }
      return try binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: groupLocalID
      ) != nil

    case .selectActiveRoutineGroup(let selectedGroupLocalID):
      guard let selectedGroupLocalID else { return true }
      guard !hasCreate(selectedGroupLocalID) else { return false }
      return try binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: selectedGroupLocalID
      ) != nil

    case .deleteRoutineGroup(let groupLocalID):
      guard !hasCreate(groupLocalID), try binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: groupLocalID
      ) != nil else { return false }
      for candidate in others {
        guard let otherCommand = try? typedCommand(from: candidate.payload) else {
          return false
        }
        switch otherCommand {
        case .addRoutine(let candidateGroupID, _) where candidateGroupID == groupLocalID:
          return false
        case .deleteRoutine(let candidateGroupID, let candidateRoutineID):
          if candidateGroupID == groupLocalID {
            return false
          }
          if candidateGroupID == nil,
             let childBinding = try binding(
               memberID: memberID,
               entityKind: .routine,
               localEntityID: candidateRoutineID
             ), childBinding.parentEntityKind == .routineGroup,
             childBinding.parentLocalEntityID == groupLocalID {
            return false
          }
        case .saveRoutineExecution(let execution) where execution.groupLocalID == groupLocalID:
          return false
        case .selectActiveRoutineGroup:
          return false
        default:
          continue
        }
      }
      return true

    case .deleteRoutine(let groupLocalID, let routineLocalID):
      guard let routineBinding = try binding(
        memberID: memberID,
        entityKind: .routine,
        localEntityID: routineLocalID
      ), !hasMutation(
        operation: .addRoutine,
        entityKind: .routine,
        localEntityID: routineLocalID
      ), !hasExecution(routineLocalID: routineLocalID) else { return false }
      if let groupLocalID {
        return !hasCreate(groupLocalID)
          && routineBinding.parentEntityKind == .routineGroup
          && routineBinding.parentLocalEntityID == groupLocalID
      }
      return true

    case .saveRoutineExecution(let execution):
      guard !hasCreate(execution.groupLocalID), !hasMutation(
        operation: .addRoutine,
        entityKind: .routine,
        localEntityID: execution.routineLocalID
      ) else { return false }
      guard let routineBinding = try binding(
        memberID: memberID,
        entityKind: .routine,
        localEntityID: execution.routineLocalID
      ) else { return false }
      return routineBinding.parentEntityKind == .routineGroup
        && routineBinding.parentLocalEntityID == execution.groupLocalID
    }
  }

  private func hasDeleteSuccessor(
    operation: RoutineSyncOperation,
    localEntityID: UUID,
    among mutations: [PersistedRoutineSyncMutation]
  ) throws -> Bool {
    try mutations.contains { mutation in
      _ = try makeMutation(mutation)
      return mutation.operationRawValue == operation.rawValue
        && mutation.localEntityID == localEntityID
    }
  }

  private func stageDiscardNeverCommittedGroup(
    memberID: Int64,
    groupLocalID: UUID
  ) throws {
    for mutation in try persistedMutations(memberID: memberID) {
      guard let command = try? typedCommand(from: mutation.payload) else { continue }
      let related: Bool
      switch command {
      case .createRoutineGroup(let group):
        related = group.localID == groupLocalID
      case .addRoutine(let candidateGroupID, _):
        related = candidateGroupID == groupLocalID
      case .selectActiveRoutineGroup(let selectedGroupID):
        related = selectedGroupID == groupLocalID
      case .deleteRoutineGroup(let candidateGroupID):
        related = candidateGroupID == groupLocalID
      case .deleteRoutine(let candidateGroupID, _):
        related = candidateGroupID == groupLocalID
      case .saveRoutineExecution(let execution):
        related = execution.groupLocalID == groupLocalID
      }
      guard related else { continue }
      let state = try makeMutation(mutation).state
      let isCreatePredecessor = mutation.operationRawValue
        == RoutineSyncOperation.createRoutineGroup.rawValue
      guard isCreatePredecessor || state == .waitingForServerContract || state == .queued else {
        throw RoutineSyncRepositoryError.reconciliationRequired(existingMutationID: mutation.id)
      }
      modelContext.delete(mutation)
    }
  }

  private func stageDiscardNeverCommittedRoutine(
    memberID: Int64,
    routineLocalID: UUID
  ) throws {
    for mutation in try persistedMutations(memberID: memberID) {
      guard let command = try? typedCommand(from: mutation.payload) else { continue }
      let related: Bool
      switch command {
      case .addRoutine(_, let routine):
        related = routine.localID == routineLocalID
      case .deleteRoutine(_, let candidateRoutineID):
        related = candidateRoutineID == routineLocalID
      case .saveRoutineExecution(let execution):
        related = execution.routineLocalID == routineLocalID
      case .createRoutineGroup, .selectActiveRoutineGroup, .deleteRoutineGroup:
        related = false
      }
      guard related else { continue }
      let state = try makeMutation(mutation).state
      let isAddPredecessor = mutation.operationRawValue == RoutineSyncOperation.addRoutine.rawValue
      guard isAddPredecessor || state == .waitingForServerContract || state == .queued else {
        throw RoutineSyncRepositoryError.reconciliationRequired(existingMutationID: mutation.id)
      }
      modelContext.delete(mutation)
    }
  }

  private func stageDiscardUnprojectableExecutions(
    memberID: Int64,
    groupLocalID: UUID,
    desiredRoutineLocalIDs: Set<UUID>
  ) throws {
    for mutation in try persistedMutations(memberID: memberID) {
      guard case .saveRoutineExecution(let execution) = try? typedCommand(
        from: mutation.payload
      ), execution.groupLocalID == groupLocalID,
        !desiredRoutineLocalIDs.contains(execution.routineLocalID) else { continue }
      let state = try makeMutation(mutation).state
      guard state == .waitingForServerContract || state == .queued else {
        throw RoutineSyncRepositoryError.reconciliationRequired(
          existingMutationID: mutation.id
        )
      }
      modelContext.delete(mutation)
    }
  }

  private func stageDeleteGroupBindingTree(memberID: Int64, groupLocalID: UUID) throws {
    let bindings = try persistedBindings(memberID: memberID)
    for binding in bindings where
      (binding.entityKindRawValue == RoutineSyncEntityKind.routineGroup.rawValue && binding.localEntityID == groupLocalID)
        || (binding.entityKindRawValue == RoutineSyncEntityKind.routine.rawValue
          && binding.parentEntityKindRawValue == RoutineSyncEntityKind.routineGroup.rawValue
          && binding.parentLocalEntityID == groupLocalID) {
      modelContext.delete(binding)
    }
    // Execution bindings intentionally remain as durable history records.
  }

  private func stageDeleteBinding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws {
    if let binding = try persistedBinding(
      key: bindingKey(memberID: memberID, entityKind: entityKind, localEntityID: localEntityID)
    ) {
      modelContext.delete(binding)
    }
  }

  private func stageDeleteAccountScopedData(memberID: Int64) throws {
    try persistedBindings(memberID: memberID).forEach(modelContext.delete)
    try persistedMutations(memberID: memberID).forEach(modelContext.delete)
  }

  private func persistedBindings(memberID: Int64) throws -> [PersistedRoutineServerBinding] {
    let namespace = serverNamespace.rawValue
    return try modelContext.fetch(FetchDescriptor<PersistedRoutineServerBinding>(
      predicate: #Predicate {
        $0.serverNamespaceRawValue == namespace && $0.memberID == memberID
      }
    ))
  }

  private func persistedBinding(key: String) throws -> PersistedRoutineServerBinding? {
    var descriptor = FetchDescriptor<PersistedRoutineServerBinding>(
      predicate: #Predicate { $0.bindingKey == key }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  private func persistedMutations(memberID: Int64) throws -> [PersistedRoutineSyncMutation] {
    let namespace = serverNamespace.rawValue
    return try modelContext.fetch(FetchDescriptor<PersistedRoutineSyncMutation>(
      predicate: #Predicate {
        $0.serverNamespaceRawValue == namespace && $0.memberID == memberID
      }
    ))
  }

  private func allPersistedMutations() throws -> [PersistedRoutineSyncMutation] {
    let namespace = serverNamespace.rawValue
    return try modelContext.fetch(FetchDescriptor<PersistedRoutineSyncMutation>(
      predicate: #Predicate { $0.serverNamespaceRawValue == namespace }
    ))
  }

  private func persistedMutation(key: String) throws -> PersistedRoutineSyncMutation? {
    var descriptor = FetchDescriptor<PersistedRoutineSyncMutation>(
      predicate: #Predicate { $0.operationKey == key }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  private func persistedMutation(id: UUID) throws -> PersistedRoutineSyncMutation? {
    let namespace = serverNamespace.rawValue
    var descriptor = FetchDescriptor<PersistedRoutineSyncMutation>(
      predicate: #Predicate { $0.id == id && $0.serverNamespaceRawValue == namespace }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  private func pendingCleanup(memberID: Int64) throws -> PersistedPendingAccountCleanup? {
    let key = cleanupKey(memberID: memberID)
    var descriptor = FetchDescriptor<PersistedPendingAccountCleanup>(
      predicate: #Predicate { $0.cleanupKey == key }
    )
    descriptor.fetchLimit = 1
    guard let marker = try modelContext.fetch(descriptor).first else {
      return nil
    }
    guard try validatedPendingCleanup(marker) == serverNamespace else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedPendingAccountCleanup.namespace"
      )
    }
    return marker
  }

  private func pendingCleanups() throws -> [PersistedPendingAccountCleanup] {
    // Read every row first. Filtering by a raw namespace before validation
    // would silently ignore a corrupt marker and allow stale credentials to
    // be restored at launch.
    return try modelContext.fetch(FetchDescriptor<PersistedPendingAccountCleanup>())
      .compactMap { marker in
        let namespace = try validatedPendingCleanup(marker)
        return namespace == serverNamespace ? marker : nil
      }
  }

  private func validatedPendingCleanup(
    _ marker: PersistedPendingAccountCleanup
  ) throws -> RoutineSyncServerNamespace {
    guard let namespace = RoutineSyncServerNamespace(
      rawValue: marker.serverNamespaceRawValue
    ), marker.memberID > 0,
      marker.cleanupKey == "\(namespace.rawValue)|\(marker.memberID)",
      PendingAccountCleanupPhase(rawValue: marker.phaseRawValue) != nil else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedPendingAccountCleanup"
      )
    }
    return namespace
  }

  private func makeBinding(_ persisted: PersistedRoutineServerBinding) throws -> RoutineServerBinding {
    try validate(memberID: persisted.memberID)
    guard let namespace = RoutineSyncServerNamespace(rawValue: persisted.serverNamespaceRawValue),
          namespace == serverNamespace,
          let entityKind = RoutineSyncEntityKind(rawValue: persisted.entityKindRawValue),
          entityKind != .account,
          persisted.remoteID > 0,
          persisted.bindingKey == bindingKey(
            memberID: persisted.memberID,
            entityKind: entityKind,
            localEntityID: persisted.localEntityID
          ),
          persisted.remoteBindingKey == remoteBindingKey(
            memberID: persisted.memberID,
            entityKind: entityKind,
            remoteID: persisted.remoteID
          ) else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedRoutineServerBinding.identity"
      )
    }
    let parentKind: RoutineSyncEntityKind?
    if let rawParent = persisted.parentEntityKindRawValue {
      guard let parsed = RoutineSyncEntityKind(rawValue: rawParent),
            let parentID = persisted.parentLocalEntityID else {
        throw RoutineSyncRepositoryError.corruptedStoredValue(
          field: "PersistedRoutineServerBinding.parent"
        )
      }
      _ = parentID
      parentKind = parsed
    } else {
      guard persisted.parentLocalEntityID == nil else {
        throw RoutineSyncRepositoryError.corruptedStoredValue(
          field: "PersistedRoutineServerBinding.parent"
        )
      }
      parentKind = nil
    }
    let expectedParent: RoutineSyncEntityKind?
    switch entityKind {
    case .routineGroup, .account: expectedParent = nil
    case .routine: expectedParent = .routineGroup
    case .routineExecution: expectedParent = .routine
    }
    guard expectedParent == parentKind else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedRoutineServerBinding.parent"
      )
    }
    return RoutineServerBinding(
      id: persisted.id,
      serverNamespace: namespace,
      memberID: persisted.memberID,
      entityKind: entityKind,
      localEntityID: persisted.localEntityID,
      remoteID: persisted.remoteID,
      remoteRevision: normalized(persisted.remoteRevision),
      parentEntityKind: parentKind,
      parentLocalEntityID: persisted.parentLocalEntityID,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt
    )
  }

  private func makeMutation(_ persisted: PersistedRoutineSyncMutation) throws -> RoutineSyncMutation {
    try validate(memberID: persisted.memberID)
    guard let namespace = RoutineSyncServerNamespace(rawValue: persisted.serverNamespaceRawValue),
          namespace == serverNamespace,
          let operation = RoutineSyncOperation(rawValue: persisted.operationRawValue),
          let entityKind = RoutineSyncEntityKind(rawValue: persisted.entityKindRawValue),
          operation.accepts(entityKind),
          let state = RoutineSyncMutationState(rawValue: persisted.stateRawValue),
          persisted.generation > 0,
          persisted.payloadVersion > 0,
          !persisted.payload.isEmpty,
          persisted.operationKey == operationKey(
            memberID: persisted.memberID,
            operation: operation,
            entityKind: entityKind,
            localEntityID: persisted.localEntityID
          ),
          try canonicalPayload(persisted.payload) == persisted.payload else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedRoutineSyncMutation"
      )
    }
    let attempt = try makeAttempt(persisted)
    if state == .attempting, attempt == nil {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedRoutineSyncMutation.attempt"
      )
    }
    return RoutineSyncMutation(
      id: persisted.id,
      serverNamespace: namespace,
      memberID: persisted.memberID,
      operation: operation,
      entityKind: entityKind,
      localEntityID: persisted.localEntityID,
      generationID: persisted.generationID,
      generation: persisted.generation,
      payloadVersion: persisted.payloadVersion,
      payload: persisted.payload,
      state: state,
      attempt: attempt,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt
    )
  }

  private func makeAttempt(_ persisted: PersistedRoutineSyncMutation) throws -> RoutineSyncAttempt? {
    let values: [Any?] = [
      persisted.attemptedGenerationID,
      persisted.attemptedGeneration,
      persisted.attemptedPayloadVersion,
      persisted.attemptedPayload,
      persisted.attemptedAt,
    ]
    let count = values.compactMap { $0 }.count
    guard count == 0 || count == values.count else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedRoutineSyncMutation.attempt"
      )
    }
    guard count > 0,
          let generationID = persisted.attemptedGenerationID,
          let generation = persisted.attemptedGeneration,
          let payloadVersion = persisted.attemptedPayloadVersion,
          let payload = persisted.attemptedPayload,
          let attemptedAt = persisted.attemptedAt,
          generation > 0,
          payloadVersion > 0,
          !payload.isEmpty,
          try canonicalPayload(payload) == payload else { return nil }
    return RoutineSyncAttempt(
      generationID: generationID,
      generation: generation,
      payloadVersion: payloadVersion,
      payload: payload,
      attemptedAt: attemptedAt
    )
  }

  private func matchesAttemptOrCurrent(
    _ persisted: PersistedRoutineSyncMutation,
    expectedGenerationID: UUID
  ) -> Bool {
    if persisted.attemptedGenerationID != nil {
      return persisted.attemptedGenerationID == expectedGenerationID
    }
    return persisted.generationID == expectedGenerationID
  }

  private func payload(
    for persisted: PersistedRoutineSyncMutation,
    expectedGenerationID: UUID
  ) throws -> Data {
    if persisted.attemptedGenerationID == expectedGenerationID,
       let payload = persisted.attemptedPayload {
      return payload
    }
    guard persisted.generationID == expectedGenerationID else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    return persisted.payload
  }

  private func typedCommand(from payload: Data) throws -> RoutineSyncCommand {
    guard let command = try? JSONDecoder().decode(
      RoutineSyncCommand.self,
      from: payload
    ) else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    return command
  }

  private func clearAttempt(_ persisted: PersistedRoutineSyncMutation) {
    persisted.attemptedGenerationID = nil
    persisted.attemptedGeneration = nil
    persisted.attemptedPayloadVersion = nil
    persisted.attemptedPayload = nil
    persisted.attemptedAt = nil
  }

  private func operation(of persisted: PersistedRoutineSyncMutation) throws -> RoutineSyncOperation {
    guard let operation = RoutineSyncOperation(rawValue: persisted.operationRawValue) else {
      throw RoutineSyncRepositoryError.corruptedStoredValue(
        field: "PersistedRoutineSyncMutation.operationRawValue"
      )
    }
    return operation
  }

  private func validate(assignment: RoutineServerBindingAssignment) throws {
    guard assignment.entityKind != .account, assignment.remoteID > 0 else {
      throw RoutineSyncRepositoryError.invalidRemoteID
    }
    let expectedParent: RoutineSyncEntityKind?
    switch assignment.entityKind {
    case .routineGroup, .account: expectedParent = nil
    case .routine: expectedParent = .routineGroup
    case .routineExecution: expectedParent = .routine
    }
    if expectedParent == nil,
       assignment.parentEntityKind == nil,
       assignment.parentLocalEntityID == nil {
      return
    }
    guard let expectedParent,
          assignment.parentEntityKind == expectedParent,
          assignment.parentLocalEntityID != nil else {
      throw RoutineSyncRepositoryError.invalidParentBinding
    }
  }

  private func validate(memberID: Int64) throws {
    guard memberID > 0 else { throw RoutineSyncRepositoryError.invalidMemberID }
  }

  private func bindingKey(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) -> String {
    "\(serverNamespace.rawValue)|\(memberID)|\(entityKind.rawValue)|\(canonical(localEntityID))"
  }

  private func operationKey(
    memberID: Int64,
    operation: RoutineSyncOperation,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) -> String {
    "\(serverNamespace.rawValue)|\(memberID)|\(operation.rawValue)|\(entityKind.rawValue)|\(canonical(localEntityID))"
  }

  private func remoteBindingKey(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    remoteID: Int64
  ) -> String {
    "\(serverNamespace.rawValue)|\(memberID)|\(entityKind.rawValue)|\(remoteID)"
  }

  private func cleanupKey(memberID: Int64) -> String {
    "\(serverNamespace.rawValue)|\(memberID)"
  }

  private func canonicalPayload(_ payload: Data) throws -> Data {
    guard !payload.isEmpty,
          let object = try? JSONSerialization.jsonObject(with: payload),
          JSONSerialization.isValidJSONObject(object),
          let canonical = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
          ),
          !canonical.isEmpty else {
      throw RoutineSyncRepositoryError.invalidPayload
    }
    return canonical
  }

  private func initialState(for operation: RoutineSyncOperation) -> RoutineSyncMutationState {
    switch operation.deliveryPolicy {
    case .requiresActiveSelectionContract,
         .requiresAbsentIsSuccessContract,
         .requiresIdempotencyOrReconciliation:
      .waitingForServerContract
    }
  }

  private func canonical(_ id: UUID) -> String { id.uuidString.lowercased() }

  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func saveOrRollback() throws {
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }
}

nonisolated final class SwiftDataRoutineSyncAccountCleaner:
  AccountScopedDataCleaning,
  @unchecked Sendable {
  private let repository: any RoutineSyncRepository

  init(repository: any RoutineSyncRepository) {
    self.repository = repository
  }

  func removeAccountScopedData(memberID: Int64) async throws {
    try await repository.removeAccountScopedData(memberID: memberID)
  }

  func preparePendingAccountCleanup(memberID: Int64) async throws {
    try await repository.preparePendingAccountCleanup(memberID: memberID, at: Date())
  }

  func beginPendingAccountCleanupAttempt(memberID: Int64) async throws {
    try await repository.beginPendingAccountCleanupAttempt(memberID: memberID)
  }

  func confirmPendingAccountCleanup(memberID: Int64) async throws {
    try await repository.confirmPendingAccountCleanup(memberID: memberID)
  }

  func cancelPendingAccountCleanup(memberID: Int64) async throws {
    try await repository.cancelPendingAccountCleanup(memberID: memberID)
  }

  func completePendingAccountCleanup(memberID: Int64) async throws {
    try await repository.completePendingAccountCleanup(memberID: memberID)
  }

  func finalizePendingAccountCleanup(memberID: Int64) async throws {
    try await repository.finalizePendingAccountCleanup(memberID: memberID)
  }

  func recoverPendingAccountCleanups() async throws -> PendingAccountCleanupRecovery {
    try await repository.pendingAccountCleanupRecovery()
  }
}
