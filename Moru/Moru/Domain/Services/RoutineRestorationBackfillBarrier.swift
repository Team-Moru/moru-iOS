//
//  RoutineRestorationBackfillBarrier.swift
//  Moru
//

import Foundation

/// Exact-session barrier shared by onboarding-status restoration and the
/// routine sync runtime. Unknown sessions are pending by default, which makes
/// coordinator scheduling order irrelevant.
@MainActor
final class RoutineRestorationBackfillBarrier {
  private var pendingIdentity: AccountSessionIdentity?
  private var resolvedIdentity: AccountSessionIdentity?
  private var resolutionHandler:
    (@MainActor (AccountSessionIdentity) -> Void)?

  func begin(for identity: AccountSessionIdentity) {
    pendingIdentity = identity
    resolvedIdentity = nil
  }

  func resolve(for identity: AccountSessionIdentity) {
    guard pendingIdentity == identity else { return }
    pendingIdentity = nil
    resolvedIdentity = identity
    resolutionHandler?(identity)
  }

  func cancel(for identity: AccountSessionIdentity) {
    if pendingIdentity == identity {
      pendingIdentity = nil
    }
    if resolvedIdentity == identity {
      resolvedIdentity = nil
    }
  }

  func allowsBackfill(for identity: AccountSessionIdentity) -> Bool {
    resolvedIdentity == identity
  }

  func isPending(for identity: AccountSessionIdentity) -> Bool {
    pendingIdentity == identity
  }

  func setResolutionHandler(
    _ handler: @escaping @MainActor (AccountSessionIdentity) -> Void
  ) {
    resolutionHandler = handler
  }
}
