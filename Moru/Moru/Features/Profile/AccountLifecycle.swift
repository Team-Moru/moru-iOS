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
}

@MainActor
final class DefaultAccountLifecycleService: AccountLifecycleManaging {
  private let authRemoteDataSource: any AuthRemoteDataSource
  private let accountSessionStore: AccountSessionStore
  private let accountScopedDataCleaner: any AccountScopedDataCleaning
  private let providerSessionSignOut: any SocialProviderSessionSigningOut

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning,
    providerSessionSignOut: any SocialProviderSessionSigningOut =
      NoopSocialProviderSessionSignOut()
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
    self.accountScopedDataCleaner = accountScopedDataCleaner
    self.providerSessionSignOut = providerSessionSignOut
  }

  func logout() async throws {
    let credentials = try? accountSessionStore.credentialsForAccountLifecycle()
    let provider = credentials?.provider ?? accountSessionStore.signedInProvider

    if let refreshToken = credentials?.refreshToken {
      try? await authRemoteDataSource.logout(refreshToken: refreshToken)
    }
    if let provider {
      try? await providerSessionSignOut.signOut(
        provider: provider,
        reason: .logout
      )
    }

    do {
      try accountSessionStore.removeLocalAccountSession()
    } catch {
      throw AccountLifecycleError.localCleanupFailed
    }
  }

  func withdraw() async throws {
    let credentials: AccountLifecycleCredentials

    do {
      credentials = try accountSessionStore.credentialsForAccountLifecycle()
    } catch {
      throw AccountLifecycleError.sessionUnavailable
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
      throw AccountLifecycleError.localCleanupFailed
    }

    do {
      _ = try await authRemoteDataSource.withdraw()
    } catch {
      if isDefinitivePreCommitFailure(error) {
        try? await accountScopedDataCleaner.cancelPendingAccountCleanup(
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
      throw AccountLifecycleError.localCleanupFailed
    }

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
      // A provider await may have allowed a new account B to replace A. A
      // false result is safe: B was intentionally left untouched, while A's
      // server-confirmed cleanup marker may still be finalized.
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
    guard case .server(let statusCode, _, _) = error as? APIError else {
      return false
    }
    return (400..<500).contains(statusCode)
      && statusCode != 408
      && statusCode != 429
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
}
