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

  init(
    credentialStore: any CredentialStore,
    accessTokenProvider: MemoryAccessTokenProvider
  ) {
    self.credentialStore = credentialStore
    self.accessTokenProvider = accessTokenProvider
  }

  func restore() {
    state = .restoring

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

  func invalidateAfterTokenRefreshFailure(
    matching accessToken: String
  ) {
    guard accessTokenProvider.accessToken == accessToken else {
      return
    }

    try? credentialStore.remove()
    accessTokenProvider.remove()
    state = .signedOut
  }
}
