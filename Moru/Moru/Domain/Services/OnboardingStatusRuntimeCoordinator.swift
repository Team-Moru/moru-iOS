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

nonisolated enum ServerRoutineRestorationRuntimeState:
  Equatable,
  Sendable {
  case idle
  case loading(AccountSessionIdentity)
  case restored(AccountSessionIdentity, routineCount: Int)
  case localDataPresent(AccountSessionIdentity)
  case onboardingRequired(AccountSessionIdentity)
  case failed(AccountSessionIdentity)
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
/// Status reconciliation remains read-only for existing local users. When the
/// optional restorer proves that both the local profile and routine stores are
/// empty, a successful server status can initialize them without merging or
/// replacing any local state.
@MainActor
final class OnboardingStatusRuntimeCoordinator {
  private let remoteService: any OnboardingStatusRemoteServing
  private let accountSessionStore: AccountSessionStore
  private let localCompletionProvider: @MainActor () -> Bool?
  private let routineRestorer: (any ServerRoutineRestoring)?
  private let onRestorationBegan: @MainActor () -> Void
  private let onRestorationFinished: @MainActor () -> Void
  private let reporter: any OnboardingStatusReporting

  private var stateObservation: AnyCancellable?
  private var requestTask: Task<Void, Never>?
  private var activeIdentity: AccountSessionIdentity?
  private var restorationLoadingIdentity: AccountSessionIdentity?

  private(set) var latestResolution: OnboardingStatusResolution?
  private(set) var restorationState: ServerRoutineRestorationRuntimeState = .idle

  init(
    remoteService: any OnboardingStatusRemoteServing,
    accountSessionStore: AccountSessionStore,
    localCompletionProvider: @escaping @MainActor () -> Bool?,
    routineRestorer: (any ServerRoutineRestoring)? = nil,
    onRestorationBegan: @escaping @MainActor () -> Void = {},
    onRestorationFinished: @escaping @MainActor () -> Void = {},
    reporter: any OnboardingStatusReporting = OnboardingStatusLogger()
  ) {
    self.remoteService = remoteService
    self.accountSessionStore = accountSessionStore
    self.localCompletionProvider = localCompletionProvider
    self.routineRestorer = routineRestorer
    self.onRestorationBegan = onRestorationBegan
    self.onRestorationFinished = onRestorationFinished
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
    let wasRestoring = restorationLoadingIdentity != nil
    stateObservation?.cancel()
    stateObservation = nil
    requestTask?.cancel()
    requestTask = nil
    activeIdentity = nil
    restorationLoadingIdentity = nil
    latestResolution = nil
    restorationState = .idle
    if wasRestoring {
      onRestorationFinished()
    }
  }

  private func refreshForCurrentSession() {
    guard case .signedIn(let account) = accountSessionStore.state,
          let identity = accountSessionStore.currentAccountSessionIdentity else {
      let wasRestoring = restorationLoadingIdentity != nil
      requestTask?.cancel()
      requestTask = nil
      activeIdentity = nil
      restorationLoadingIdentity = nil
      latestResolution = nil
      restorationState = .idle
      if wasRestoring {
        onRestorationFinished()
      }
      return
    }

    guard activeIdentity != identity else {
      return
    }

    requestTask?.cancel()
    activeIdentity = identity
    latestResolution = nil

    let shouldAttemptRestoration: Bool
    let restorationEligibilityFailed: Bool
    do {
      shouldAttemptRestoration = try routineRestorer?
        .isLocalProfileAndRoutineStoreEmpty() ?? false
      restorationEligibilityFailed = false
    } catch {
      shouldAttemptRestoration = false
      restorationEligibilityFailed = true
      restorationState = .failed(identity)
    }

    if shouldAttemptRestoration {
      let wasAlreadyRestoring = restorationLoadingIdentity != nil
      restorationLoadingIdentity = identity
      restorationState = .loading(identity)
      if !wasAlreadyRestoring {
        onRestorationBegan()
      }
    } else {
      if !restorationEligibilityFailed, routineRestorer != nil {
        restorationState = .localDataPresent(identity)
      }
      if restorationLoadingIdentity != nil {
        restorationLoadingIdentity = nil
        onRestorationFinished()
      }
    }

    requestTask = Task { @MainActor [weak self] in
      await self?.resolve(
        identity: identity,
        loginCompleted: account.onboardingCompleted,
        shouldAttemptRestoration: shouldAttemptRestoration
      )
    }
  }

  private func resolve(
    identity: AccountSessionIdentity,
    loginCompleted: Bool,
    shouldAttemptRestoration: Bool
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

      guard shouldAttemptRestoration else {
        return
      }
      guard status.isCompleted else {
        restorationState = .onboardingRequired(identity)
        finishRestorationLoading(for: identity)
        return
      }
      guard let routineRestorer else {
        restorationState = .failed(identity)
        finishRestorationLoading(for: identity)
        return
      }

      do {
        let result = try await routineRestorer.restoreIfLocalStoreIsEmpty(
          for: identity
        )
        guard !Task.isCancelled, isCurrent(identity) else {
          return
        }
        switch result {
        case .restored(let routineCount):
          restorationState = .restored(
            identity,
            routineCount: routineCount
          )
        case .localDataPresent:
          restorationState = .localDataPresent(identity)
        }
        finishRestorationLoading(for: identity)
      } catch {
        guard !Task.isCancelled, isCurrent(identity) else {
          return
        }
        restorationState = .failed(identity)
        finishRestorationLoading(for: identity)
      }
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
      if shouldAttemptRestoration {
        restorationState = .failed(identity)
        finishRestorationLoading(for: identity)
      }
    }
  }

  private func finishRestorationLoading(
    for identity: AccountSessionIdentity
  ) {
    guard restorationLoadingIdentity == identity else {
      return
    }
    restorationLoadingIdentity = nil
    onRestorationFinished()
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
      case .invalidRequest:
        return .unavailable
      case .invalidResponse:
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
