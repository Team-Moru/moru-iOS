//
//  OnboardingStatusRuntimeCoordinator.swift
//  Moru
//

import Combine
import Foundation
import OSLog

nonisolated enum OnboardingStatusFallbackReason: Equatable, Sendable {
  case offline
  case timeout
  case cancelled
  case invalidResponse
  case accountAuthorizationChanged
  case server
  case transport
  case unavailable
}

nonisolated enum OnboardingStatusResolutionSource: Equatable, Sendable {
  case statusEndpoint
  case loginFallback(OnboardingStatusFallbackReason)
}

nonisolated enum OnboardingStatusMismatch: Equatable, Sendable {
  case loginResponse(loginCompleted: Bool, statusCompleted: Bool)
  case localState(localCompleted: Bool, serverCompleted: Bool)
  case localFallbackHint(localCompleted: Bool, loginCompleted: Bool)
}

/// Read-only reconciliation result for one exact account session.
///
/// A successful status response is newer than the login or restored-Keychain
/// hint. Neither source can replace the local profile, which remains the app's
/// routing and routine-data source of truth.
nonisolated struct OnboardingStatusResolution: Equatable, Sendable {
  let identity: AccountSessionIdentity
  let resolvedCompleted: Bool
  let source: OnboardingStatusResolutionSource
  let mismatches: [OnboardingStatusMismatch]
}

nonisolated enum OnboardingStatusDiagnostic: Equatable, Sendable {
  case fallback(
    identity: AccountSessionIdentity,
    reason: OnboardingStatusFallbackReason
  )
  case mismatch(
    identity: AccountSessionIdentity,
    mismatch: OnboardingStatusMismatch
  )
}

nonisolated protocol OnboardingStatusReporting: Sendable {
  func report(_ diagnostic: OnboardingStatusDiagnostic)
}

nonisolated struct OnboardingStatusLogger: OnboardingStatusReporting {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "OnboardingStatus"
  )

  func report(_ diagnostic: OnboardingStatusDiagnostic) {
    switch diagnostic {
    case .fallback(_, let reason):
      let reasonDescription = String(describing: reason)
      logger.info(
        "Onboarding status fallback: \(reasonDescription, privacy: .public)"
      )
    case .mismatch(_, let mismatch):
      let mismatchKind = switch mismatch {
      case .loginResponse:
        "loginResponse"
      case .localState:
        "localState"
      case .localFallbackHint:
        "localFallbackHint"
      }
      logger.notice(
        "Onboarding status mismatch: \(mismatchKind, privacy: .public)"
      )
    }
  }
}

/// Observes every account-session publication so a same-member re-login, which
/// creates a new `sessionID`, cannot be collapsed by Equatable state filtering.
/// The coordinator has no repository write dependency by design: reconciliation
/// can report differences but cannot delete or initialize local onboarding data.
@MainActor
final class OnboardingStatusRuntimeCoordinator {
  private let remoteService: any OnboardingStatusRemoteServing
  private let accountSessionStore: AccountSessionStore
  private let localCompletionProvider: @MainActor () -> Bool?
  private let reporter: any OnboardingStatusReporting

  private var stateObservation: AnyCancellable?
  private var requestTask: Task<Void, Never>?
  private var activeIdentity: AccountSessionIdentity?

  private(set) var latestResolution: OnboardingStatusResolution?

  init(
    remoteService: any OnboardingStatusRemoteServing,
    accountSessionStore: AccountSessionStore,
    localCompletionProvider: @escaping @MainActor () -> Bool?,
    reporter: any OnboardingStatusReporting = OnboardingStatusLogger()
  ) {
    self.remoteService = remoteService
    self.accountSessionStore = accountSessionStore
    self.localCompletionProvider = localCompletionProvider
    self.reporter = reporter
  }

  func start() {
    guard stateObservation == nil else {
      return
    }

    // Do not use `removeDuplicates()`: two equal SignedInAccount values may
    // represent different session generations after a same-member re-login.
    stateObservation = accountSessionStore.$state
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshForCurrentSession()
        }
      }
  }

  func stop() {
    stateObservation?.cancel()
    stateObservation = nil
    requestTask?.cancel()
    requestTask = nil
    activeIdentity = nil
    latestResolution = nil
  }

  private func refreshForCurrentSession() {
    guard case .signedIn(let account) = accountSessionStore.state,
          let identity = accountSessionStore.currentAccountSessionIdentity else {
      requestTask?.cancel()
      requestTask = nil
      activeIdentity = nil
      latestResolution = nil
      return
    }

    guard activeIdentity != identity else {
      return
    }

    requestTask?.cancel()
    activeIdentity = identity
    latestResolution = nil

    requestTask = Task { @MainActor [weak self] in
      await self?.resolve(
        identity: identity,
        loginCompleted: account.onboardingCompleted
      )
    }
  }

  private func resolve(
    identity: AccountSessionIdentity,
    loginCompleted: Bool
  ) async {
    do {
      let status = try await remoteService.fetchStatus(for: identity)
      guard !Task.isCancelled, isCurrent(identity) else {
        return
      }

      publish(
        identity: identity,
        resolvedCompleted: status.isCompleted,
        source: .statusEndpoint,
        loginCompleted: loginCompleted
      )
    } catch {
      guard !Task.isCancelled, isCurrent(identity) else {
        return
      }

      let reason = Self.fallbackReason(for: error)
      reporter.report(.fallback(identity: identity, reason: reason))
      publish(
        identity: identity,
        resolvedCompleted: loginCompleted,
        source: .loginFallback(reason),
        loginCompleted: loginCompleted
      )
    }
  }

  private func isCurrent(_ identity: AccountSessionIdentity) -> Bool {
    activeIdentity == identity
      && accountSessionStore.currentAccountSessionIdentity == identity
  }

  private func publish(
    identity: AccountSessionIdentity,
    resolvedCompleted: Bool,
    source: OnboardingStatusResolutionSource,
    loginCompleted: Bool
  ) {
    guard isCurrent(identity) else {
      return
    }

    var mismatches: [OnboardingStatusMismatch] = []
    if source == .statusEndpoint,
       loginCompleted != resolvedCompleted {
      mismatches.append(
        .loginResponse(
          loginCompleted: loginCompleted,
          statusCompleted: resolvedCompleted
        )
      )
    }

    // Read this after the request finishes. The user may have completed local
    // onboarding while the status request was in flight. A failed status call
    // has no server value, so identify any difference as a login-hint mismatch
    // instead of incorrectly reporting it as a server/local mismatch.
    if let localCompleted = localCompletionProvider(),
       localCompleted != resolvedCompleted {
      switch source {
      case .statusEndpoint:
        mismatches.append(
          .localState(
            localCompleted: localCompleted,
            serverCompleted: resolvedCompleted
          )
        )
      case .loginFallback:
        mismatches.append(
          .localFallbackHint(
            localCompleted: localCompleted,
            loginCompleted: resolvedCompleted
          )
        )
      }
    }

    let resolution = OnboardingStatusResolution(
      identity: identity,
      resolvedCompleted: resolvedCompleted,
      source: source,
      mismatches: mismatches
    )
    latestResolution = resolution

    for mismatch in mismatches {
      reporter.report(.mismatch(identity: identity, mismatch: mismatch))
    }
  }

  nonisolated private static func fallbackReason(
    for error: Error
  ) -> OnboardingStatusFallbackReason {
    if error is CancellationError {
      return .cancelled
    }
    if let remoteError = error as? OnboardingStatusRemoteError {
      switch remoteError {
      case .invalidRequest, .invalidResponse:
        return .invalidResponse
      case .accountAuthorizationChanged:
        return .accountAuthorizationChanged
      }
    }
    if let apiError = error as? APIError {
      switch apiError {
      case .cancelled:
        return .cancelled
      case .transport(let code, _):
        return transportFallbackReason(code: code)
      case .decoding, .missingResult:
        return .invalidResponse
      case .server:
        return .server
      case .invalidRequest, .authenticationRequired, .capabilityDisabled:
        return .unavailable
      }
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      return transportFallbackReason(code: nsError.code)
    }
    return .unavailable
  }

  nonisolated private static func transportFallbackReason(
    code: Int
  ) -> OnboardingStatusFallbackReason {
    if code == URLError.timedOut.rawValue {
      return .timeout
    }

    let offlineCodes: Set<Int> = [
      URLError.notConnectedToInternet.rawValue,
      URLError.networkConnectionLost.rawValue,
      URLError.cannotFindHost.rawValue,
      URLError.cannotConnectToHost.rawValue,
      URLError.dnsLookupFailed.rawValue,
      URLError.internationalRoamingOff.rawValue,
      URLError.callIsActive.rawValue,
      URLError.dataNotAllowed.rawValue,
    ]
    return offlineCodes.contains(code) ? .offline : .transport
  }
}
