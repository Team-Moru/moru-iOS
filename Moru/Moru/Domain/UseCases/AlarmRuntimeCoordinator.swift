//
//  AlarmRuntimeCoordinator.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation

@MainActor
final class DefaultAlarmRuntimeCoordinator: AlarmRuntimeHandling {
  static let snoozeOptions = [5, 10, 15, 30]

  private struct RuntimeTarget {
    let routine: Routine
    let backend: AlarmDeliveryBackend
  }

  private let routineRepository: any RoutineRepository
  private let stateRepository: any AlarmPlatformStateRepository
  private let primaryScheduler: any AlarmScheduling
  private let fallbackScheduler: any AlarmScheduling
  private let now: () -> Date
  private let makeID: () -> UUID
  private let maximumIngressAge: TimeInterval
  private let futureIngressTolerance: TimeInterval
  private let gate: AlarmMutationGate

  init(
    routineRepository: any RoutineRepository,
    stateRepository: any AlarmPlatformStateRepository,
    primaryScheduler: any AlarmScheduling,
    fallbackScheduler: any AlarmScheduling,
    now: @escaping () -> Date = Date.init,
    makeID: @escaping () -> UUID = UUID.init,
    maximumIngressAge: TimeInterval = 30 * 60,
    futureIngressTolerance: TimeInterval = 5 * 60,
    gate: AlarmMutationGate = AlarmMutationGate()
  ) {
    self.routineRepository = routineRepository
    self.stateRepository = stateRepository
    self.primaryScheduler = primaryScheduler
    self.fallbackScheduler = fallbackScheduler
    self.now = now
    self.makeID = makeID
    self.maximumIngressAge = maximumIngressAge
    self.futureIngressTolerance = futureIngressTolerance
    self.gate = gate
  }

  func resolve(_ envelope: AlarmIngressEnvelope) async -> AlarmIngressResolution {
    let age = now().timeIntervalSince(envelope.fireDate)
    guard age <= maximumIngressAge,
          age >= -futureIngressTolerance else {
      await discardStaleIngress(envelope)
      return .ignored(.stale)
    }

    do {
      let target = try runtimeTarget(for: envelope)
      return .route(
        AlarmRingContext(
          ingress: envelope,
          routineName: target.routine.name,
          routineMinutes: estimatedMinutes(for: target.routine)
        )
      )
    } catch let reason as AlarmIngressValidationError {
      await discardStaleIngress(envelope)
      return .ignored(reason.ignoredReason)
    } catch {
      return .temporarilyUnavailable
    }
  }

  func startRoutine(from context: AlarmRingContext) async throws {
    try await withMutationLock {
      try await startRoutineWithoutLock(from: context)
    }
  }

  func snooze(
    context: AlarmRingContext,
    minutes: Int
  ) async throws -> SnoozedAlarmRecord {
    try await withMutationLock {
      try await snoozeWithoutLock(context: context, minutes: minutes)
    }
  }

  private func startRoutineWithoutLock(
    from context: AlarmRingContext
  ) async throws {
    let target = try requiredTarget(for: context.ingress)

    do {
      try await scheduler(for: target.backend).stop(id: context.ingress.alarmID)
    } catch {
      throw AlarmRuntimeError.stopFailed
    }

    if context.ingress.kind == .snooze {
      try? stateRepository.deleteSnoozedAlarm(id: context.ingress.alarmID)
    }
  }

  private func snoozeWithoutLock(
    context: AlarmRingContext,
    minutes: Int
  ) async throws -> SnoozedAlarmRecord {
    guard Self.snoozeOptions.contains(minutes) else {
      throw AlarmRuntimeError.invalidSnoozeMinutes
    }

    let target = try requiredTarget(for: context.ingress)
    let replacedSnooze = try currentSnoozeRecord(for: context.ingress)
    let excludedID = context.ingress.kind == .snooze
      ? context.ingress.alarmID
      : nil
    try await cancelExistingSnoozes(
      scheduleID: context.ingress.scheduleID,
      excluding: excludedID
    )

    let request = AlarmSnoozeRequest(
      alarmID: makeID(),
      scheduleID: context.ingress.scheduleID,
      routineID: context.ingress.routineID,
      routineName: target.routine.name,
      fireDate: now().addingTimeInterval(TimeInterval(minutes * 60))
    )
    let scheduled = try await scheduleSnooze(request)
    let record = SnoozedAlarmRecord(
      id: request.alarmID,
      scheduleID: request.scheduleID,
      routineID: request.routineID,
      fireDate: request.fireDate,
      backend: scheduled.backend,
      platformIdentifiers: scheduled.identifiers,
      createdAt: now()
    )

    do {
      try stateRepository.replaceSnoozedAlarm(
        scheduleID: record.scheduleID,
        with: record
      )
    } catch {
      try? await scheduler(for: scheduled.backend).cancel(
        identifiers: scheduled.identifiers
      )
      throw AlarmRuntimeError.persistenceFailed
    }

    do {
      try await scheduler(for: target.backend).stop(id: context.ingress.alarmID)
    } catch {
      try await compensateFailedStop(
        newRecord: record,
        replacedSnooze: replacedSnooze
      )
      throw AlarmRuntimeError.stopFailed
    }

    return record
  }

  private func compensateFailedStop(
    newRecord: SnoozedAlarmRecord,
    replacedSnooze: SnoozedAlarmRecord?
  ) async throws {
    do {
      try await scheduler(for: newRecord.backend).cancel(
        identifiers: newRecord.platformIdentifiers
      )
    } catch {
      if let replacedSnooze {
        try? stateRepository.replaceSnoozedAlarm(
          scheduleID: replacedSnooze.scheduleID,
          with: replacedSnooze
        )
      }
      throw AlarmRuntimeError.cancellationFailed
    }

    do {
      if let replacedSnooze {
        try stateRepository.replaceSnoozedAlarm(
          scheduleID: replacedSnooze.scheduleID,
          with: replacedSnooze
        )
      } else {
        try stateRepository.deleteSnoozedAlarm(id: newRecord.id)
      }
    } catch {
      throw AlarmRuntimeError.persistenceFailed
    }
  }

  private func withMutationLock<Value>(
    _ operation: () async throws -> Value
  ) async throws -> Value {
    await gate.acquire()

    do {
      let value = try await operation()
      await gate.release()
      return value
    } catch {
      await gate.release()
      throw error
    }
  }

  private func runtimeTarget(
    for envelope: AlarmIngressEnvelope
  ) throws -> RuntimeTarget {
    guard let routine = try routineRepository.routine(id: envelope.routineID) else {
      throw AlarmIngressValidationError.routineUnavailable
    }
    guard routine.isActive else {
      throw AlarmIngressValidationError.routineInactive
    }
    guard let schedule = routine.alarmSchedule,
          schedule.isEnabled else {
      throw AlarmIngressValidationError.alarmDisabled
    }
    guard schedule.id == envelope.scheduleID else {
      throw AlarmIngressValidationError.scheduleMismatch
    }
    guard let delivery = try stateRepository.record(
      scheduleID: envelope.scheduleID
    ),
      delivery.routineID == envelope.routineID,
      delivery.state == .scheduled,
      let deliveryBackend = delivery.backend else {
      throw AlarmIngressValidationError.deliveryUnavailable
    }

    switch envelope.kind {
    case .recurring:
      guard envelope.alarmID == envelope.scheduleID else {
        throw AlarmIngressValidationError.scheduleMismatch
      }
      return RuntimeTarget(routine: routine, backend: deliveryBackend)

    case .snooze:
      guard let snooze = try stateRepository.fetchSnoozedAlarms()
        .first(where: { $0.id == envelope.alarmID }),
        snooze.scheduleID == envelope.scheduleID,
        snooze.routineID == envelope.routineID else {
        throw AlarmIngressValidationError.snoozeUnavailable
      }
      return RuntimeTarget(routine: routine, backend: snooze.backend)
    }
  }

  private func requiredTarget(
    for envelope: AlarmIngressEnvelope
  ) throws -> RuntimeTarget {
    do {
      return try runtimeTarget(for: envelope)
    } catch {
      throw AlarmRuntimeError.routeNoLongerAvailable
    }
  }

  private func scheduleSnooze(
    _ request: AlarmSnoozeRequest
  ) async throws -> (backend: AlarmDeliveryBackend, identifiers: [String]) {
    let primaryAuthorization = await resolvedAuthorization(for: primaryScheduler)
    var primarySchedulingFailed = false

    if primaryAuthorization == .authorized {
      do {
        let identifiers = try await primaryScheduler.scheduleSnooze(request)
        return (primaryScheduler.backend, identifiers)
      } catch {
        primarySchedulingFailed = true
      }
    }

    let fallbackAuthorization = await resolvedAuthorization(for: fallbackScheduler)
    guard fallbackAuthorization == .authorized else {
      throw primarySchedulingFailed
        ? AlarmRuntimeError.schedulingFailed
        : AlarmRuntimeError.authorizationRequired
    }

    do {
      let identifiers = try await fallbackScheduler.scheduleSnooze(request)
      return (fallbackScheduler.backend, identifiers)
    } catch {
      throw AlarmRuntimeError.schedulingFailed
    }
  }

  private func resolvedAuthorization(
    for scheduler: any AlarmScheduling
  ) async -> AlarmAuthorizationState {
    let state = await scheduler.authorizationState()
    guard state == .notDetermined else {
      return state
    }
    return (try? await scheduler.requestAuthorization()) ?? .unavailable
  }

  private func cancelExistingSnoozes(
    scheduleID: UUID,
    excluding excludedID: UUID?
  ) async throws {
    let records = try stateRepository.fetchSnoozedAlarms()
      .filter { $0.scheduleID == scheduleID && $0.id != excludedID }

    for record in records {
      do {
        try await scheduler(for: record.backend).cancel(
          identifiers: record.platformIdentifiers
        )
        try stateRepository.deleteSnoozedAlarm(id: record.id)
      } catch {
        throw AlarmRuntimeError.cancellationFailed
      }
    }
  }

  private func currentSnoozeRecord(
    for envelope: AlarmIngressEnvelope
  ) throws -> SnoozedAlarmRecord? {
    guard envelope.kind == .snooze else {
      return nil
    }
    return try stateRepository.fetchSnoozedAlarms()
      .first { $0.id == envelope.alarmID }
  }

  private func discardStaleIngress(_ envelope: AlarmIngressEnvelope) async {
    if envelope.kind == .snooze,
       let record = try? stateRepository.fetchSnoozedAlarms()
        .first(where: { $0.id == envelope.alarmID }) {
      try? await scheduler(for: record.backend).cancel(
        identifiers: record.platformIdentifiers
      )
      try? stateRepository.deleteSnoozedAlarm(id: record.id)
      return
    }

    if let record = try? stateRepository.record(
      scheduleID: envelope.scheduleID
    ),
      let backend = record.backend {
      try? await scheduler(for: backend).stop(id: envelope.alarmID)
      return
    }

    try? await primaryScheduler.stop(id: envelope.alarmID)
    try? await fallbackScheduler.stop(id: envelope.alarmID)
  }

  private func scheduler(
    for backend: AlarmDeliveryBackend
  ) -> any AlarmScheduling {
    backend == fallbackScheduler.backend ? fallbackScheduler : primaryScheduler
  }

  private func estimatedMinutes(for routine: Routine) -> Int {
    let seconds = routine.steps.reduce(0) { partialResult, step in
      partialResult + max(step.estimatedSeconds ?? 60, 0)
    }
    return max((seconds + 59) / 60, 1)
  }
}

private enum AlarmIngressValidationError: Error {
  case routineUnavailable
  case routineInactive
  case alarmDisabled
  case scheduleMismatch
  case deliveryUnavailable
  case snoozeUnavailable

  var ignoredReason: AlarmIngressIgnoredReason {
    switch self {
    case .routineUnavailable:
      .routineUnavailable
    case .routineInactive:
      .routineInactive
    case .alarmDisabled:
      .alarmDisabled
    case .scheduleMismatch:
      .scheduleMismatch
    case .deliveryUnavailable:
      .deliveryUnavailable
    case .snoozeUnavailable:
      .snoozeUnavailable
    }
  }
}
