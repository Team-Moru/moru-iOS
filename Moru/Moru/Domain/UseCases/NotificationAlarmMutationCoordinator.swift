//
//  NotificationAlarmMutationCoordinator.swift
//  Moru
//

import Foundation

@MainActor
final class NotificationAlarmMutationCoordinator: AlarmScheduleMutating {
  private enum PlatformOperation {
    case replace(
      request: AlarmNotificationScheduleRequest,
      pending: AlarmPlatformSnapshot
    )
    case cancel(
      scheduleID: UUID,
      pending: AlarmPlatformSnapshot
    )

    var pendingSnapshot: AlarmPlatformSnapshot {
      switch self {
      case .replace(_, let pending), .cancel(_, let pending):
        pending
      }
    }

    var finalState: AlarmPlatformState {
      switch self {
      case .replace:
        .configured
      case .cancel:
        .cancelled
      }
    }
  }

  private final class PlatformOperationTracker {
    var persistedOperations: [PlatformOperation] = []
    var appliedReplacementOperations: [PlatformOperation] = []
  }

  private let scheduler: any AlarmNotificationScheduling
  private let platformRepository: any AlarmPlatformStateRepository
  private let resetGeneration: @MainActor () throws -> UInt64
  private let mutationAllowed: @MainActor () -> Bool
  private let now: @MainActor () -> Date
  private let makeUUID: @MainActor () -> UUID
  private var isMutationActive = false
  private var normalMutationWaiters: [CheckedContinuation<Void, Error>] = []
  private var frozenMutationWaiters: [CheckedContinuation<Void, Error>] = []
  private var freezeWaiter: CheckedContinuation<AlarmMutationFreezeToken, Error>?
  private var activeFreezeToken: AlarmMutationFreezeToken?
  private var thawRequested = false

  init(
    scheduler: any AlarmNotificationScheduling,
    platformRepository: any AlarmPlatformStateRepository,
    resetGeneration: @escaping @MainActor () throws -> UInt64,
    mutationAllowed: @escaping @MainActor () -> Bool = { true },
    now: @escaping @MainActor () -> Date = { Date() },
    makeUUID: @escaping @MainActor () -> UUID = { UUID() }
  ) {
    self.scheduler = scheduler
    self.platformRepository = platformRepository
    self.resetGeneration = resetGeneration
    self.now = now
    self.mutationAllowed = mutationAllowed
    self.makeUUID = makeUUID
  }

  func freezeAndDrain() async throws -> AlarmMutationFreezeToken {
    guard freezeWaiter == nil, activeFreezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }

    rejectNormalMutationWaiters()
    guard isMutationActive else {
      let token = AlarmMutationFreezeToken(id: UUID())
      activeFreezeToken = token
      return token
    }

    return try await withCheckedThrowingContinuation { continuation in
      freezeWaiter = continuation
    }
  }

  func commit(
    routines: [Routine],
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try await admitNormalMutation()
    defer { releaseMutation() }

    let existingSnapshots = try loadSnapshots()
    let operations = try makeOperations(
      routines: routines,
      existingSnapshots: existingSnapshots,
      cancelAbsentRoutines: false
    )
    let tracker = try await applyPlatformOperations(operations)

    do {
      try localCommit()
    } catch {
      try await recoverAfterLocalCommitFailure(tracker)
      throw NotificationAlarmMutationError.localCommitFailure
    }

    try finalize(operations)
  }

  func delete(
    routineID: UUID,
    scheduleID: UUID?,
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try await admitNormalMutation()
    defer { releaseMutation() }

    let existingSnapshots = try loadSnapshots()
    let existingByScheduleID = try snapshotIndex(existingSnapshots)
    var generation: UInt64?
    let operations: [PlatformOperation]

    if let scheduleID {
      let operation = try makeCancellationOperation(
        routineID: routineID,
        scheduleID: scheduleID,
        existing: existingByScheduleID[scheduleID],
        generation: &generation
      )
      operations = operation.map { [$0] } ?? []
    } else {
      operations = try existingSnapshots
        .filter { $0.routineID == routineID && $0.state != .cancelled }
        .sorted(by: Self.sortSnapshots)
        .compactMap {
          try makeCancellationOperation(
            routineID: routineID,
            scheduleID: $0.scheduleID,
            existing: $0,
            generation: &generation
          )
        }
    }

    let tracker = try await applyPlatformOperations(operations)

    do {
      try localCommit()
    } catch {
      try await recoverAfterLocalCommitFailure(tracker)
      throw NotificationAlarmMutationError.localCommitFailure
    }

    try finalize(operations)
  }

  func reconcile(routines: [Routine]) async throws {
    try await admitNormalMutation()
    defer { releaseMutation() }

    let operations = try makeOperations(
      routines: routines,
      existingSnapshots: try loadSnapshots(),
      cancelAbsentRoutines: true
    )
    _ = try await applyPlatformOperations(operations)
    try finalize(operations)
  }

  func cancelAll(
    scheduleIDs: [UUID],
    using token: AlarmMutationFreezeToken
  ) async throws {
    try await admitFrozenMutation(using: token)
    defer { releaseMutation() }

    let snapshots = try loadSnapshots()
    let existingByScheduleID = try snapshotIndex(snapshots)
    let orderedScheduleIDs = Array(Set(scheduleIDs)).sorted {
      $0.uuidString < $1.uuidString
    }
    let operations = orderedScheduleIDs.compactMap { scheduleID -> PlatformOperation? in
      guard let existing = existingByScheduleID[scheduleID], existing.state != .cancelled else {
        return nil
      }
      return .cancel(
        scheduleID: scheduleID,
        pending: replacing(
          existing,
          state: .cancellationPending,
          updatedAt: now(),
          lastErrorCode: "notificationCancellationPending"
        )
      )
    }

    let tracker = try await applyPlatformOperations(operations)

    do {
      for scheduleID in orderedScheduleIDs where existingByScheduleID[scheduleID] == nil {
        try await scheduler.cancel(scheduleID: scheduleID)
      }
    } catch {
      try markFailures(tracker.persistedOperations, errorCode: "notificationPlatformFailed")
      throw NotificationAlarmMutationError.platformFailure
    }

    try finalize(operations)
  }

  func thaw(_ token: AlarmMutationFreezeToken) {
    guard activeFreezeToken == token, !thawRequested else {
      return
    }

    thawRequested = true
    guard !isMutationActive else {
      rejectFrozenMutationWaiters()
      return
    }

    finishThaw()
  }

  func permissionState() async -> AlarmNotificationPermissionState {
    await scheduler.authorizationState()
  }

  private var isFreezeRequested: Bool {
    freezeWaiter != nil
  }

  private func admitNormalMutation() async throws {
    guard mutationAllowed() else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
    guard !isFreezeRequested, activeFreezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }

    guard isMutationActive else {
      isMutationActive = true
      return
    }

    try await withCheckedThrowingContinuation { continuation in
      normalMutationWaiters.append(continuation)
    }
  }

  private func admitFrozenMutation(using token: AlarmMutationFreezeToken) async throws {
    guard activeFreezeToken == token, !thawRequested else {
      throw NotificationAlarmMutationError.mutationFrozen
    }

    guard isMutationActive else {
      isMutationActive = true
      return
    }

    try await withCheckedThrowingContinuation { continuation in
      frozenMutationWaiters.append(continuation)
    }
  }

  private func releaseMutation() {
    guard isMutationActive else {
      return
    }

    isMutationActive = false

    if activeFreezeToken != nil {
      if thawRequested {
        finishThaw()
      } else {
        resumeNextFrozenMutation()
      }
      return
    }

    if let freezeWaiter {
      self.freezeWaiter = nil
      let token = AlarmMutationFreezeToken(id: UUID())
      activeFreezeToken = token
      freezeWaiter.resume(returning: token)
      return
    }

    resumeNextNormalMutation()
  }

  private func finishThaw() {
    activeFreezeToken = nil
    thawRequested = false
    rejectFrozenMutationWaiters()
    resumeNextNormalMutation()
  }

  private func resumeNextNormalMutation() {
    guard !isMutationActive, !isFreezeRequested, activeFreezeToken == nil else {
      return
    }

    while !normalMutationWaiters.isEmpty {
      let continuation = normalMutationWaiters.removeFirst()
      guard mutationAllowed() else {
        continuation.resume(throwing: NotificationAlarmMutationError.mutationFrozen)
        continue
      }

      isMutationActive = true
      continuation.resume()
      return
    }
  }

  private func resumeNextFrozenMutation() {
    guard !isMutationActive, activeFreezeToken != nil, !thawRequested,
          !frozenMutationWaiters.isEmpty else {
      return
    }

    let continuation = frozenMutationWaiters.removeFirst()
    isMutationActive = true
    continuation.resume()
  }

  private func rejectNormalMutationWaiters() {
    let waiters = normalMutationWaiters
    normalMutationWaiters.removeAll()

    for waiter in waiters {
      waiter.resume(throwing: NotificationAlarmMutationError.mutationFrozen)
    }
  }

  private func rejectFrozenMutationWaiters() {
    let waiters = frozenMutationWaiters
    frozenMutationWaiters.removeAll()

    for waiter in waiters {
      waiter.resume(throwing: NotificationAlarmMutationError.mutationFrozen)
    }
  }

  private func makeOperations(
    routines: [Routine],
    existingSnapshots: [AlarmPlatformSnapshot],
    cancelAbsentRoutines: Bool
  ) throws -> [PlatformOperation] {
    let existingByScheduleID = try snapshotIndex(existingSnapshots)
    let orderedRoutines = Self.stablySorted(routines)
    let representedRoutineIDs = Set(orderedRoutines.map(\.id))
    var generation: UInt64?
    var operations: [PlatformOperation] = []
    var processedScheduleIDs = Set<UUID>()

    for routine in orderedRoutines {
      guard let schedule = routine.alarmSchedule else {
        let snapshotsToCancel = existingSnapshots
          .filter { $0.routineID == routine.id && $0.state != .cancelled }
          .sorted(by: Self.sortSnapshots)
        for snapshot in snapshotsToCancel {
          guard processedScheduleIDs.insert(snapshot.scheduleID).inserted else {
            continue
          }
          if let operation = try makeCancellationOperation(
            routineID: routine.id,
            scheduleID: snapshot.scheduleID,
            existing: snapshot,
            generation: &generation
          ) {
            operations.append(operation)
          }
        }
        continue
      }

      let existing = existingByScheduleID[schedule.id]
      processedScheduleIDs.insert(schedule.id)
      if routine.isActive && schedule.isEnabled {
        guard AlarmNotificationScheduleRequest.validationError(
          hour: schedule.hour,
          minute: schedule.minute,
          weekdays: schedule.weekdays
        ) == nil else {
          throw NotificationAlarmMutationError.invalidSchedule
        }

        operations.append(
          try makeReplacementOperation(
            routine: routine,
            schedule: schedule,
            existing: existing,
            generation: &generation
          )
        )
      } else if let operation = try makeCancellationOperation(
        routineID: routine.id,
        scheduleID: schedule.id,
        existing: existing,
        generation: &generation
      ) {
        operations.append(operation)
      }

      let staleRoutineSnapshots = existingSnapshots
        .filter {
          $0.routineID == routine.id
            && $0.scheduleID != schedule.id
            && $0.state != .cancelled
        }
        .sorted(by: Self.sortSnapshots)
      for snapshot in staleRoutineSnapshots {
        guard processedScheduleIDs.insert(snapshot.scheduleID).inserted else {
          continue
        }
        if let operation = try makeCancellationOperation(
          routineID: routine.id,
          scheduleID: snapshot.scheduleID,
          existing: snapshot,
          generation: &generation
        ) {
          operations.append(operation)
        }
      }
    }

    if cancelAbsentRoutines {
      let absentRoutineSnapshots = existingSnapshots
        .filter {
          !representedRoutineIDs.contains($0.routineID)
            && $0.state != .cancelled
        }
        .sorted(by: Self.sortSnapshots)
      for snapshot in absentRoutineSnapshots {
        guard processedScheduleIDs.insert(snapshot.scheduleID).inserted else {
          continue
        }
        if let operation = try makeCancellationOperation(
          routineID: snapshot.routineID,
          scheduleID: snapshot.scheduleID,
          existing: snapshot,
          generation: &generation
        ) {
          operations.append(operation)
        }
      }
    }

    return operations
  }

  private func makeReplacementOperation(
    routine: Routine,
    schedule: AlarmSchedule,
    existing: AlarmPlatformSnapshot?,
    generation: inout UInt64?
  ) throws -> PlatformOperation {
    let resetGeneration = try currentGeneration(&generation)
    let fingerprint = AlarmNotificationScheduleRequest.desiredScheduleFingerprint(
      routineID: routine.id,
      scheduleID: schedule.id,
      routineName: routine.name,
      hour: schedule.hour,
      minute: schedule.minute,
      weekdays: schedule.weekdays,
      resetGeneration: resetGeneration
    )
    let platformRequestID: UUID
    if let existing, existing.desiredScheduleFingerprint == fingerprint {
      platformRequestID = existing.platformRequestID
    } else {
      platformRequestID = makeUUID()
    }
    let timestamp = now()
    let pending = AlarmPlatformSnapshot(
      id: existing?.id ?? schedule.id,
      scheduleID: schedule.id,
      routineID: routine.id,
      desiredScheduleFingerprint: fingerprint,
      platformRequestID: platformRequestID,
      state: .repairRequired,
      updatedAt: timestamp,
      lastErrorCode: "notificationMutationPending"
    )
    let request = AlarmNotificationScheduleRequest(
      routineID: routine.id,
      scheduleID: schedule.id,
      routineName: routine.name,
      hour: schedule.hour,
      minute: schedule.minute,
      weekdays: schedule.weekdays,
      resetGeneration: resetGeneration,
      desiredScheduleFingerprint: fingerprint
    )
    return .replace(request: request, pending: pending)
  }

  private func makeCancellationOperation(
    routineID: UUID,
    scheduleID: UUID,
    existing: AlarmPlatformSnapshot?,
    generation: inout UInt64?
  ) throws -> PlatformOperation? {
    guard existing?.state != .cancelled else {
      return nil
    }

    if let existing {
      return .cancel(
        scheduleID: scheduleID,
        pending: replacing(
          existing,
          state: .cancellationPending,
          updatedAt: now(),
          lastErrorCode: "notificationCancellationPending"
        )
      )
    }

    let resetGeneration = try currentGeneration(&generation)
    let timestamp = now()
    return .cancel(
      scheduleID: scheduleID,
      pending: AlarmPlatformSnapshot(
        id: scheduleID,
        scheduleID: scheduleID,
        routineID: routineID,
        desiredScheduleFingerprint: AlarmNotificationScheduleRequest.cancellationFingerprint(
          routineID: routineID,
          scheduleID: scheduleID,
          resetGeneration: resetGeneration
        ),
        platformRequestID: makeUUID(),
        state: .cancellationPending,
        updatedAt: timestamp,
        lastErrorCode: "notificationCancellationPending"
      )
    )
  }

  private func applyPlatformOperations(
    _ operations: [PlatformOperation]
  ) async throws -> PlatformOperationTracker {
    let tracker = PlatformOperationTracker()

    do {
      try await performPlatformOperations(operations, tracker: tracker)
    } catch {
      let failure = (error as? NotificationAlarmMutationError) ?? .platformFailure
      try await recoverAfterPlatformFailure(failure, tracker: tracker)
      throw failure
    }

    return tracker
  }

  private func performPlatformOperations(
    _ operations: [PlatformOperation],
    tracker: PlatformOperationTracker
  ) async throws {
    for operation in operations {
      try save(operation.pendingSnapshot)
      tracker.persistedOperations.append(operation)

      switch operation {
      case .replace(let request, _):
        try await requireSchedulingPermission()
        try await scheduler.replace(request)
        tracker.appliedReplacementOperations.append(operation)
      case .cancel(let scheduleID, _):
        do {
          try await scheduler.cancel(scheduleID: scheduleID)
        } catch {
          throw NotificationAlarmMutationError.platformFailure
        }
      }
    }
  }

  private func recoverAfterPlatformFailure(
    _ error: Error,
    tracker: PlatformOperationTracker
  ) async throws {
    let failureCode: String
    if let mutationError = error as? NotificationAlarmMutationError {
      failureCode = errorCode(for: mutationError)
    } else {
      failureCode = "notificationPlatformFailed"
    }

    try await recover(
      operations: tracker.persistedOperations,
      appliedReplacements: tracker.appliedReplacementOperations,
      errorCode: failureCode
    )
  }

  private func recoverAfterLocalCommitFailure(
    _ tracker: PlatformOperationTracker
  ) async throws {
    try await recover(
      operations: tracker.persistedOperations,
      appliedReplacements: tracker.appliedReplacementOperations,
      errorCode: "notificationLocalCommitFailed"
    )
  }

  private func recover(
    operations: [PlatformOperation],
    appliedReplacements: [PlatformOperation],
    errorCode: String
  ) async throws {
    var firstRecoveryError: Error?

    do {
      try markFailures(operations, errorCode: errorCode)
    } catch {
      firstRecoveryError = error
    }

    do {
      try await compensateAppliedReplacements(appliedReplacements)
    } catch {
      if firstRecoveryError == nil {
        firstRecoveryError = error
      }
    }

    if let firstRecoveryError {
      throw firstRecoveryError
    }
  }

  private func compensateAppliedReplacements(
    _ operations: [PlatformOperation]
  ) async throws {
    var firstPersistenceError: Error?

    for operation in operations.reversed() {
      guard case .replace(let request, _) = operation else {
        continue
      }

      do {
        try await scheduler.cancel(scheduleID: request.scheduleID)
      } catch {
        do {
          try markFailure(operation, errorCode: "notificationCompensationFailed")
        } catch {
          if firstPersistenceError == nil {
            firstPersistenceError = error
          }
        }
      }
    }

    if let firstPersistenceError {
      throw firstPersistenceError
    }
  }

  private func finalize(_ operations: [PlatformOperation]) throws {
    for operation in operations {
      try save(
        replacing(
          operation.pendingSnapshot,
          state: operation.finalState,
          updatedAt: now(),
          lastErrorCode: nil
        )
      )
    }
  }

  private func requireSchedulingPermission() async throws {
    switch await scheduler.authorizationState() {
    case .authorized:
      return
    case .denied:
      throw NotificationAlarmMutationError.permissionDenied
    case .notDetermined:
      let requestedState: AlarmNotificationPermissionState
      do {
        requestedState = try await scheduler.requestAuthorization()
      } catch {
        throw NotificationAlarmMutationError.platformFailure
      }
      guard requestedState == .authorized else {
        throw NotificationAlarmMutationError.permissionDenied
      }
    }
  }

  private func currentGeneration(_ cachedGeneration: inout UInt64?) throws -> UInt64 {
    if let cachedGeneration {
      return cachedGeneration
    }
    do {
      let generation = try resetGeneration()
      cachedGeneration = generation
      return generation
    } catch {
      throw NotificationAlarmMutationError.generationUnavailable
    }
  }

  private func loadSnapshots() throws -> [AlarmPlatformSnapshot] {
    do {
      return try platformRepository.fetchAll()
    } catch {
      throw NotificationAlarmMutationError.storageFailure
    }
  }

  private func snapshotIndex(
    _ snapshots: [AlarmPlatformSnapshot]
  ) throws -> [UUID: AlarmPlatformSnapshot] {
    var index: [UUID: AlarmPlatformSnapshot] = [:]
    for snapshot in snapshots {
      guard index[snapshot.scheduleID] == nil else {
        throw NotificationAlarmMutationError.storageFailure
      }
      index[snapshot.scheduleID] = snapshot
    }
    return index
  }

  private func save(_ snapshot: AlarmPlatformSnapshot) throws {
    do {
      try platformRepository.save(snapshot)
    } catch {
      throw NotificationAlarmMutationError.storageFailure
    }
  }
  private func markFailures(
    _ operations: [PlatformOperation],
    errorCode: String
  ) throws {
    var firstPersistenceError: Error?

    for operation in operations {
      do {
        try markFailure(operation, errorCode: errorCode)
      } catch {
        if firstPersistenceError == nil {
          firstPersistenceError = error
        }
      }
    }

    if let firstPersistenceError {
      throw firstPersistenceError
    }
  }

  private func markFailure(
    _ operation: PlatformOperation,
    errorCode: String
  ) throws {
    try save(
      replacing(
        operation.pendingSnapshot,
        state: operation.pendingSnapshot.state,
        updatedAt: now(),
        lastErrorCode: errorCode
      )
    )
  }

  private func replacing(
    _ snapshot: AlarmPlatformSnapshot,
    state: AlarmPlatformState,
    updatedAt: Date,
    lastErrorCode: String?
  ) -> AlarmPlatformSnapshot {
    AlarmPlatformSnapshot(
      id: snapshot.id,
      scheduleID: snapshot.scheduleID,
      routineID: snapshot.routineID,
      desiredScheduleFingerprint: snapshot.desiredScheduleFingerprint,
      platformRequestID: snapshot.platformRequestID,
      state: state,
      updatedAt: updatedAt,
      lastErrorCode: lastErrorCode
    )
  }

  private func errorCode(for error: NotificationAlarmMutationError) -> String {
    switch error {
    case .permissionDenied:
      "notificationPermissionDenied"
    case .invalidSchedule:
      "notificationInvalidSchedule"
    case .platformFailure:
      "notificationPlatformFailed"
    case .localCommitFailure:
      "notificationLocalCommitFailed"
    case .storageFailure:
      "notificationStorageFailed"
    case .mutationFrozen:
      "notificationMutationFrozen"
    case .generationUnavailable:
      "notificationGenerationUnavailable"
    }
  }

  private static func stablySorted(_ routines: [Routine]) -> [Routine] {
    routines.enumerated().sorted { left, right in
      let leftID = left.element.id.uuidString.lowercased()
      let rightID = right.element.id.uuidString.lowercased()
      if leftID == rightID {
        return left.offset < right.offset
      }
      return leftID < rightID
    }.map(\.element)
  }

  private static func sortSnapshots(
    _ left: AlarmPlatformSnapshot,
    _ right: AlarmPlatformSnapshot
  ) -> Bool {
    left.scheduleID.uuidString.lowercased() < right.scheduleID.uuidString.lowercased()
  }
}
