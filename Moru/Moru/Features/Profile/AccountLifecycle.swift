//
//  AccountLifecycle.swift
//  Moru
//

import Foundation

nonisolated protocol AccountScopedDataCleaning: Sendable {
  func removeAccountScopedData(memberID: Int64) async throws
}

/// Used by previews and tests that intentionally do not construct account-scoped storage.
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
  private let serverSynchronizer: (any ServerSynchronizing)?

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning,
    providerSessionSignOut: any SocialProviderSessionSigningOut =
      NoopSocialProviderSessionSignOut(),
    serverSynchronizer: (any ServerSynchronizing)? = nil
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
    self.accountScopedDataCleaner = accountScopedDataCleaner
    self.providerSessionSignOut = providerSessionSignOut
    self.serverSynchronizer = serverSynchronizer
  }

  func logout() async throws {
    let credentials = try? accountSessionStore.credentialsForAccountLifecycle()
    let memberID = credentials?.memberID
      ?? accountSessionStore.signedInMemberID
    let provider = credentials?.provider ?? accountSessionStore.signedInProvider

    if let memberID {
      await serverSynchronizer?.suspendSynchronization(memberID: memberID)
    }
    if let refreshToken = credentials?.refreshToken {
      try? await authRemoteDataSource.logout(refreshToken: refreshToken)
    }
    if let provider {
      try? await providerSessionSignOut.signOut(
        provider: provider,
        reason: .logout
      )
    }
    if let memberID {
      await serverSynchronizer?.suspendSynchronization(memberID: memberID)
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

    await serverSynchronizer?.suspendSynchronization(
      memberID: credentials.memberID
    )
    do {
      _ = try await authRemoteDataSource.withdraw()
    } catch {
      serverSynchronizer?.resumeSynchronization(
        memberID: credentials.memberID
      )
      throw error
    }
    var cleanupFailed = false

    do {
      try await providerSessionSignOut.signOut(
        provider: credentials.provider,
        reason: .withdrawal
      )
    } catch {
      cleanupFailed = true
    }

    await serverSynchronizer?.suspendSynchronization(
      memberID: credentials.memberID
    )
    do {
      try await accountScopedDataCleaner.removeAccountScopedData(
        memberID: credentials.memberID
      )
    } catch {
      cleanupFailed = true
    }

    do {
      try accountSessionStore.removeLocalAccountSession()
    } catch {
      cleanupFailed = true
    }

    if cleanupFailed {
      throw AccountLifecycleError.localCleanupFailed
    }
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
