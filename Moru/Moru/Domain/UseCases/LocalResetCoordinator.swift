//
//  LocalResetCoordinator.swift
//  Moru
//

import Foundation

nonisolated
enum LocalResetCoordinatorError: Error, Equatable, LocalizedError {
  case journal(LocalResetJournalStoreError)
  case journalFailure(String)
  case inventory(String)
  case cancellation(String)
  case deletion(String)
  case coordinatorClear(String)

  var errorDescription: String? {
    switch self {
    case .journal(let error):
      return error.localizedDescription
    case .journalFailure(let reason):
      return "Local reset journal failed: \(reason)."
    case .inventory(let reason):
      return "Local reset schedule inventory failed: \(reason)."
    case .cancellation(let reason):
      return "Local reset notification cancellation failed: \(reason)."
    case .deletion(let reason):
      return "Local reset data deletion failed: \(reason)."
    case .coordinatorClear(let reason):
      return "Local reset coordinator clear failed: \(reason)."
    }
  }
}

@MainActor
final class LocalResetCoordinator {
  private let alarmMutator: any AlarmScheduleMutating
  private let resetRepository: any LocalResetDataRepository
  private let journalStore: any LocalResetJournalStoring
  private let now: @MainActor () -> Date
  private let makeUUID: @MainActor () -> UUID
  private let clearCoordinator: @MainActor (UUID) async throws -> Void
  private var inFlightReset: Task<UUID, Error>?

  init(
    alarmMutator: any AlarmScheduleMutating,
    resetRepository: any LocalResetDataRepository,
    journalStore: any LocalResetJournalStoring,
    now: @escaping @MainActor () -> Date = { Date() },
    makeUUID: @escaping @MainActor () -> UUID = { UUID() },
    clearCoordinator: @escaping @MainActor (UUID) async throws -> Void
  ) {
    self.alarmMutator = alarmMutator
    self.resetRepository = resetRepository
    self.journalStore = journalStore
    self.now = now
    self.makeUUID = makeUUID
    self.clearCoordinator = clearCoordinator
  }

  @discardableResult
  func reset() async throws -> UUID {
    if let inFlightReset {
      return try await inFlightReset.value
    }

    let task = Task { @MainActor [weak self] in
      guard let self else {
        throw CancellationError()
      }
      return try await self.performReset()
    }
    inFlightReset = task
    defer { inFlightReset = nil }
    return try await task.value
  }

  private func performReset() async throws -> UUID {
    let freezeToken: AlarmMutationFreezeToken
    do {
      freezeToken = try await alarmMutator.freezeAndDrain()
    } catch {
      throw LocalResetCoordinatorError.cancellation(error.localizedDescription)
    }
    defer {
      alarmMutator.thaw(freezeToken)
    }

    let operationID = makeUUID()
    let startedAt = now()
    var entry = try journal {
      try journalStore.begin(operationID: operationID, at: startedAt)
    }

    while true {
      switch entry.phase {
      case .freezeRequested:
        let advancedAt = now()
        entry = try journal {
          try journalStore.advance(
            operationID: entry.operationID,
            to: .gathering,
            at: advancedAt
          )
        }

      case .gathering:
        let scheduleIDs: [UUID]
        do {
          scheduleIDs = try resetRepository.inventoryScheduleIDs()
        } catch {
          try recordRetry(operationID: entry.operationID, resuming: .gathering)
          throw LocalResetCoordinatorError.inventory(error.localizedDescription)
        }

        let sealedAt = now()
        entry = try journal {
          try journalStore.seal(
            operationID: entry.operationID,
            scheduleIDs: scheduleIDs,
            at: sealedAt
          )
        }

      case .sealed:
        try preflightAdvance(operationID: entry.operationID, to: .cancelling)
        let advancedAt = now()
        entry = try journal {
          try journalStore.advance(
            operationID: entry.operationID,
            to: .cancelling,
            at: advancedAt
          )
        }

      case .cancelling:
        try preflightAdvance(operationID: entry.operationID, to: .swiftDataDeleting)
        do {
          try await alarmMutator.cancelAll(
            scheduleIDs: entry.sealedScheduleIDs,
            using: freezeToken
          )
        } catch {
          try recordRetry(operationID: entry.operationID, resuming: .cancelling)
          throw LocalResetCoordinatorError.cancellation(error.localizedDescription)
        }

        let advancedAt = now()
        entry = try journal {
          try journalStore.advance(
            operationID: entry.operationID,
            to: .swiftDataDeleting,
            at: advancedAt
          )
        }

      case .swiftDataDeleting:
        try preflightAdvance(operationID: entry.operationID, to: .coordinatorClearing)
        do {
          try resetRepository.deleteAll()
        } catch {
          try recordRetry(operationID: entry.operationID, resuming: .swiftDataDeleting)
          throw LocalResetCoordinatorError.deletion(error.localizedDescription)
        }

        let advancedAt = now()
        entry = try journal {
          try journalStore.advance(
            operationID: entry.operationID,
            to: .coordinatorClearing,
            at: advancedAt
          )
        }

      case .coordinatorClearing:
        try preflightAdvance(operationID: entry.operationID, to: .completed)
        do {
          try await clearCoordinator(entry.operationID)
        } catch {
          try recordRetry(operationID: entry.operationID, resuming: .coordinatorClearing)
          throw LocalResetCoordinatorError.coordinatorClear(error.localizedDescription)
        }

        let completedAt = now()
        entry = try journal {
          try journalStore.advance(
            operationID: entry.operationID,
            to: .completed,
            at: completedAt
          )
        }

      case .retryRequired:
        let resumedAt = now()
        entry = try journal {
          try journalStore.resume(operationID: entry.operationID, at: resumedAt)
        }

      case .completed:
        return entry.operationID
      }
    }
  }

  private func recordRetry(
    operationID: UUID,
    resuming phase: LocalResetJournalPhase
  ) throws {
    let retryAt = now()
    _ = try journal {
      try journalStore.markRetryRequired(
        operationID: operationID,
        resuming: phase,
        at: retryAt
      )
    }
  }
  private func preflightAdvance(
    operationID: UUID,
    to phase: LocalResetJournalPhase
  ) throws {
    try journal {
      try journalStore.preflightAdvance(operationID: operationID, to: phase)
    }
  }

  private func journal<Value>(_ operation: () throws -> Value) throws -> Value {
    do {
      return try operation()
    } catch let error as LocalResetJournalStoreError {
      throw LocalResetCoordinatorError.journal(error)
    } catch {
      throw LocalResetCoordinatorError.journalFailure(error.localizedDescription)
    }
  }
}
