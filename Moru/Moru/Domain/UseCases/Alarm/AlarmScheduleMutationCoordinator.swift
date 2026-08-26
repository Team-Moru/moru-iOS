//
//  AlarmScheduleMutationCoordinator.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation

actor AlarmMutationGate {
  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    guard isLocked else {
      isLocked = true
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    guard !waiters.isEmpty else {
      isLocked = false
      return
    }

    waiters.removeFirst().resume()
  }
}

@MainActor
final class DefaultAlarmScheduleMutationCoordinator: AlarmScheduleMutating {
  private let routineRepository: any RoutineRepository
  private let stateRepository: any AlarmPlatformStateRepository
  private let primaryScheduler: any AlarmScheduling
  private let fallbackScheduler: any AlarmScheduling
  private let now: () -> Date
  private let gate: AlarmMutationGate

  init(
    routineRepository: any RoutineRepository,
    stateRepository: any AlarmPlatformStateRepository,
    primaryScheduler: any AlarmScheduling,
    fallbackScheduler: any AlarmScheduling,
    now: @escaping () -> Date = Date.init,
    gate: AlarmMutationGate = AlarmMutationGate()
  ) {
    self.routineRepository = routineRepository
    self.stateRepository = stateRepository
    self.primaryScheduler = primaryScheduler
    self.fallbackScheduler = fallbackScheduler
    self.now = now
    self.gate = gate
  }

  func apply(_ mutation: AlarmScheduleMutation) async throws -> AlarmMutationResult {
    await gate.acquire()

    do {
      let result = try await applyWithoutLock(mutation)
      await gate.release()
      return result
    } catch {
      await gate.release()
      throw error
    }
  }

  func reconcile() async {
    await gate.acquire()
    await reconcileWithoutLock()
    await gate.release()
  }

  func cancelAllForReset() async throws {
    await gate.acquire()

    do {
      try await cancelAllWithoutLock()
      await gate.release()
    } catch {
      await gate.release()
      throw error
    }
  }

  private func applyWithoutLock(
    _ mutation: AlarmScheduleMutation
  ) async throws -> AlarmMutationResult {
    switch mutation {
    case .synchronize(let routines):
      var records: [AlarmDeliveryRecord] = []

      for routine in routines {
        if let scheduleID = routine.alarmSchedule?.id {
          try await cancelSnoozes(scheduleID: scheduleID)
        }

        if let request = AlarmScheduleRequest(routine: routine) {
          records.append(try await synchronize(request))
        } else if let scheduleID = routine.alarmSchedule?.id,
                  let record = try stateRepository.record(scheduleID: scheduleID) {
          do {
            try await cancelAndDelete(record)
          } catch {
            records.append(try makeRepairRecord(from: record, error: error))
          }
        }
      }

      return AlarmMutationResult(records: records)

    case .delete(let scheduleID):
      try await cancelSnoozes(scheduleID: scheduleID)
      guard let record = try stateRepository.record(scheduleID: scheduleID) else {
        return .empty
      }

      try await cancelAndDelete(record)
      return .empty
    }
  }

  private func synchronize(
    _ request: AlarmScheduleRequest,
    platformSnapshots: [AlarmDeliveryBackend: AlarmPlatformSnapshot] = [:]
  ) async throws -> AlarmDeliveryRecord {
    let previousRecord = try stateRepository.record(scheduleID: request.scheduleID)

    if let previousRecord,
       previousRecord.request.fingerprint == request.fingerprint,
       previousRecord.state == .scheduled,
       recordExists(previousRecord, in: platformSnapshots) {
      return previousRecord
    }

    if let previousRecord,
       !previousRecord.platformIdentifiers.isEmpty {
      do {
        try await scheduler(for: previousRecord.backend).cancel(
          identifiers: previousRecord.platformIdentifiers
        )
      } catch {
        return try makeRepairRecord(
          from: previousRecord,
          request: request,
          error: error
        )
      }
    }

    let primaryAuthorization = await resolvedAuthorization(for: primaryScheduler)
    var primaryError: Error?

    if primaryAuthorization == .authorized {
      do {
        return try await schedule(
          request,
          using: primaryScheduler,
          previousRecord: previousRecord
        )
      } catch {
        primaryError = error
      }
    }

    let fallbackAuthorization = await resolvedAuthorization(for: fallbackScheduler)
    if fallbackAuthorization == .authorized {
      do {
        return try await schedule(
          request,
          using: fallbackScheduler,
          previousRecord: previousRecord
        )
      } catch {
        return try makeFailureRecord(
          request: request,
          primaryAuthorization: primaryAuthorization,
          fallbackAuthorization: fallbackAuthorization,
          error: error
        )
      }
    }

    return try makeFailureRecord(
      request: request,
      primaryAuthorization: primaryAuthorization,
      fallbackAuthorization: fallbackAuthorization,
      error: primaryError
    )
  }

  private func schedule(
    _ request: AlarmScheduleRequest,
    using scheduler: any AlarmScheduling,
    previousRecord: AlarmDeliveryRecord?
  ) async throws -> AlarmDeliveryRecord {
    let identifiers = try await scheduler.scheduleRecurring(request)
    let record = AlarmDeliveryRecord(
      request: request,
      backend: scheduler.backend,
      state: .scheduled,
      platformIdentifiers: identifiers,
      lastErrorMessage: nil,
      updatedAt: now()
    )

    do {
      try stateRepository.saveRecord(record)
      return record
    } catch {
      try? await scheduler.cancel(identifiers: identifiers)
      await restore(previousRecord)
      throw error
    }
  }

  private func restore(_ record: AlarmDeliveryRecord?) async {
    guard let record,
          let backend = record.backend,
          record.state == .scheduled else {
      return
    }

    let scheduler = backend == primaryScheduler.backend
      ? primaryScheduler
      : fallbackScheduler
    _ = try? await scheduler.scheduleRecurring(record.request)
  }

  private func makeFailureRecord(
    request: AlarmScheduleRequest,
    primaryAuthorization: AlarmAuthorizationState,
    fallbackAuthorization: AlarmAuthorizationState,
    error: Error?
  ) throws -> AlarmDeliveryRecord {
    let hasAuthorization = primaryAuthorization == .authorized
      || fallbackAuthorization == .authorized
    let record = AlarmDeliveryRecord(
      request: request,
      backend: nil,
      state: hasAuthorization ? .repairRequired : .authorizationRequired,
      platformIdentifiers: [],
      lastErrorMessage: error.map { String(describing: $0) },
      updatedAt: now()
    )
    try stateRepository.saveRecord(record)
    return record
  }

  private func makeRepairRecord(
    from record: AlarmDeliveryRecord,
    request: AlarmScheduleRequest? = nil,
    error: Error
  ) throws -> AlarmDeliveryRecord {
    let repairRecord = AlarmDeliveryRecord(
      request: request ?? record.request,
      backend: record.backend,
      state: .repairRequired,
      platformIdentifiers: record.platformIdentifiers,
      lastErrorMessage: String(describing: error),
      updatedAt: now()
    )
    try stateRepository.saveRecord(repairRecord)
    return repairRecord
  }

  private func cancelAndDelete(_ record: AlarmDeliveryRecord) async throws {
    try await cancelSnoozes(scheduleID: record.scheduleID)

    if !record.platformIdentifiers.isEmpty {
      try await scheduler(for: record.backend).cancel(
        identifiers: record.platformIdentifiers
      )
    }

    try stateRepository.deleteRecord(scheduleID: record.scheduleID)
  }

  private func resolvedAuthorization(
    for scheduler: any AlarmScheduling
  ) async -> AlarmAuthorizationState {
    let currentState = await scheduler.authorizationState()
    guard currentState == .notDetermined else {
      return currentState
    }

    return (try? await scheduler.requestAuthorization()) ?? .unavailable
  }

  private func scheduler(
    for backend: AlarmDeliveryBackend?
  ) -> any AlarmScheduling {
    backend == fallbackScheduler.backend ? fallbackScheduler : primaryScheduler
  }

  private func recordExists(
    _ record: AlarmDeliveryRecord,
    in snapshots: [AlarmDeliveryBackend: AlarmPlatformSnapshot]
  ) -> Bool {
    guard let backend = record.backend,
          let snapshot = snapshots[backend] else {
      return true
    }

    return Set(record.platformIdentifiers).isSubset(of: snapshot.identifiers)
  }

  private func reconcileWithoutLock() async {
    guard let routines = try? routineRepository.fetchRoutines(),
          let records = try? stateRepository.fetchRecords() else {
      return
    }

    let snapshots = await loadSnapshots()
    let desiredRequests = routines.compactMap(AlarmScheduleRequest.init)
    let desiredScheduleIDs = Set(desiredRequests.map(\.scheduleID))

    for request in desiredRequests {
      _ = try? await synchronize(request, platformSnapshots: snapshots)
    }

    for record in records where !desiredScheduleIDs.contains(record.scheduleID) {
      do {
        try await cancelAndDelete(record)
      } catch {
        _ = try? makeRepairRecord(from: record, error: error)
      }
    }

    let reconciledRecords = (try? stateRepository.fetchRecords()) ?? records
    await cancelOrphans(records: reconciledRecords, snapshots: snapshots)
  }

  private func loadSnapshots() async -> [AlarmDeliveryBackend: AlarmPlatformSnapshot] {
    var snapshots: [AlarmDeliveryBackend: AlarmPlatformSnapshot] = [:]

    if let snapshot = try? await primaryScheduler.snapshot() {
      snapshots[snapshot.backend] = snapshot
    }
    if let snapshot = try? await fallbackScheduler.snapshot() {
      snapshots[snapshot.backend] = snapshot
    }

    return snapshots
  }

  private func cancelOrphans(
    records: [AlarmDeliveryRecord],
    snapshots: [AlarmDeliveryBackend: AlarmPlatformSnapshot]
  ) async {
    let snoozedAlarms = (try? stateRepository.fetchSnoozedAlarms()) ?? []

    for scheduler in [primaryScheduler, fallbackScheduler] {
      guard let snapshot = snapshots[scheduler.backend] else {
        continue
      }

      let knownIdentifiers = Set(
        records
          .filter { $0.backend == scheduler.backend }
          .flatMap(\.platformIdentifiers)
          + snoozedAlarms
            .filter { $0.backend == scheduler.backend }
            .flatMap(\.platformIdentifiers)
      )
      let orphanIdentifiers = snapshot.identifiers.subtracting(knownIdentifiers)
      if !orphanIdentifiers.isEmpty {
        try? await scheduler.cancel(identifiers: orphanIdentifiers.sorted())
      }
    }
  }

  private func cancelAllWithoutLock() async throws {
    let records = try stateRepository.fetchRecords()
    let snapshots = try await [
      primaryScheduler.snapshot(),
      fallbackScheduler.snapshot(),
    ]

    for scheduler in [primaryScheduler, fallbackScheduler] {
      let persistedIdentifiers = records
        .filter { $0.backend == scheduler.backend }
        .flatMap(\.platformIdentifiers)
      let snapshotIdentifiers = snapshots
        .first { $0.backend == scheduler.backend }?
        .identifiers ?? []
      let identifiers = Set(persistedIdentifiers).union(snapshotIdentifiers)
      try await scheduler.cancel(identifiers: identifiers.sorted())
    }

    try stateRepository.deleteAllSnoozedAlarms()
    try stateRepository.deleteAllRecords()
  }

  private func cancelSnoozes(scheduleID: UUID) async throws {
    let snoozedAlarms = try stateRepository.fetchSnoozedAlarms()
      .filter { $0.scheduleID == scheduleID }

    for snoozedAlarm in snoozedAlarms {
      try await scheduler(for: snoozedAlarm.backend).cancel(
        identifiers: snoozedAlarm.platformIdentifiers
      )
      try stateRepository.deleteSnoozedAlarm(id: snoozedAlarm.id)
    }
  }
}
