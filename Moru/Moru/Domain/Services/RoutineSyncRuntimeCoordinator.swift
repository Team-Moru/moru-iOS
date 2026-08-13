//
//  RoutineSyncRuntimeCoordinator.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineSyncSending: AnyObject {
  func sendNext(
    memberID: Int64,
    at date: Date
  ) async throws -> RoutineSyncSendResult
}

extension RoutineSyncSender: RoutineSyncSending {}

@MainActor
protocol RoutineSyncRuntimeScheduling: AnyObject {
  var now: Date { get }

  func sleep(until date: Date) async throws
}

@MainActor
final class SystemRoutineSyncRuntimeScheduler: RoutineSyncRuntimeScheduling {
  static let shared = SystemRoutineSyncRuntimeScheduler()

  var now: Date { Date() }

  func sleep(until date: Date) async throws {
    let interval = max(0, date.timeIntervalSince(now))
    guard interval > 0 else { return }

    let nanoseconds = UInt64(
      min(interval * 1_000_000_000, Double(UInt64.max))
    )
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}

nonisolated enum RoutineSyncRuntimeStopReason: Equatable, Sendable {
  case inactive
  case signedOut
  case idle
  case blocked(RoutineSyncBlockReason)
  case staleSession
  case runtimeFailure
}

/// Foreground-only, account-bound serial drain for the durable routine Outbox.
///
/// This type owns scheduling only. Request bytes, idempotency keys, settlement,
/// and stale-response protection stay inside `RoutineSyncSender` and its
/// repository. No token or request body crosses this runtime boundary.
@MainActor
final class RoutineSyncRuntimeCoordinator {
  private let sender: any RoutineSyncSending
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let scheduler: any RoutineSyncRuntimeScheduling
  private let unscheduledRetryDelay: TimeInterval
  private let onMutationCompleted: @MainActor () -> Void

  private var drainTask: Task<Void, Never>?
  private var drainGeneration = 0
  private var wakePending = false
  private var sessionRestartPending = false

  private(set) var isSceneActive: Bool
  private(set) var isDraining = false
  private(set) var lastStopReason: RoutineSyncRuntimeStopReason?

  init(
    sender: any RoutineSyncSending,
    sessionIdentityProvider: any CurrentAccountSessionIdentityProviding,
    wakeupRelay: RoutineSyncWakeupRelay? = nil,
    scheduler: any RoutineSyncRuntimeScheduling =
      SystemRoutineSyncRuntimeScheduler.shared,
    isSceneActive: Bool = false,
    unscheduledRetryDelay: TimeInterval = 1,
    onMutationCompleted: @escaping @MainActor () -> Void = {}
  ) {
    precondition(unscheduledRetryDelay > 0)
    self.sender = sender
    self.sessionIdentityProvider = sessionIdentityProvider
    self.scheduler = scheduler
    self.isSceneActive = isSceneActive
    self.unscheduledRetryDelay = unscheduledRetryDelay
    self.onMutationCompleted = onMutationCompleted

    wakeupRelay?.setHandler { [weak self] in
      self?.wake()
    }
  }

  func setSceneActive(_ isActive: Bool) {
    guard isSceneActive != isActive else {
      if isActive { wake() }
      return
    }

    isSceneActive = isActive
    if isActive {
      wake()
    } else {
      wakePending = false
      sessionRestartPending = false
      lastStopReason = .inactive
      drainTask?.cancel()
    }
  }

  /// Call after the account session state or session generation changes.
  /// A running old-session drain is cancelled and a distinct new-session drain
  /// starts only after the old drain has stopped.
  func accountSessionDidChange() {
    guard isSceneActive else {
      lastStopReason = .inactive
      return
    }
    guard sessionIdentityProvider?.currentAccountSessionIdentity != nil else {
      wakePending = false
      sessionRestartPending = false
      lastStopReason = .signedOut
      drainTask?.cancel()
      return
    }

    if isDraining {
      sessionRestartPending = true
      drainTask?.cancel()
    } else {
      wake()
    }
  }

  /// Coalesces any number of wakeups into the current serial drain.
  func wake() {
    wakePending = true
    startDrainIfEligible()
  }

  private func startDrainIfEligible() {
    guard !isDraining else { return }
    guard isSceneActive else {
      wakePending = false
      lastStopReason = .inactive
      return
    }
    guard let identity = sessionIdentityProvider?
      .currentAccountSessionIdentity else {
      wakePending = false
      lastStopReason = .signedOut
      return
    }

    wakePending = false
    isDraining = true
    lastStopReason = nil
    drainGeneration += 1
    let generation = drainGeneration

    drainTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.drain(identity: identity)
      self.finishDrain(generation: generation)
    }
  }

  private func drain(identity: AccountSessionIdentity) async {
    while !Task.isCancelled {
      guard isSceneActive else {
        lastStopReason = .inactive
        return
      }
      guard sessionIdentityProvider?.currentAccountSessionIdentity
        == identity else {
        lastStopReason = .staleSession
        return
      }

      // A wake received after this point is observed when the send suspends.
      wakePending = false

      let result: RoutineSyncSendResult
      do {
        result = try await sender.sendNext(
          memberID: identity.memberID,
          at: scheduler.now
        )
      } catch is CancellationError {
        return
      } catch {
        wakePending = false
        lastStopReason = .runtimeFailure
        return
      }

      switch result {
      case .completed:
        onMutationCompleted()
        continue

      case .retryScheduled(_, let nextAttemptAt):
        let retryAt = nextAttemptAt
          ?? scheduler.now.addingTimeInterval(unscheduledRetryDelay)
        do {
          try await scheduler.sleep(until: retryAt)
        } catch is CancellationError {
          return
        } catch {
          wakePending = false
          lastStopReason = .runtimeFailure
          return
        }

      case .idle:
        if wakePending {
          continue
        }
        lastStopReason = .idle
        return

      case .blocked(_, let reason):
        wakePending = false
        lastStopReason = .blocked(reason)
        return

      case .staleSession:
        wakePending = false
        lastStopReason = .staleSession
        return
      }
    }
  }

  private func finishDrain(generation: Int) {
    guard drainGeneration == generation else { return }
    drainTask = nil
    isDraining = false

    if sessionRestartPending {
      sessionRestartPending = false
      wakePending = true
    }
    if wakePending {
      startDrainIfEligible()
    }
  }
}
