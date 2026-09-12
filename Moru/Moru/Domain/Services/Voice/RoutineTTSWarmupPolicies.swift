//
//  RoutineTTSWarmupPolicies.swift
//  Moru
//

import Foundation

/// A bounded retry window used only when a user is about to hear a
/// server-generated routine. Background warming intentionally remains a
/// single request so foregrounding many routines cannot amplify traffic.
nonisolated struct RoutineTTSForegroundPollingPolicy: Equatable, Sendable {
  let maximumAttempts: Int
  let retryDelay: Duration
  let maximumWait: Duration

  init(
    maximumAttempts: Int = 31,
    retryDelay: Duration = .seconds(1),
    maximumWait: Duration = .seconds(30)
  ) {
    precondition(maximumAttempts > 0)
    precondition(maximumWait > .zero)
    self.maximumAttempts = maximumAttempts
    self.retryDelay = retryDelay
    self.maximumWait = maximumWait
  }
}

/// 파일 분리 전에는 `private`이었다. 쓰는 쪽은 여전히 코디네이터 하나뿐이다.
actor RoutineTTSForegroundWaitGate {
  private var result: RoutineTTSForegroundPreparationStatus?
  private var continuation:
    CheckedContinuation<RoutineTTSForegroundPreparationStatus, Never>?

  func value() async -> RoutineTTSForegroundPreparationStatus {
    if let result {
      return result
    }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resolve(_ result: RoutineTTSForegroundPreparationStatus) {
    guard self.result == nil else { return }
    self.result = result
    continuation?.resume(returning: result)
    continuation = nil
  }
}

nonisolated struct RoutineTTSPrefetchPollingPolicy: Sendable {
  let maximumAttempts: Int
  let retryDelays: [Duration]
  let now: @Sendable () -> Date
  let sleep: @Sendable (Duration) async throws -> Void

  init(
    maximumAttempts: Int = 4,
    retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)],
    now: @escaping @Sendable () -> Date = Date.init,
    sleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) {
    precondition(maximumAttempts > 0)
    precondition(retryDelays.count >= max(0, maximumAttempts - 1))
    self.maximumAttempts = maximumAttempts
    self.retryDelays = retryDelays
    self.now = now
    self.sleep = sleep
  }
}
