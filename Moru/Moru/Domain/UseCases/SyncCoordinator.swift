//
//  SyncCoordinator.swift
//  Moru
//

import Foundation

nonisolated enum SyncTrigger: Equatable, Sendable {
  case appActive
  case loginSucceeded
  case sessionRestored
  case manual
}

nonisolated enum ServerMutationExecutionResult: Equatable, Sendable {
  case sent
  /// The queued operation remains untouched until an executor can handle it.
  case deferred
}

nonisolated protocol ServerMutationExecuting: Sendable {
  func execute(_ mutation: ServerMutation) async throws -> ServerMutationExecutionResult
}

nonisolated struct DeferredServerMutationExecutor: ServerMutationExecuting {
  func execute(_ mutation: ServerMutation) async throws -> ServerMutationExecutionResult {
    .deferred
  }
}

nonisolated enum ServerMutationRetryClassifier {
  static func classify(_ error: Error) -> ServerMutationFailure {
    guard let failureProvider = error as? any ServerMutationFailureProviding else {
      return .nonRetryable
    }

    return failureProvider.serverMutationFailure
  }
}

nonisolated enum ServerMutationBackoff {
  static let initialDelay: TimeInterval = 30
  static let maximumDelay: TimeInterval = 6 * 60 * 60

  static func delay(afterAttempt attempt: Int) -> TimeInterval {
    guard attempt > 1 else {
      return initialDelay
    }

    let exponent = min(attempt - 1, 20)
    return min(initialDelay * pow(2, Double(exponent)), maximumDelay)
  }
}

@MainActor
final class SyncCoordinator: ServerSynchronizing {
  private struct Flight {
    let id: UUID
    let task: Task<Void, Never>
  }

  private let mutationRepository: any ServerMutationRepository
  private let executor: any ServerMutationExecuting
  private let now: @Sendable () -> Date
  private var flights: [Int64: Flight] = [:]
  private var cancellationGenerations: [Int64: Int] = [:]
  private var suspendedMemberIDs: Set<Int64> = []

  init(
    mutationRepository: any ServerMutationRepository,
    executor: any ServerMutationExecuting,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.mutationRepository = mutationRepository
    self.executor = executor
    self.now = now
  }

  func synchronize(memberID: Int64, trigger: SyncTrigger) async {
    guard memberID > 0,
          !suspendedMemberIDs.contains(memberID) else {
      return
    }

    let cancellationGeneration = cancellationGenerations[
      memberID,
      default: 0
    ]
    if let flight = flights[memberID] {
      await flight.task.value
      clearFlight(memberID: memberID, matching: flight.id)
      guard !Task.isCancelled,
            cancellationGenerations[memberID, default: 0]
              == cancellationGeneration else {
        return
      }
      await synchronize(memberID: memberID, trigger: trigger)
      return
    }

    let flightID = UUID()
    let task = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      await runSynchronization(memberID: memberID, trigger: trigger)
    }
    flights[memberID] = Flight(id: flightID, task: task)

    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    clearFlight(memberID: memberID, matching: flightID)
  }

  func suspendSynchronization(memberID: Int64) async {
    suspendedMemberIDs.insert(memberID)
    cancellationGenerations[memberID, default: 0] += 1
    guard let flight = flights[memberID] else {
      return
    }

    flight.task.cancel()
    await flight.task.value
    clearFlight(memberID: memberID, matching: flight.id)
  }

  func resumeSynchronization(memberID: Int64) {
    suspendedMemberIDs.remove(memberID)
  }

  private func runSynchronization(
    memberID: Int64,
    trigger: SyncTrigger
  ) async {
    guard !Task.isCancelled else {
      return
    }

    let currentDate = now()
    let mutations: [ServerMutation]

    do {
      mutations = try mutationRepository.mutations(
        memberID: memberID,
        dueAt: currentDate,
        includeBlocked: trigger == .manual
      )
    } catch {
      return
    }

    for mutation in mutations {
      guard !Task.isCancelled else {
        return
      }

      do {
        switch try await executor.execute(mutation) {
        case .sent:
          try mutationRepository.removeSucceeded(mutation)
        case .deferred:
          return
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else {
          return
        }
        try? mutationRepository.recordFailure(
          ServerMutationRetryClassifier.classify(error),
          for: mutation,
          at: currentDate
        )
      }
    }
  }

  private func clearFlight(
    memberID: Int64,
    matching flightID: UUID
  ) {
    guard flights[memberID]?.id == flightID else {
      return
    }

    flights[memberID] = nil
  }
}
