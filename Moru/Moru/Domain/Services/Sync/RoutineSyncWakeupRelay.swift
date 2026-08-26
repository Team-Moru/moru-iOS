//
//  RoutineSyncWakeupRelay.swift
//  Moru
//

import Foundation

/// Small dependency-injection seam used by local repositories to wake the
/// sync runtime only after their SwiftData transaction has committed.
///
/// The relay intentionally carries no account, token, command, or request
/// data. Runtime eligibility is checked again by `RoutineSyncRuntimeCoordinator`.
@MainActor
final class RoutineSyncWakeupRelay {
  typealias Handler = @MainActor @Sendable () -> Void

  private var handler: Handler?

  func setHandler(_ handler: @escaping Handler) {
    self.handler = handler
  }

  func removeHandler() {
    handler = nil
  }

  func wake() {
    handler?()
  }
}
