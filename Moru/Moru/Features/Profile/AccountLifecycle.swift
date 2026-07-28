//
//  AccountLifecycle.swift
//  Moru
//

import Foundation

nonisolated protocol AccountScopedDataCleaning: Sendable {
  func removeAccountScopedData(memberID: Int64) async throws
}

/// P5 has no account-scoped SwiftData models. P6 replaces this boundary with its
/// Outbox and server preference cleanup implementation.
nonisolated struct NoAccountScopedDataCleaner: AccountScopedDataCleaning {
  func removeAccountScopedData(memberID: Int64) async throws {}
}

nonisolated enum AccountLifecycleError: Error, Equatable, Sendable {
  case sessionUnavailable
  case localCleanupFailed
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

  init(
    authRemoteDataSource: any AuthRemoteDataSource,
    accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning
  ) {
    self.authRemoteDataSource = authRemoteDataSource
    self.accountSessionStore = accountSessionStore
    self.accountScopedDataCleaner = accountScopedDataCleaner
  }

  func logout() async throws {
    let credentials = try? accountSessionStore.credentialsForAccountLifecycle()

    if let refreshToken = credentials?.refreshToken {
      try? await authRemoteDataSource.logout(refreshToken: refreshToken)
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

    _ = try await authRemoteDataSource.withdraw()

    var cleanupFailed = false

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
