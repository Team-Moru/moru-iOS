//
//  SwiftDataRoutineRepository.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataRoutineRepository: RoutineRepository {
  private let modelContext: ModelContext
  private let routineSyncRepository: (any RoutineSyncRepository)?
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?
  private let routineSyncWakeupRelay: RoutineSyncWakeupRelay?

  init(
    modelContext: ModelContext,
    routineSyncRepository: (any RoutineSyncRepository)? = nil,
    signedInMemberProvider: (any SignedInMemberProviding)? = nil,
    routineSyncWakeupRelay: RoutineSyncWakeupRelay? = nil
  ) {
    self.modelContext = modelContext
    self.routineSyncRepository = routineSyncRepository
    self.signedInMemberProvider = signedInMemberProvider
    self.routineSyncWakeupRelay = routineSyncWakeupRelay
  }

  @MainActor
  func fetchRoutines() throws -> [Routine] {
    let descriptor = FetchDescriptor<PersistedRoutine>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRoutine)
  }

  @MainActor
  func fetchActiveRoutines() throws -> [Routine] {
    let descriptor = FetchDescriptor<PersistedRoutine>(
      predicate: #Predicate { $0.isActive },
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).map(SwiftDataMapper.makeDomainRoutine)
  }

  @MainActor
  func routine(id: UUID) throws -> Routine? {
    try persistedRoutine(id: id).map(SwiftDataMapper.makeDomainRoutine)
  }

  @MainActor
  func saveRoutine(_ routine: Routine) throws {
    try saveRoutines([routine])
  }

  @MainActor
  func saveRoutines(_ routines: [Routine]) throws {
    do {
      let memberID = signedInMemberProvider?.signedInMemberID
      let now = Date()
      var activeProjectionChanged = false
      var removedBoundActiveRoutine = false
      for routine in routines {
        if let persisted = try persistedRoutine(id: routine.id) {
          let previous = try SwiftDataMapper.makeDomainRoutine(from: persisted)
          let hadGroupBinding = if let memberID {
            try routineSyncRepository?.binding(
              memberID: memberID,
              entityKind: .routineGroup,
              localEntityID: routine.id
            ) != nil
          } else {
            false
          }
          let hadPendingCreate = if let memberID {
            try routineSyncRepository?.mutation(
              memberID: memberID,
              operation: .createRoutineGroup,
              entityKind: .routineGroup,
              localEntityID: routine.id
            ) != nil
          } else {
            false
          }
          SwiftDataMapper.update(persisted, with: routine, in: modelContext)
          if let memberID {
            try stageExistingRoutineIntent(
              previous: previous,
              current: routine,
              memberID: memberID,
              at: now
            )
          }
          if previous.isActive != routine.isActive, hadGroupBinding || hadPendingCreate {
            activeProjectionChanged = true
          }
          removedBoundActiveRoutine = removedBoundActiveRoutine
            || (previous.isActive && !routine.isActive && hadGroupBinding)
        } else {
          modelContext.insert(SwiftDataMapper.makePersistedRoutine(from: routine))
          if let memberID {
            try routineSyncRepository?.stageEnqueue(
              EnqueuedRoutineSyncMutation(
                memberID: memberID,
                command: .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
              ),
              at: now
            )
          }
          // An inactive creation has no server-side active projection to
          // change. Creating an active group does, and is represented by the
          // same transaction's create snapshot plus account selection intent.
          activeProjectionChanged = activeProjectionChanged || routine.isActive
        }
      }

      try ensureActiveRoutineWeekdaysDoNotOverlap()

      if let memberID, activeProjectionChanged {
        try stageActiveSelection(
          memberID: memberID,
          allowRemoteClear: removedBoundActiveRoutine,
          at: now
        )
      }

      try modelContext.save()
      routineSyncWakeupRelay?.wake()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routine(id: id) else {
      return
    }

    routine.isActive = isActive
    routine.updatedAt = Date()
    try saveRoutine(routine)
  }

  @MainActor
  func deleteRoutine(id: UUID) throws {
    guard let persisted = try persistedRoutine(id: id) else {
      return
    }
    do {
      let routine = try SwiftDataMapper.makeDomainRoutine(from: persisted)
      let memberID = signedInMemberProvider?.signedInMemberID
      modelContext.delete(persisted)
      if let memberID {
        let binding = try routineSyncRepository?.binding(
          memberID: memberID,
          entityKind: .routineGroup,
          localEntityID: routine.id
        )
        let pendingCreate = try routineSyncRepository?.mutation(
          memberID: memberID,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: routine.id
        )
        let pendingCreateMayExistRemotely = mutationMayHaveReachedServer(
          pendingCreate
        )
        if binding != nil {
          try routineSyncRepository?.stageEnqueue(
            EnqueuedRoutineSyncMutation(
              memberID: memberID,
              command: .deleteRoutineGroup(groupLocalID: routine.id)
            ),
            at: Date()
          )
        } else if pendingCreateMayExistRemotely {
          // The server may already contain this group. Preserve the ambiguous
          // create and record desired absence as a dependency-blocked delete.
          try routineSyncRepository?.stageEnqueue(
            EnqueuedRoutineSyncMutation(
              memberID: memberID,
              command: .deleteRoutineGroup(groupLocalID: routine.id)
            ),
            at: Date()
          )
        } else {
          _ = try routineSyncRepository?.stageCancel(
            memberID: memberID,
            operation: .createRoutineGroup,
            entityKind: .routineGroup,
            localEntityID: routine.id
          )
          // A never-attempted local group has no server identity, so all of
          // its dependent unsent intents can disappear with it.
          try stageCancelPendingDescendantIntents(
            groupLocalID: routine.id,
            memberID: memberID
          )
        }
        if routine.isActive,
           binding != nil || pendingCreateMayExistRemotely {
          try stageActiveSelection(
            memberID: memberID,
            allowRemoteClear: true,
            at: Date()
          )
        } else if binding == nil {
          _ = try routineSyncRepository?.stageCancelActiveSelection(
            memberID: memberID,
            selectedGroupLocalID: routine.id
          )
        }
      }
      try modelContext.save()
      routineSyncWakeupRelay?.wake()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  private func stageExistingRoutineIntent(
    previous: Routine,
    current: Routine,
    memberID: Int64,
    at date: Date
  ) throws {
    guard let routineSyncRepository else { return }
    let groupBinding = try routineSyncRepository.binding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: current.id
    )
    if let pendingCreate = try routineSyncRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: current.id
    ) {
      if pendingCreate.state == .waitingForServerContract || pendingCreate.state == .queued {
        let currentStepIDs = Set(current.steps.map(\.id))
        for removedStep in previous.steps where !currentStepIDs.contains(removedStep.id) {
          // A pending group-create snapshot can still describe this child, but
          // the current desired snapshot no longer does. Its result cannot be
          // delivered after the group is created, so remove the matching
          // waiting/queued execution intent in the same local transaction.
          try stageCancelPendingExecutionIntents(
            groupLocalID: current.id,
            routineLocalID: removedStep.id,
            memberID: memberID
          )
        }
      }
      // During an attempt or reconciliation this rotates only the desired
      // generation. The exact attempted snapshot remains durable.
      try routineSyncRepository.stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: memberID,
          command: .createRoutineGroup(RoutineSyncGroupSnapshot(routine: current))
        ),
        at: date
      )
      return
    }
    if groupBinding == nil {
      // Login backfill owns creation for existing local-only groups. Avoid
      // creating that account-scoped intent implicitly from an unrelated edit.
      return
    }

    let previousSteps = Dictionary(uniqueKeysWithValues: previous.steps.map { ($0.id, $0) })
    let currentSteps = Dictionary(uniqueKeysWithValues: current.steps.map { ($0.id, $0) })
    for step in current.steps where previousSteps[step.id] == nil {
      if let existingBinding = try routineSyncRepository.binding(
        memberID: memberID,
        entityKind: .routine,
        localEntityID: step.id
      ) {
        guard existingBinding.parentEntityKind == .routineGroup,
              existingBinding.parentLocalEntityID == current.id else {
          throw RoutineSyncRepositoryError.invalidParentBinding
        }
        continue
      }
      try routineSyncRepository.stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: memberID,
          command: .addRoutine(
            groupLocalID: current.id,
            routine: RoutineSyncRoutineSnapshot(step: step)
          )
        ),
        at: date
      )
    }
    for step in current.steps where previousSteps[step.id] != nil {
      guard try routineSyncRepository.binding(
        memberID: memberID,
        entityKind: .routine,
        localEntityID: step.id
      ) == nil,
      let pendingAdd = try routineSyncRepository.mutation(
        memberID: memberID,
        operation: .addRoutine,
        entityKind: .routine,
        localEntityID: step.id
      ) else {
        continue
      }
      guard case .addRoutine(let groupLocalID, let queuedStep) = try JSONDecoder().decode(
        RoutineSyncCommand.self,
        from: pendingAdd.payload
      ), groupLocalID == current.id, queuedStep.localID == step.id else {
        throw RoutineSyncRepositoryError.invalidParentBinding
      }
      guard previousSteps[step.id] != step else { continue }
      try routineSyncRepository.stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: memberID,
          command: .addRoutine(
            groupLocalID: current.id,
            routine: RoutineSyncRoutineSnapshot(step: step)
          )
        ),
        at: date
      )
    }
    for step in previous.steps where currentSteps[step.id] == nil {
      let stepBinding = try routineSyncRepository.binding(
        memberID: memberID,
        entityKind: .routine,
        localEntityID: step.id
      )
      if let stepBinding,
         stepBinding.parentEntityKind == .routineGroup,
         stepBinding.parentLocalEntityID == current.id {
        try routineSyncRepository.stageEnqueue(
          EnqueuedRoutineSyncMutation(
            memberID: memberID,
            command: .deleteRoutine(
              groupLocalID: current.id,
              routineLocalID: step.id
            )
          ),
          at: date
        )
      } else {
        let pendingAdd = try routineSyncRepository.mutation(
          memberID: memberID,
          operation: .addRoutine,
          entityKind: .routine,
          localEntityID: step.id
        )
        if mutationMayHaveReachedServer(pendingAdd) {
          // The add may have committed. Keep dependent execution history and
          // record deletion behind the unresolved add instead of rolling back
          // the local edit.
          try routineSyncRepository.stageEnqueue(
            EnqueuedRoutineSyncMutation(
              memberID: memberID,
              command: .deleteRoutine(
                groupLocalID: current.id,
                routineLocalID: step.id
              )
            ),
            at: date
          )
        } else {
          _ = try routineSyncRepository.stageCancel(
            memberID: memberID,
            operation: .addRoutine,
            entityKind: .routine,
            localEntityID: step.id
          )
          try stageCancelPendingExecutionIntents(
            groupLocalID: current.id,
            routineLocalID: step.id,
            memberID: memberID
          )
        }
      }
    }
    // Name, schedule, prior step contents, and ordering have no server PATCH
    // contract. Their local SwiftData update above intentionally emits no row.
  }

  @MainActor
  private func stageActiveSelection(
    memberID: Int64,
    allowRemoteClear: Bool,
    at date: Date
  ) throws {
    guard let routineSyncRepository else { return }
    let routines = try modelContext.fetch(FetchDescriptor<PersistedRoutine>())
      .map(SwiftDataMapper.makeDomainRoutine)
    let activeRoutines = routines.filter(\.isActive).sorted {
      if $0.updatedAt == $1.updatedAt {
        if $0.createdAt == $1.createdAt {
          return $0.id.uuidString < $1.id.uuidString
        }
        return $0.createdAt > $1.createdAt
      }
      return $0.updatedAt > $1.updatedAt
    }
    let localSelection = try activeRoutines.first { routine in
      try isServerProjectableGroup(routine.id, memberID: memberID)
    }

    if let localSelection {
      try routineSyncRepository.stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: memberID,
          command: .selectActiveRoutineGroup(selectedGroupLocalID: localSelection.id)
        ),
        at: date
      )
      return
    }

    if allowRemoteClear {
      try routineSyncRepository.stageEnqueue(
        EnqueuedRoutineSyncMutation(
          memberID: memberID,
          command: .selectActiveRoutineGroup(selectedGroupLocalID: nil)
        ),
        at: date
      )
    } else {
      // A local-only group must never become an unresolvable active ID. If a
      // not-yet-sent creation supplied the old account intent, discard that
      // intent rather than turning it into a server-side `nil` selection.
      try cancelUnboundActiveSelectionIfNeeded(memberID: memberID)
    }
  }

  @MainActor
  private func isServerProjectableGroup(_ groupID: UUID, memberID: Int64) throws -> Bool {
    guard let routineSyncRepository else { return false }
    if try routineSyncRepository.binding(
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: groupID
    ) != nil {
      return true
    }
    return try routineSyncRepository.mutation(
      memberID: memberID,
      operation: .createRoutineGroup,
      entityKind: .routineGroup,
      localEntityID: groupID
    ) != nil
  }

  /// A blocked mutation without an attempt is a local validation failure and
  /// can be cancelled. Any durable attempt means the server may have committed
  /// it, including a TTL-expired or conflict-blocked attempt.
  private func mutationMayHaveReachedServer(
    _ mutation: RoutineSyncMutation?
  ) -> Bool {
    guard let mutation else { return false }
    return mutation.state == .attempting
      || mutation.state == .needsReconciliation
      || mutation.state == .blocked && mutation.attempt != nil
  }

  @MainActor
  private func cancelUnboundActiveSelectionIfNeeded(memberID: Int64) throws {
    guard let routineSyncRepository,
          let mutation = try routineSyncRepository.mutation(
            memberID: memberID,
            operation: .setRoutineGroupActive,
            entityKind: .account,
            localEntityID: RoutineSyncCommand.accountSelectionID
          ),
          case .selectActiveRoutineGroup(let selectedGroupID?) = try JSONDecoder().decode(
            RoutineSyncCommand.self,
            from: mutation.payload
          ),
          try routineSyncRepository.binding(
            memberID: memberID,
            entityKind: .routineGroup,
            localEntityID: selectedGroupID
          ) == nil,
          try routineSyncRepository.mutation(
            memberID: memberID,
            operation: .createRoutineGroup,
            entityKind: .routineGroup,
            localEntityID: selectedGroupID
          ) != nil else {
      return
    }
    _ = try routineSyncRepository.stageCancelActiveSelection(
      memberID: memberID,
      selectedGroupLocalID: selectedGroupID
    )
  }

  /// Cancels delivery-blocked execution snapshots for an entity that was
  /// never bound on the server. The typed payload is the only safe source for
  /// the group/step relationship: result IDs alone are globally stable but do
  /// not say which group deletion made them undeliverable.
  @MainActor
  private func stageCancelPendingExecutionIntents(
    groupLocalID: UUID,
    routineLocalID: UUID? = nil,
    memberID: Int64
  ) throws {
    guard let routineSyncRepository else { return }
    for mutation in try routineSyncRepository.mutations(memberID: memberID)
    where mutation.operation == .saveRoutineExecution {
      guard case .saveRoutineExecution(let execution) = try JSONDecoder().decode(
        RoutineSyncCommand.self,
        from: mutation.payload
      ), execution.groupLocalID == groupLocalID,
         routineLocalID == nil || execution.routineLocalID == routineLocalID else {
        continue
      }
      _ = try routineSyncRepository.stageCancel(
        memberID: memberID,
        operation: .saveRoutineExecution,
        entityKind: .routineExecution,
        localEntityID: execution.localID
      )
    }
  }

  @MainActor
  private func stageCancelPendingDescendantIntents(
    groupLocalID: UUID,
    memberID: Int64
  ) throws {
    guard let routineSyncRepository else { return }
    for mutation in try routineSyncRepository.mutations(memberID: memberID) {
      let command = try JSONDecoder().decode(RoutineSyncCommand.self, from: mutation.payload)
      switch command {
      case .addRoutine(let queuedGroupID, let routine) where queuedGroupID == groupLocalID:
        _ = try routineSyncRepository.stageCancel(
          memberID: memberID,
          operation: .addRoutine,
          entityKind: .routine,
          localEntityID: routine.localID
        )
      case .saveRoutineExecution(let execution) where execution.groupLocalID == groupLocalID:
        _ = try routineSyncRepository.stageCancel(
          memberID: memberID,
          operation: .saveRoutineExecution,
          entityKind: .routineExecution,
          localEntityID: execution.localID
        )
      default:
        continue
      }
    }
  }

  @MainActor
  private func persistedRoutine(id: UUID) throws -> PersistedRoutine? {
    var descriptor = FetchDescriptor<PersistedRoutine>(
      predicate: #Predicate { $0.id == id }
    )
    descriptor.fetchLimit = 1

    return try modelContext.fetch(descriptor).first
  }

  @MainActor
  private func ensureActiveRoutineWeekdaysDoNotOverlap() throws {
    let activeRoutines = try modelContext.fetch(
      FetchDescriptor<PersistedRoutine>(predicate: #Predicate { $0.isActive })
    )

    var scheduledWeekdays: Set<Weekday> = []
    for persisted in activeRoutines {
      let routine = try SwiftDataMapper.makeDomainRoutine(from: persisted)
      let weekdays = Set(routine.alarmSchedule?.weekdays ?? [])
      guard scheduledWeekdays.isDisjoint(with: weekdays) else {
        throw RepositoryContractError.overlappingActiveRoutineWeekdays
      }
      scheduledWeekdays.formUnion(weekdays)
    }
  }
}
