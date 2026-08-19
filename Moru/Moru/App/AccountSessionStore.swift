//
//  AccountSessionStore.swift
//  Moru
//

import Combine
import Foundation

nonisolated struct SignedInAccount: Equatable, Sendable {
  let memberID: Int64
  let onboardingCompleted: Bool
  let provider: AuthProvider
  let providerUserIdentifier: String?

  init(
    memberID: Int64,
    onboardingCompleted: Bool,
    provider: AuthProvider = .apple,
    providerUserIdentifier: String? = nil
  ) {
    self.memberID = memberID
    self.onboardingCompleted = onboardingCompleted
    self.provider = provider
    self.providerUserIdentifier = providerUserIdentifier
  }
}

nonisolated struct AccountLifecycleCredentials: Equatable, Sendable {
  let memberID: Int64
  let accessToken: String
  let refreshToken: String
  let provider: AuthProvider
}

nonisolated struct AccountTokenRefreshContext: Equatable, Sendable {
  let credentials: AccountCredentials
  let authorizationContext: AccountAuthorizationContext
}

nonisolated extension AccountLifecycleCredentials:
  CustomDebugStringConvertible,
  CustomStringConvertible {
  var description: String {
    """
    AccountLifecycleCredentials(\
    memberID: \(memberID), \
    accessToken: <redacted>, \
    refreshToken: <redacted>, \
    provider: \(provider.serverValue)\
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
  /// A prior DELETE may or may not have reached the server. Credentials stay
  /// available only for withdrawal retry/reconciliation; account sync and
  /// other signed-in features must treat this as signed out.
  case withdrawalPending(SignedInAccount)
  case failure(AccountSessionFailure)
}

nonisolated enum AccountLifecycleOperation: Equatable, Sendable {
  case logout
  case withdrawal
}

@MainActor
final class AccountSessionStore: ObservableObject {
  @Published private(set) var state: AccountSessionState = .signedOut

  let accessTokenProvider: MemoryAccessTokenProvider

  private let credentialStore: any CredentialStore
  private let restorationGuard: any AccountSessionRestorationGuarding
  private var activeAccountLifecycleOperation: AccountLifecycleOperation?

  var signedInProvider: AuthProvider? {
    lifecycleAccount?.provider
  }

  var isWithdrawalPending: Bool {
    if case .withdrawalPending = state {
      return true
    }
    return false
  }

  private var lifecycleAccount: SignedInAccount? {
    switch state {
    case .signedIn(let account), .withdrawalPending(let account):
      account
    case .signedOut, .restoring, .failure:
      nil
    }
  }

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

  func prepareForRestoration() {
    guard state == .signedOut else {
      return
    }

    state = .restoring
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

      accessTokenProvider.establishAccountSession(
        with: credentials.accessToken,
        memberID: credentials.memberID
      )
      state = .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted,
          provider: credentials.provider,
          providerUserIdentifier: credentials.providerUserIdentifier
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
    guard activeAccountLifecycleOperation == nil else {
      // A social-login response can arrive while logout or withdrawal is
      // suspended in provider/network work. It must not replace the exact
      // credential captured by that lifecycle operation.
      throw CredentialStoreError.invalidCredentials
    }

    if case .withdrawalPending = state {
      // Replacing the only credential that can reconcile an ambiguous DELETE
      // would strand the pending account and may revive it later.
      throw CredentialStoreError.invalidCredentials
    }

    try establishValidatedSession(credentials: credentials)
  }

  /// Applies only a server-confirmed onboarding completion to the exact
  /// account/session that issued the Outbox request. The bearer token and its
  /// generation stay unchanged, so an in-flight response for an old session
  /// can never update a replacement credential.
  @discardableResult
  func markOnboardingCompleted(
    for identity: AccountSessionIdentity
  ) throws -> Bool {
    guard case .signedIn(let account) = state,
          account.memberID == identity.memberID,
          currentAccountSessionIdentity == identity,
          let credentials = try credentialStore.load(),
          credentials.isValid,
          credentials.memberID == identity.memberID,
          credentials.provider == account.provider else {
      return false
    }

    guard !credentials.onboardingCompleted || !account.onboardingCompleted else {
      return true
    }
    let updatedCredentials = AccountCredentials(
      memberID: credentials.memberID,
      accessToken: credentials.accessToken,
      refreshToken: credentials.refreshToken,
      onboardingCompleted: true,
      provider: credentials.provider,
      providerUserIdentifier: credentials.providerUserIdentifier
    )
    try credentialStore.save(updatedCredentials)
    state = .signedIn(
      SignedInAccount(
        memberID: account.memberID,
        onboardingCompleted: true,
        provider: account.provider,
        providerUserIdentifier: account.providerUserIdentifier
      )
    )
    return true
  }

  @discardableResult
  func beginAccountLifecycleOperation(
    _ operation: AccountLifecycleOperation
  ) -> Bool {
    guard activeAccountLifecycleOperation == nil else {
      return false
    }

    activeAccountLifecycleOperation = operation
    return true
  }

  func endAccountLifecycleOperation(
    _ operation: AccountLifecycleOperation
  ) {
    guard activeAccountLifecycleOperation == operation else {
      return
    }
    activeAccountLifecycleOperation = nil
  }

  private func establishValidatedSession(
    credentials: AccountCredentials
  ) throws {
    guard credentials.isValid else {
      throw CredentialStoreError.invalidCredentials
    }

    try credentialStore.save(credentials)
    restorationGuard.allowRestoration()
    accessTokenProvider.establishAccountSession(
      with: credentials.accessToken,
      memberID: credentials.memberID
    )
    state = .signedIn(
      SignedInAccount(
        memberID: credentials.memberID,
        onboardingCompleted: credentials.onboardingCompleted,
        provider: credentials.provider,
        providerUserIdentifier: credentials.providerUserIdentifier
      )
    )
  }

  func currentAuthorizationContext() -> AccountAuthorizationContext? {
    guard case .signedIn(let account) = state,
          let authorizationContext = accessTokenProvider
            .authorizationContext(forMemberID: account.memberID) else {
      return nil
    }

    return authorizationContext
  }

  func credentialsForTokenRefresh(
    matching authorizationContext: AccountAuthorizationContext
  ) throws -> AccountTokenRefreshContext {
    guard case .signedIn(let account) = state,
          account.memberID == authorizationContext.memberID,
          accessTokenProvider.authorizationContext(
            forMemberID: account.memberID
          ) == authorizationContext,
          let credentials = try credentialStore.load(),
          credentials.isValid,
          credentials.memberID == account.memberID,
          credentials.accessToken
            == authorizationContext.accessToken else {
      throw CredentialStoreError.invalidCredentials
    }

    return AccountTokenRefreshContext(
      credentials: credentials,
      authorizationContext: authorizationContext
    )
  }

  func replaceCredentialsAfterTokenRefresh(
    _ credentials: AccountCredentials,
    replacing refreshContext: AccountTokenRefreshContext
  ) throws {
    guard credentials.isValid,
          case .signedIn(let account) = state,
          account.memberID == credentials.memberID,
          refreshContext.credentials.memberID == account.memberID,
          refreshContext.authorizationContext.memberID == account.memberID,
          refreshContext.authorizationContext.accessToken
            == refreshContext.credentials.accessToken,
          accessTokenProvider.authorizationContext(
            forMemberID: account.memberID
          ) == refreshContext.authorizationContext else {
      throw CredentialStoreError.invalidCredentials
    }

    try credentialStore.save(credentials)
    guard accessTokenProvider.replaceAccountSessionToken(
      with: credentials.accessToken,
      replacing: refreshContext.authorizationContext
    ) else {
      throw CredentialStoreError.invalidCredentials
    }
    let updatedAccount = SignedInAccount(
      memberID: credentials.memberID,
      onboardingCompleted: credentials.onboardingCompleted,
      provider: credentials.provider,
      providerUserIdentifier: credentials.providerUserIdentifier
    )
    state = .signedIn(updatedAccount)
  }

  func credentialsForAccountLifecycle() throws -> AccountLifecycleCredentials {
    guard let account = lifecycleAccount,
          let credentials = try credentialStore.load(),
          credentials.isValid,
          credentials.memberID == account.memberID,
          credentials.provider == account.provider else {
      throw CredentialStoreError.invalidCredentials
    }

    switch state {
    case .signedIn:
      guard credentials.accessToken == accessTokenProvider.accessToken else {
        throw CredentialStoreError.invalidCredentials
      }
    case .withdrawalPending:
      break
    case .signedOut, .restoring, .failure:
      throw CredentialStoreError.invalidCredentials
    }

    return AccountLifecycleCredentials(
      memberID: credentials.memberID,
      accessToken: credentials.accessToken,
      refreshToken: credentials.refreshToken,
      provider: credentials.provider
    )
  }

  /// Used only after a persisted, server-confirmed withdrawal cleanup. A
  /// marker for account A must never remove newer account B's credentials.
  @discardableResult
  func removeStoredSessionIfMatching(memberID: Int64) throws -> Bool {
    try removeLocalAccountSessionIfMatching(memberID: memberID)
  }

  /// Removes only the exact member captured before an async account-lifecycle
  /// operation. If another account became active or replaced Keychain while
  /// awaiting a provider callback, it deliberately does nothing.
  @discardableResult
  func removeLocalAccountSessionIfMatching(memberID: Int64) throws -> Bool {
    let activeMemberID = lifecycleAccount?.memberID
    let storedCredentials = try credentialStore.load()
    let storedMemberID = storedCredentials?.memberID

    // Never touch an unrelated current session or its persisted credentials.
    guard storedMemberID == nil || storedMemberID == memberID,
          activeMemberID == nil || activeMemberID == memberID else {
      return false
    }
    guard storedMemberID == memberID || activeMemberID == memberID else {
      return false
    }

    if storedMemberID == memberID {
      restorationGuard.blockRestoration()
      do {
        try credentialStore.remove()
        restorationGuard.allowRestoration()
      } catch {
        if activeMemberID == memberID {
          accessTokenProvider.remove()
          state = .signedOut
        }
        throw error
      }
    }

    if activeMemberID == memberID {
      accessTokenProvider.remove()
      state = .signedOut
    }
    return true
  }

  func isCurrentSession(matching memberID: Int64) -> Bool {
    lifecycleAccount?.memberID == memberID
  }

  /// Reads only the member identity needed to decide whether an ambiguous
  /// withdrawal marker applies. It never returns credential/token material.
  func hasStoredSession(matching memberIDs: [Int64]) throws -> Bool {
    guard !memberIDs.isEmpty,
          let credentials = try credentialStore.load() else {
      return false
    }
    return memberIDs.contains(credentials.memberID)
  }

  /// Restores only the authorization needed to retry an ambiguous withdrawal.
  /// `signedInMemberID` and `currentAccountSessionIdentity` remain unavailable,
  /// so routine sync, server TTS, and account feature requests stay disabled.
  @discardableResult
  func preparePendingWithdrawalRetry(
    matching memberIDs: [Int64]
  ) throws -> Bool {
    guard !memberIDs.isEmpty,
          let credentials = try credentialStore.load(),
          credentials.isValid,
          memberIDs.contains(credentials.memberID) else {
      return false
    }

    // Do not restore a generally usable bearer token during bootstrap. The
    // withdrawal service establishes it only for an explicit retry.
    accessTokenProvider.remove()
    state = .withdrawalPending(
      SignedInAccount(
        memberID: credentials.memberID,
        onboardingCompleted: credentials.onboardingCompleted,
        provider: credentials.provider,
        providerUserIdentifier: credentials.providerUserIdentifier
      )
    )
    return true
  }

  @discardableResult
  func beginWithdrawalOperation(memberID: Int64) -> Bool {
    let account: SignedInAccount
    switch state {
    case .signedIn(let signedInAccount),
         .withdrawalPending(let signedInAccount):
      account = signedInAccount
    case .signedOut, .restoring, .failure:
      return false
    }
    guard account.memberID == memberID else {
      return false
    }

    // Invalidate ordinary and already-captured account-bound requests before
    // the first suspension point. The withdrawal request uses its own captured
    // credential instead of republishing this token.
    accessTokenProvider.remove()
    state = .withdrawalPending(account)
    return true
  }

  func suspendPendingWithdrawalAuthorization(memberID: Int64) {
    guard case .withdrawalPending(let account) = state,
          account.memberID == memberID else {
      return
    }
    accessTokenProvider.remove()
  }

  func resumeAfterDefinitiveWithdrawalFailure(memberID: Int64) {
    guard case .withdrawalPending(let account) = state,
          account.memberID == memberID else {
      return
    }
    guard let credentials = try? credentialStore.load(),
          credentials.isValid,
          credentials.memberID == memberID else {
      accessTokenProvider.remove()
      return
    }
    accessTokenProvider.establishAccountSession(
      with: credentials.accessToken,
      memberID: memberID
    )
    state = .signedIn(account)
  }

  /// Replaces only the credentials for the exact Apple account that is held
  /// in a withdrawal-pending state. The refreshed bearer remains unavailable
  /// to normal account features; it is used solely by the next explicit
  /// withdrawal retry.
  func replacePendingWithdrawalCredentialsAfterAppleReauthentication(
    _ credentials: AccountCredentials
  ) throws {
    guard credentials.isValid,
          case .withdrawalPending(let account) = state,
          account.provider == .apple,
          credentials.memberID == account.memberID,
          credentials.provider == .apple,
          account.providerUserIdentifier == nil
            || account.providerUserIdentifier == credentials.providerUserIdentifier else {
      throw CredentialStoreError.invalidCredentials
    }

    try credentialStore.save(credentials)
    restorationGuard.allowRestoration()
    accessTokenProvider.remove()
    state = .withdrawalPending(
      SignedInAccount(
        memberID: credentials.memberID,
        onboardingCompleted: credentials.onboardingCompleted,
        provider: .apple,
        providerUserIdentifier: credentials.providerUserIdentifier
      )
    )
  }

  /// Fail closed when cleanup recovery cannot be read. The credential remains
  /// in Keychain, but no bearer token is exposed to normal app requests.
  func deferRestorationWithoutDeletingCredentials() {
    accessTokenProvider.remove()
    guard let credentials = try? credentialStore.load(),
          credentials.isValid else {
      state = .signedOut
      return
    }
    state = .withdrawalPending(
      SignedInAccount(
        memberID: credentials.memberID,
        onboardingCompleted: credentials.onboardingCompleted,
        provider: credentials.provider,
        providerUserIdentifier: credentials.providerUserIdentifier
      )
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
    matching authorizationContext: AccountAuthorizationContext
  ) {
    guard accessTokenProvider.authorizationContext(
      forMemberID: authorizationContext.memberID
    ) == authorizationContext else {
      return
    }

    try? removeLocalAccountSession()
  }
}
