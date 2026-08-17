//
//  AccountLifecycle.swift
//  Moru
//

import Foundation

nonisolated protocol AccountScopedDataCleaning: Sendable {
  func removeAccountScopedData(memberID: Int64) async throws
  func preparePendingAccountCleanup(memberID: Int64) async throws
  func beginPendingAccountCleanupAttempt(memberID: Int64) async throws
  func confirmPendingAccountCleanup(memberID: Int64) async throws
  func cancelPendingAccountCleanup(memberID: Int64) async throws
  func completePendingAccountCleanup(memberID: Int64) async throws
  func finalizePendingAccountCleanup(memberID: Int64) async throws
  func recoverPendingAccountCleanups() async throws -> PendingAccountCleanupRecovery
}

nonisolated extension AccountScopedDataCleaning {
  func preparePendingAccountCleanup(memberID: Int64) async throws {}
  func beginPendingAccountCleanupAttempt(memberID: Int64) async throws {}
  func confirmPendingAccountCleanup(memberID: Int64) async throws {}
  func cancelPendingAccountCleanup(memberID: Int64) async throws {}
  func completePendingAccountCleanup(memberID: Int64) async throws {
    try await removeAccountScopedData(memberID: memberID)
  }
  func finalizePendingAccountCleanup(memberID: Int64) async throws {}
  func recoverPendingAccountCleanups() async throws -> PendingAccountCleanupRecovery {
    .none
  }
}

/// Preview and test graphs without account-scoped persistence use this cleaner.
nonisolated struct NoAccountScopedDataCleaner: AccountScopedDataCleaning {
  func removeAccountScopedData(memberID: Int64) async throws {}
}

nonisolated enum AccountLifecycleError: Error, Equatable, Sendable {
  case sessionUnavailable
  case localCleanupFailed
  case withdrawalStateUnavailable
  case appleReauthenticationRequired
}

nonisolated enum SocialProviderSessionSignOutReason: Equatable, Sendable {
  case logout
  case withdrawal
}

@MainActor
protocol SocialProviderSessionSigningOut: AnyObject {
  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws
}

@MainActor
final class NoopSocialProviderSessionSignOut:
  SocialProviderSessionSigningOut {
  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws {}
}

@MainActor
final class SocialProviderSessionSignOutRouter:
  SocialProviderSessionSigningOut {
  private let handlers: [AuthProvider: any SocialProviderSessionSigningOut]

  init(handlers: [AuthProvider: any SocialProviderSessionSigningOut]) {
    self.handlers = handlers
  }

  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws {
    try await handlers[provider]?.signOut(provider: provider, reason: reason)
  }
}

@MainActor
protocol AccountLifecycleManaging: AnyObject {
  func logout() async throws
  func withdraw() async throws
  func reauthenticateAppleWithdrawal(
    with authorization: SocialAuthorization
  ) async throws
}

@MainActor
final class DefaultAccountLifecycleService: AccountLifecycleManaging {
  private let authRemoteDataSource: any AuthRemoteDataSource
  private let accountSessionStore: AccountSessionStore
  private let accountScopedDataCleaner: any AccountScopedDataCleaning
  private let providerSessionSignOut: any SocialProviderSessionSigningOut
  private let routineTTSAudioCacheCleaner:
    (any RoutineTTSAudioCacheCleaning)?
  private var withdrawalTask: Task<Void, Error>?

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning,
    providerSessionSignOut: any SocialProviderSessionSigningOut =
      NoopSocialProviderSessionSignOut(),
    routineTTSAudioCacheCleaner:
      (any RoutineTTSAudioCacheCleaning)? = nil
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
    self.accountScopedDataCleaner = accountScopedDataCleaner
    self.providerSessionSignOut = providerSessionSignOut
    self.routineTTSAudioCacheCleaner = routineTTSAudioCacheCleaner
  }

  func logout() async throws {
    guard !accountSessionStore.isWithdrawalPending,
          accountSessionStore.beginAccountLifecycleOperation(.logout) else {
      // A competing lifecycle operation owns the exact credential until its
      // remote and local settlement has finished.
      throw AccountLifecycleError.sessionUnavailable
    }
    defer { accountSessionStore.endAccountLifecycleOperation(.logout) }

    let credentials = try? accountSessionStore.credentialsForAccountLifecycle()
    let provider = credentials?.provider ?? accountSessionStore.signedInProvider
    let memberID = credentials?.memberID ?? accountSessionStore.signedInMemberID

    if let refreshToken = credentials?.refreshToken {
      try? await authRemoteDataSource.logout(refreshToken: refreshToken)
    }
    if let provider {
      try? await providerSessionSignOut.signOut(
        provider: provider,
        reason: .logout
      )
    }

    if let memberID, let routineTTSAudioCacheCleaner {
      do {
        // Purge before credentials are removed. If the process dies here, the
        // account is still restorable and a later logout can retry; the inverse
        // order could orphan account audio with no durable cleanup marker.
        try await routineTTSAudioCacheCleaner.removeRoutineTTSAudio(
          memberID: memberID
        )
      } catch {
        throw AccountLifecycleError.localCleanupFailed
      }
    }

    do {
      try accountSessionStore.removeLocalAccountSession()
    } catch {
      throw AccountLifecycleError.localCleanupFailed
    }
  }

  func withdraw() async throws {
    if let withdrawalTask {
      try await withdrawalTask.value
      return
    }

    guard accountSessionStore.beginAccountLifecycleOperation(.withdrawal) else {
      throw AccountLifecycleError.sessionUnavailable
    }

    let task = Task { @MainActor in
      try await self.performWithdrawal()
    }
    withdrawalTask = task
    defer {
      withdrawalTask = nil
      accountSessionStore.endAccountLifecycleOperation(.withdrawal)
    }
    try await task.value
  }

  func reauthenticateAppleWithdrawal(
    with authorization: SocialAuthorization
  ) async throws {
    guard accountSessionStore.beginAccountLifecycleOperation(.withdrawal) else {
      throw AccountLifecycleError.sessionUnavailable
    }
    defer { accountSessionStore.endAccountLifecycleOperation(.withdrawal) }

    let pendingCredentials: AccountLifecycleCredentials
    do {
      pendingCredentials = try accountSessionStore.credentialsForAccountLifecycle()
    } catch {
      throw AccountLifecycleError.sessionUnavailable
    }

    guard pendingCredentials.provider == .apple,
          authorization.provider == .apple,
          Self.hasValue(authorization.token),
          Self.hasValue(authorization.authorizationCode),
          Self.hasValue(authorization.providerUserIdentifier) else {
      throw AccountLifecycleError.sessionUnavailable
    }

    let response = try await authRemoteDataSource.login(
      provider: .apple,
      request: SocialLoginRequestDTO(
        token: authorization.token,
        authorizationCode: authorization.authorizationCode
      )
    )
    guard response.memberId == pendingCredentials.memberID,
          response.isNewMember != true else {
      throw AccountLifecycleError.sessionUnavailable
    }

    try accountSessionStore
      .replacePendingWithdrawalCredentialsAfterAppleReauthentication(
        AccountCredentials(
          memberID: response.memberId,
          accessToken: response.accessToken,
          refreshToken: response.refreshToken,
          onboardingCompleted: response.onboardingCompleted,
          provider: .apple,
          providerUserIdentifier: authorization.providerUserIdentifier
        )
      )
  }

  private func performWithdrawal() async throws {
    let credentials: AccountLifecycleCredentials

    do {
      credentials = try accountSessionStore.credentialsForAccountLifecycle()
    } catch {
      throw AccountLifecycleError.sessionUnavailable
    }

    guard accountSessionStore.beginWithdrawalOperation(
      memberID: credentials.memberID
    ) else {
      throw AccountLifecycleError.sessionUnavailable
    }

    let recovery: PendingAccountCleanupRecovery
    do {
      recovery = try await accountScopedDataCleaner
        .recoverPendingAccountCleanups()
    } catch {
      accountSessionStore.suspendPendingWithdrawalAuthorization(
        memberID: credentials.memberID
      )
      throw AccountLifecycleError.withdrawalStateUnavailable
    }

    if recovery.completedMemberIDs.contains(credentials.memberID) {
      // The server response was durably confirmed before a prior local
      // cleanup failure or process exit. Resume local/session cleanup without
      // issuing another DELETE.
      try await settleConfirmedWithdrawal(credentials: credentials)
      return
    }

    do {
      try await accountScopedDataCleaner.preparePendingAccountCleanup(
        memberID: credentials.memberID
      )
      // This save is the boundary: after it succeeds, a process crash or
      // transport error is deliberately treated as an ambiguous withdrawal.
      try await accountScopedDataCleaner.beginPendingAccountCleanupAttempt(
        memberID: credentials.memberID
      )
    } catch {
      accountSessionStore.suspendPendingWithdrawalAuthorization(
        memberID: credentials.memberID
      )
      throw AccountLifecycleError.withdrawalStateUnavailable
    }

    do {
      _ = try await authRemoteDataSource.withdraw(
        accessToken: credentials.accessToken
      )
    } catch {
      if requiresAppleReauthentication(error, credentials: credentials) {
        accountSessionStore.suspendPendingWithdrawalAuthorization(
          memberID: credentials.memberID
        )
        throw AccountLifecycleError.appleReauthenticationRequired
      }
      if isDefinitivePreCommitFailure(error) {
        do {
          try await accountScopedDataCleaner.cancelPendingAccountCleanup(
            memberID: credentials.memberID
          )
          accountSessionStore.resumeAfterDefinitiveWithdrawalFailure(
            memberID: credentials.memberID
          )
        } catch {
          accountSessionStore.suspendPendingWithdrawalAuthorization(
            memberID: credentials.memberID
          )
          throw AccountLifecycleError.withdrawalStateUnavailable
        }
      } else {
        accountSessionStore.suspendPendingWithdrawalAuthorization(
          memberID: credentials.memberID
        )
      }
      throw error
    }

    do {
      try await accountScopedDataCleaner.confirmPendingAccountCleanup(
        memberID: credentials.memberID
      )
      try await accountScopedDataCleaner.completePendingAccountCleanup(
        memberID: credentials.memberID
      )
    } catch {
      // Remote deletion may have succeeded. Keep the marker and this exact
      // session intact so startup can retry only the local, confirmed cleanup.
      accountSessionStore.suspendPendingWithdrawalAuthorization(
        memberID: credentials.memberID
      )
      throw AccountLifecycleError.localCleanupFailed
    }

    try await settleConfirmedWithdrawal(credentials: credentials)
  }

  private func settleConfirmedWithdrawal(
    credentials: AccountLifecycleCredentials
  ) async throws {
    var cleanupFailed = false

    if accountSessionStore.isCurrentSession(matching: credentials.memberID) {
      do {
        try await providerSessionSignOut.signOut(
          provider: credentials.provider,
          reason: .withdrawal
        )
      } catch {
        cleanupFailed = true
      }
    }

    var sessionCleanupSettled = false
    do {
      // The lifecycle gate blocks normal account replacement. Keep the
      // member-scoped removal as defense in depth for any out-of-band state
      // change while a provider callback is suspended.
      _ = try accountSessionStore.removeLocalAccountSessionIfMatching(
        memberID: credentials.memberID
      )
      sessionCleanupSettled = true
    } catch {
      cleanupFailed = true
    }

    if sessionCleanupSettled {
      do {
        try await accountScopedDataCleaner.finalizePendingAccountCleanup(
          memberID: credentials.memberID
        )
      } catch {
        cleanupFailed = true
      }
    }

    if cleanupFailed {
      throw AccountLifecycleError.localCleanupFailed
    }
  }

  private func isDefinitivePreCommitFailure(_ error: Error) -> Bool {
    // The backend documents MEMBER4091 as a retryable lock conflict. Any
    // server response that is not a locally detected pre-transport failure
    // remains durable recovery evidence rather than being inferred as a
    // completed or failed deletion.
    guard let apiError = error as? APIError else {
      return false
    }
    return switch apiError {
    case .invalidRequest, .authenticationRequired, .capabilityDisabled:
      true
    case .transport, .server, .decoding, .missingResult, .cancelled:
      false
    }
  }

  private func requiresAppleReauthentication(
    _ error: Error,
    credentials: AccountLifecycleCredentials
  ) -> Bool {
    guard credentials.provider == .apple,
          let apiError = error as? APIError,
          case .server(let statusCode, let code, _) = apiError else {
      return false
    }
    return statusCode == 409 && code == "AUTH4091"
  }

  private static func hasValue(_ value: String?) -> Bool {
    guard let value else {
      return false
    }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

@MainActor
final class UnavailableAccountLifecycleService: AccountLifecycleManaging {
  func logout() async throws {
    throw AccountLifecycleError.sessionUnavailable
  }

  func withdraw() async throws {
    throw AccountLifecycleError.sessionUnavailable
  }

  func reauthenticateAppleWithdrawal(
    with _: SocialAuthorization
  ) async throws {
    throw AccountLifecycleError.sessionUnavailable
  }
}
