//
//  SyncCoordinator.swift
//  Moru
//

import Foundation

nonisolated enum SyncTrigger: Equatable, Sendable {
  case appActive
  case loginSucceeded
  case manual
}

nonisolated enum ServerMutationExecutionResult: Equatable, Sendable {
  case sent
  /// P6 has no server Target. The queued operation stays untouched until P7 installs an executor.
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
    guard let apiError = error as? APIError else {
      return .nonRetryable
    }

    switch apiError {
    case .transport:
      return .transport
    case .server(let statusCode, _, _) where statusCode == 408:
      return .requestTimeout
    case .server(let statusCode, _, _) where statusCode == 429:
      return .rateLimited
    case .server(let statusCode, _, _) where (500..<600).contains(statusCode):
      return .serverUnavailable
    case .invalidRequest,
         .authenticationRequired,
         .capabilityDisabled,
         .server,
         .decoding,
         .missingResult,
         .cancelled:
      return .nonRetryable
    }
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
final class SyncCoordinator {
  private let mutationRepository: any ServerMutationRepository
  private let executor: any ServerMutationExecuting
  private let now: @Sendable () -> Date
  private var syncingMemberIDs: Set<Int64> = []

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
    guard memberID > 0, syncingMemberIDs.insert(memberID).inserted else {
      return
    }
    defer { syncingMemberIDs.remove(memberID) }

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
        try? mutationRepository.recordFailure(
          ServerMutationRetryClassifier.classify(error),
          for: mutation,
          at: currentDate
        )
      }
    }
  }
}
