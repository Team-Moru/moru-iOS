//
//  AccountSessionStore.swift
//  Moru
//

import Combine
import Foundation

nonisolated struct SignedInAccount: Equatable, Sendable {
  let memberID: Int64
  let onboardingCompleted: Bool
}

nonisolated struct AccountLifecycleCredentials: Equatable, Sendable {
  let memberID: Int64
  let refreshToken: String
}

nonisolated extension AccountLifecycleCredentials:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    """
    AccountLifecycleCredentials(\
    memberID: \(memberID), \
    refreshToken: <redacted>\
    )
    """
  }

  var debugDescription: String {
    description
  }
}

nonisolated enum AccountSessionFailure: Equatable, Sendable {
  case invalidCredentials
  case credentialStoreUnavailable
}

nonisolated enum AccountSessionState: Equatable, Sendable {
  case signedOut
  case restoring
  case signedIn(SignedInAccount)
  case failure(AccountSessionFailure)
}

@MainActor
final class AccountSessionStore: ObservableObject {
  @Published private(set) var state: AccountSessionState = .signedOut

  let accessTokenProvider: MemoryAccessTokenProvider

  private let credentialStore: any CredentialStore
  private let restorationGuard: any AccountSessionRestorationGuarding

  init(
    credentialStore: any CredentialStore,
    accessTokenProvider: MemoryAccessTokenProvider,
    restorationGuard: any AccountSessionRestorationGuarding =
      InMemoryAccountSessionRestorationGuard()
  ) {
    self.credentialStore = credentialStore
    self.accessTokenProvider = accessTokenProvider
    self.restorationGuard = restorationGuard
  }

  func restore() {
    state = .restoring

    guard !restorationGuard.isRestorationBlocked else {
      do {
        try credentialStore.remove()
        restorationGuard.allowRestoration()
      } catch {
        // Keep the non-sensitive guard set so stale credentials cannot revive.
      }

      accessTokenProvider.remove()
      state = .signedOut
      return
    }

    do {
      guard let credentials = try credentialStore.load() else {
        accessTokenProvider.remove()
        state = .signedOut
        return
      }

      guard credentials.isValid else {
        accessTokenProvider.remove()
        state = .failure(.invalidCredentials)
        return
      }

      accessTokenProvider.replace(with: credentials.accessToken)
      state = .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    } catch CredentialStoreError.invalidCredentials,
            CredentialStoreError.invalidStoredData {
      accessTokenProvider.remove()
      state = .failure(.invalidCredentials)
    } catch {
      accessTokenProvider.remove()
      state = .failure(.credentialStoreUnavailable)
    }
  }

  func establishSession(
    credentials: AccountCredentials
  ) throws {
    guard credentials.isValid else {
      throw CredentialStoreError.invalidCredentials
    }

    try credentialStore.save(credentials)
    restorationGuard.allowRestoration()
    accessTokenProvider.replace(with: credentials.accessToken)
    state = .signedIn(
      SignedInAccount(
        memberID: credentials.memberID,
        onboardingCompleted: credentials.onboardingCompleted
      )
    )
  }

  func credentialsForTokenRefresh(
    matching accessToken: String
  ) throws -> AccountCredentials {
    guard case .signedIn = state,
          accessTokenProvider.accessToken == accessToken,
          let credentials = try credentialStore.load(),
          credentials.isValid,
          credentials.accessToken == accessToken else {
      throw CredentialStoreError.invalidCredentials
    }

    return credentials
  }

  func replaceCredentialsAfterTokenRefresh(
    _ credentials: AccountCredentials,
    replacing accessToken: String
  ) throws {
    guard credentials.isValid,
          case .signedIn = state,
          accessTokenProvider.accessToken == accessToken else {
      throw CredentialStoreError.invalidCredentials
    }

    try credentialStore.save(credentials)
    accessTokenProvider.replace(with: credentials.accessToken)
    state = .signedIn(
      SignedInAccount(
        memberID: credentials.memberID,
        onboardingCompleted: credentials.onboardingCompleted
      )
    )
  }

  func credentialsForAccountLifecycle() throws -> AccountLifecycleCredentials {
    guard case .signedIn(let account) = state,
          let accessToken = accessTokenProvider.accessToken,
          let credentials = try credentialStore.load(),
          credentials.isValid,
          credentials.memberID == account.memberID,
          credentials.accessToken == accessToken else {
      throw CredentialStoreError.invalidCredentials
    }

    return AccountLifecycleCredentials(
      memberID: credentials.memberID,
      refreshToken: credentials.refreshToken
    )
  }

  func removeLocalAccountSession() throws {
    restorationGuard.blockRestoration()
    let removalError: Error?

    do {
      try credentialStore.remove()
      restorationGuard.allowRestoration()
      removalError = nil
    } catch {
      removalError = error
    }

    accessTokenProvider.remove()
    state = .signedOut

    if let removalError {
      throw removalError
    }
  }

  func invalidateAfterTokenRefreshFailure(
    matching accessToken: String
  ) {
    guard accessTokenProvider.accessToken == accessToken else {
      return
    }

    try? removeLocalAccountSession()
  }
}
