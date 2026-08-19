//
//  AccountSessionFoundationTests.swift
//  MoruTests
//

import Security
import SwiftData
import XCTest

@testable import Moru

@MainActor
final class AccountSessionFoundationTests: XCTestCase {
  func testKeychainQueriesDisableSynchronizationAndUseDeviceOnlyAccessibility() {
    let data = Data("credential-data".utf8)
    let itemQuery = KeychainCredentialStore.itemQuery(
      service: "test-service",
      account: "test-account"
    )
    let attributes = KeychainCredentialStore.addAttributes(
      service: "test-service",
      account: "test-account",
      data: data
    )

    XCTAssertEqual(
      itemQuery[kSecAttrSynchronizable] as? Bool,
      false
    )
    XCTAssertEqual(
      attributes[kSecAttrSynchronizable] as? Bool,
      false
    )
    XCTAssertEqual(
      attributes[kSecAttrAccessible] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
    XCTAssertEqual(attributes[kSecValueData] as? Data, data)
  }

  func testKeychainCredentialsSurviveStoreRecreation() throws {
    let service = "com.teammoru.MoruTests.\(UUID().uuidString)"
    let account = "relaunch"
    let firstStore = KeychainCredentialStore(
      service: service,
      account: account
    )
    let credentials = makeCredentials()
    try? firstStore.remove()
    defer { try? firstStore.remove() }

    try firstStore.save(credentials)

    let relaunchedStore = KeychainCredentialStore(
      service: service,
      account: account
    )
    XCTAssertEqual(try relaunchedStore.load(), credentials)

    let rotatedCredentials = AccountCredentials(
      memberID: credentials.memberID,
      accessToken: "rotated-access-token",
      refreshToken: "rotated-refresh-token",
      onboardingCompleted: false
    )
    try relaunchedStore.save(rotatedCredentials)
    XCTAssertEqual(try firstStore.load(), rotatedCredentials)
  }

  func testKeychainStoreRejectsBlankCredentialsBeforeWriting() throws {
    let service = "com.teammoru.MoruTests.\(UUID().uuidString)"
    let store = KeychainCredentialStore(
      service: service,
      account: "blank"
    )
    defer { try? store.remove() }

    XCTAssertThrowsError(
      try store.save(
        AccountCredentials(
          memberID: 7,
          accessToken: " ",
          refreshToken: "refresh-token",
          onboardingCompleted: false
        )
      )
    ) {
      XCTAssertEqual(
        $0 as? CredentialStoreError,
        .invalidCredentials
      )
    }
    XCTAssertNil(try store.load())
  }

  func testKeychainStoreReportsCorruptedAndEmptyPayloadsWithoutSecrets() throws {
    try assertInvalidStoredData(Data("not-json".utf8))
    try assertInvalidStoredData(Data())
  }

  func testMemoryAccessTokenProviderNormalizesAndRemovesSnapshot() throws {
    let provider = MemoryAccessTokenProvider()

    provider.replace(with: "  access-token  ")
    XCTAssertEqual(provider.accessToken, "access-token")
    XCTAssertNil(provider.authorizationContext(forMemberID: 7))

    provider.replace(with: "\n ")
    XCTAssertNil(provider.accessToken)

    provider.establishAccountSession(
      with: "account-token",
      memberID: 7
    )
    let firstContext = try XCTUnwrap(
      provider.authorizationContext(forMemberID: 7)
    )
    XCTAssertEqual(firstContext.accessToken, "account-token")
    XCTAssertNil(provider.authorizationContext(forMemberID: 8))

    XCTAssertTrue(
      provider.replaceAccountSessionToken(
        with: "rotated-token",
        replacing: firstContext
      )
    )
    let rotatedContext = provider.authorizationContext(forMemberID: 7)
    XCTAssertEqual(rotatedContext?.accessToken, "rotated-token")
    XCTAssertEqual(rotatedContext?.sessionID, firstContext.sessionID)

    provider.establishAccountSession(
      with: "new-session-token",
      memberID: 7
    )
    XCTAssertNotEqual(
      provider.authorizationContext(forMemberID: 7)?.sessionID,
      firstContext.sessionID
    )

    provider.remove()
    XCTAssertNil(provider.accessToken)
    XCTAssertNil(provider.authorizationContext(forMemberID: 7))
  }

  func testCredentialDescriptionRedactsTokens() {
    let credentials = makeCredentials()
    let description = String(describing: credentials)
    let debugDescription = String(reflecting: credentials)

    XCTAssertFalse(description.contains(credentials.accessToken))
    XCTAssertFalse(description.contains(credentials.refreshToken))
    XCTAssertFalse(debugDescription.contains(credentials.accessToken))
    XCTAssertFalse(debugDescription.contains(credentials.refreshToken))
    XCTAssertTrue(description.contains("<redacted>"))
  }

  func testAccountSessionRestoreTransitionsToSignedInAndUpdatesMemorySnapshot() {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(credentials))
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )

    sessionStore.restore()

    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    )
    XCTAssertEqual(sessionStore.signedInMemberID, credentials.memberID)
    XCTAssertEqual(tokenProvider.accessToken, credentials.accessToken)
    XCTAssertEqual(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )?.accessToken,
      credentials.accessToken
    )
    XCTAssertEqual(credentialStore.loadCount, 1)
  }

  func testMissingCredentialRestoresSignedOutAndClearsStaleSnapshot() {
    let credentialStore = StubCredentialStore(loadResult: .success(nil))
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.replace(with: "stale-access-token")
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )

    sessionStore.restore()

    XCTAssertEqual(sessionStore.state, .signedOut)
    XCTAssertNil(tokenProvider.accessToken)
  }

  func testCredentialCorruptionBecomesRedactedFailureAndClearsSnapshot() {
    let credentialStore = StubCredentialStore(
      loadResult: .failure(CredentialStoreError.invalidStoredData)
    )
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.replace(with: "stale-access-token")
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )

    sessionStore.restore()

    XCTAssertEqual(sessionStore.state, .failure(.invalidCredentials))
    XCTAssertNil(tokenProvider.accessToken)
    XCTAssertFalse(String(describing: sessionStore.state).contains("stale-access-token"))
  }

  func testCredentialAccessFailureDoesNotBecomeLocalBootstrapFailure() {
    let credentialStore = StubCredentialStore(
      loadResult: .failure(CredentialStoreError.keychain(status: -1))
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )

    sessionStore.restore()

    XCTAssertEqual(
      sessionStore.state,
      .failure(.credentialStoreUnavailable)
    )
    XCTAssertNil(tokenProvider.accessToken)
  }

  func testEstablishSessionPersistsBeforePublishingSignedInState() throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(nil))
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )

    try sessionStore.establishSession(credentials: credentials)

    XCTAssertEqual(credentialStore.savedCredentials, credentials)
    XCTAssertEqual(tokenProvider.accessToken, credentials.accessToken)
    XCTAssertEqual(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )?.accessToken,
      credentials.accessToken
    )
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    )
  }

  func testTokenRefreshKeepsSessionIdentityAndRejectsAnotherMember() throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(credentials))
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: credentials)
    let originalContext = try XCTUnwrap(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )
    )
    let refreshContext = AccountTokenRefreshContext(
      credentials: credentials,
      authorizationContext: originalContext
    )
    let rotatedCredentials = AccountCredentials(
      memberID: credentials.memberID,
      accessToken: "rotated-access-token",
      refreshToken: "rotated-refresh-token",
      onboardingCompleted: credentials.onboardingCompleted
    )

    try sessionStore.replaceCredentialsAfterTokenRefresh(
      rotatedCredentials,
      replacing: refreshContext
    )

    let rotatedContext = try XCTUnwrap(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )
    )
    XCTAssertEqual(rotatedContext.accessToken, "rotated-access-token")
    XCTAssertEqual(rotatedContext.sessionID, originalContext.sessionID)

    let anotherMember = AccountCredentials(
      memberID: credentials.memberID + 1,
      accessToken: "another-member-token",
      refreshToken: "another-member-refresh-token",
      onboardingCompleted: true
    )
    let rotatedRefreshContext = AccountTokenRefreshContext(
      credentials: rotatedCredentials,
      authorizationContext: rotatedContext
    )
    XCTAssertThrowsError(
      try sessionStore.replaceCredentialsAfterTokenRefresh(
        anotherMember,
        replacing: rotatedRefreshContext
      )
    ) {
      XCTAssertEqual($0 as? CredentialStoreError, .invalidCredentials)
    }
    XCTAssertEqual(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      ),
      rotatedContext
    )

    try sessionStore.removeLocalAccountSession()
    XCTAssertNil(sessionStore.signedInMemberID)
    XCTAssertNil(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )
    )
  }

  func testStaleRefreshCannotReplaceANewerSameMemberSession() throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(credentials))
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: credentials)
    let originalAuthorization = try XCTUnwrap(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )
    )
    let staleRefreshContext = AccountTokenRefreshContext(
      credentials: credentials,
      authorizationContext: originalAuthorization
    )
    let replacementSession = AccountCredentials(
      memberID: credentials.memberID,
      accessToken: credentials.accessToken,
      refreshToken: "replacement-session-refresh-token",
      onboardingCompleted: false
    )
    try sessionStore.establishSession(credentials: replacementSession)
    let replacementAuthorization = try XCTUnwrap(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )
    )
    XCTAssertNotEqual(
      replacementAuthorization.sessionID,
      originalAuthorization.sessionID
    )
    let staleRefreshedCredentials = AccountCredentials(
      memberID: credentials.memberID,
      accessToken: "stale-refreshed-access-token",
      refreshToken: "stale-refreshed-refresh-token",
      onboardingCompleted: true
    )

    XCTAssertThrowsError(
      try sessionStore.replaceCredentialsAfterTokenRefresh(
        staleRefreshedCredentials,
        replacing: staleRefreshContext
      )
    ) {
      XCTAssertEqual($0 as? CredentialStoreError, .invalidCredentials)
    }
    XCTAssertEqual(credentialStore.savedCredentials, replacementSession)
    XCTAssertEqual(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      ),
      replacementAuthorization
    )
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: replacementSession.memberID,
          onboardingCompleted: replacementSession.onboardingCompleted
        )
      )
    )
  }

  func testOnboardingCompletionUpdatesOnlyTheCapturedSessionHint() throws {
    let credentials = AccountCredentials(
      memberID: 7,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      onboardingCompleted: false,
      provider: .google
    )
    let credentialStore = MutableSessionCredentialStore(credentials: credentials)
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: credentials)
    let capturedIdentity = try XCTUnwrap(
      sessionStore.currentAccountSessionIdentity
    )
    let originalAuthorization = try XCTUnwrap(
      tokenProvider.authorizationContext(forMemberID: credentials.memberID)
    )

    XCTAssertTrue(try sessionStore.markOnboardingCompleted(for: capturedIdentity))
    XCTAssertEqual(credentialStore.credentials?.onboardingCompleted, true)
    XCTAssertEqual(sessionStore.currentAccountSessionIdentity, capturedIdentity)
    XCTAssertEqual(
      tokenProvider.authorizationContext(forMemberID: credentials.memberID),
      originalAuthorization
    )

    try sessionStore.establishSession(
      credentials: AccountCredentials(
        memberID: 7,
        accessToken: "replacement-access",
        refreshToken: "replacement-refresh",
        onboardingCompleted: false,
        provider: .google
      )
    )
    XCTAssertFalse(try sessionStore.markOnboardingCompleted(for: capturedIdentity))
    XCTAssertEqual(credentialStore.credentials?.onboardingCompleted, false)
  }

  func testMemberScopedLiveRemovalNeverDeletesReplacementAccountAndClearsCapturedInMemoryAccount() throws {
    let captured = makeCredentials()
    let replacement = AccountCredentials(
      memberID: captured.memberID + 1,
      accessToken: "replacement-access",
      refreshToken: "replacement-refresh",
      onboardingCompleted: false,
      provider: .google
    )
    let store = MutableSessionCredentialStore(credentials: captured)
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: store,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: captured)
    try sessionStore.establishSession(credentials: replacement)

    XCTAssertFalse(
      try sessionStore.removeLocalAccountSessionIfMatching(memberID: captured.memberID)
    )
    XCTAssertEqual(store.credentials, replacement)
    XCTAssertEqual(tokenProvider.accessToken, replacement.accessToken)
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: replacement.memberID,
          onboardingCompleted: replacement.onboardingCompleted,
          provider: replacement.provider
        )
      )
    )

    let capturedOnlyStore = MutableSessionCredentialStore(credentials: captured)
    let capturedOnlySession = AccountSessionStore(
      credentialStore: capturedOnlyStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    try capturedOnlySession.establishSession(credentials: captured)
    try capturedOnlyStore.remove()

    XCTAssertTrue(
      try capturedOnlySession.removeLocalAccountSessionIfMatching(
        memberID: captured.memberID
      )
    )
    XCTAssertEqual(capturedOnlySession.state, .signedOut)
    XCTAssertNil(capturedOnlySession.accessTokenProvider.accessToken)
  }

  func testCapabilitiesRequireEnabledSignedInAccount() {
    let signedIn = AccountSessionState.signedIn(
      SignedInAccount(memberID: 7, onboardingCompleted: true)
    )

    XCTAssertTrue(
      AppCapabilities.production.canUseAccountFeatures(
        sessionState: signedIn
      )
    )
    XCTAssertFalse(
      AppCapabilities.production.canUseAccountFeatures(
        sessionState: .restoring
      )
    )
    XCTAssertFalse(
      AppCapabilities.localOnly.canUseAccountFeatures(
        sessionState: signedIn
      )
    )
    XCTAssertTrue(AppCapabilities.production.shouldShowAccountUI)
    XCTAssertTrue(AppCapabilities.production.shouldAllowServerRequests)
    XCTAssertFalse(AppCapabilities.localOnly.shouldShowAccountUI)
    XCTAssertFalse(AppCapabilities.localOnly.shouldRestoreAccountSession)
    XCTAssertFalse(AppCapabilities.localOnly.shouldAllowServerRequests)
  }

  func testBootstrapPublishesRestoringStateBeforeOptionalAccountRestore() async throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(credentials))
    let tokenProvider = MemoryAccessTokenProvider()
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: {
        try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
      },
      accountSessionStoreFactory: {
        accountSessionStore
      },
      appCapabilities: .production,
      installationMarkerUserDefaults: makeInstallationUserDefaults(
        markerPresent: true
      )
    )

    bootstrapper.start()

    XCTAssertEqual(accountSessionStore.state, .restoring)
    XCTAssertEqual(credentialStore.loadCount, 0)

    try await waitUntil {
      if case .ready = bootstrapper.state {
        return true
      }
      return false
    }
    guard case .ready(let app) = bootstrapper.state else {
      return XCTFail("Local app graph should become ready after preflight.")
    }
    XCTAssertEqual(app.sessionStore.phase, .onboardingRequired)

    try await waitUntil {
      credentialStore.loadCount == 1
    }

    XCTAssertEqual(credentialStore.loadCount, 1)
    XCTAssertEqual(
      app.accountSessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    )
  }

  func testFreshReinstallDiscardsCredentialAndSkipsServerRestoration()
    async throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(
      loadResult: .success(credentials)
    )
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.replace(with: "stale-memory-token")
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    let installationDefaults = makeInstallationUserDefaults(
      markerPresent: false
    )
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: {
        try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
      },
      accountSessionStoreFactory: {
        accountSessionStore
      },
      appCapabilities: .production,
      installationMarkerUserDefaults: installationDefaults
    )

    bootstrapper.start()
    try await waitUntil {
      if case .ready = bootstrapper.state {
        return true
      }
      return false
    }
    guard case .ready(let app) = bootstrapper.state else {
      return XCTFail("Fresh installation should finish bootstrapping.")
    }

    XCTAssertEqual(credentialStore.removeCount, 1)
    XCTAssertEqual(credentialStore.loadCount, 0)
    XCTAssertEqual(accountSessionStore.state, .signedOut)
    XCTAssertNil(accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertTrue(
      installationDefaults.bool(
        forKey: AppBootstrapper.installationMarkerKey
      )
    )

    app.onboardingStatusRuntimeCoordinator?.start()
    app.onboardingStatusRuntimeCoordinator?.accountSessionDidChange()
    await Task.yield()
    XCTAssertEqual(
      app.onboardingStatusRuntimeCoordinator?.restorationState,
      .idle
    )
    XCTAssertNil(app.onboardingStatusRuntimeCoordinator?.latestResolution)
  }

  func testMissingInstallationMarkerWithLocalDataPreservesAccountRestore()
    async throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(
      loadResult: .success(credentials)
    )
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    try SwiftDataLocalProfileRepository(
      modelContext: container.mainContext
    ).saveProfile(LocalProfile(displayName: "기존 사용자"))
    let installationDefaults = makeInstallationUserDefaults(
      markerPresent: false
    )
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: { container },
      accountSessionStoreFactory: { accountSessionStore },
      appCapabilities: .production,
      installationMarkerUserDefaults: installationDefaults
    )

    bootstrapper.start()
    try await waitUntil {
      accountSessionStore.state == .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    }

    XCTAssertEqual(credentialStore.removeCount, 0)
    XCTAssertEqual(credentialStore.loadCount, 1)
    XCTAssertEqual(
      accountSessionStore.accessTokenProvider.accessToken,
      credentials.accessToken
    )
    XCTAssertTrue(
      installationDefaults.bool(
        forKey: AppBootstrapper.installationMarkerKey
      )
    )
  }

  func testDisabledAccountCapabilitySkipsCredentialRestore() async throws {
    let credentialStore = StubCredentialStore(
      loadResult: .success(makeCredentials())
    )
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: {
        try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
      },
      accountSessionStoreFactory: {
        accountSessionStore
      },
      appCapabilities: .localOnly
    )

    bootstrapper.start()
    try await waitUntil {
      if case .ready = bootstrapper.state {
        return true
      }
      return false
    }

    XCTAssertEqual(credentialStore.loadCount, 0)
    XCTAssertEqual(accountSessionStore.state, .signedOut)
  }

  func testBootstrapAwaitsPreflightBeforePublishingReady() async throws {
    let preflight = BlockingBootstrapPreflight()
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: {
        try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
      },
      appCapabilities: .localOnly,
      preflight: preflight
    )

    bootstrapper.start()

    let didStartPreflight = await preflight.waitUntilStarted()
    XCTAssertTrue(didStartPreflight)
    guard case .loading = bootstrapper.state else {
      return XCTFail("Bootstrap must stay loading while preflight is running.")
    }

    preflight.finish()
    try await waitUntil {
      if case .ready = bootstrapper.state {
        return true
      }
      return false
    }
    XCTAssertEqual(preflight.events, ["started", "finished"])
  }

  func testAmbiguousCleanupForStoredAccountPublishesRestrictedWithdrawalRecovery()
    async throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(credentials))
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let syncRepository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    try syncRepository.preparePendingAccountCleanup(
      memberID: credentials.memberID,
      at: Date()
    )
    try syncRepository.beginPendingAccountCleanupAttempt(
      memberID: credentials.memberID
    )
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: { container },
      accountSessionStoreFactory: { accountSessionStore },
      appCapabilities: .production,
      installationMarkerUserDefaults: makeInstallationUserDefaults(
        markerPresent: true
      )
    )

    bootstrapper.start()
    XCTAssertEqual(accountSessionStore.state, .restoring)

    try await waitUntil {
      if case .ready = bootstrapper.state {
        return accountSessionStore.state == .withdrawalPending(
          SignedInAccount(
            memberID: credentials.memberID,
            onboardingCompleted: credentials.onboardingCompleted,
            provider: credentials.provider,
            providerUserIdentifier: credentials.providerUserIdentifier
          )
        )
      }
      return false
    }

    XCTAssertEqual(credentialStore.removeCount, 0)
    XCTAssertEqual(credentialStore.loadCount, 1)
    XCTAssertNil(accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertNil(accountSessionStore.signedInMemberID)
    XCTAssertNil(accountSessionStore.currentAccountSessionIdentity)
    XCTAssertFalse(
      AppCapabilities.production.canUseAccountFeatures(
        sessionState: accountSessionStore.state
      )
    )
  }

  func testAmbiguousCleanupForAnotherMemberDoesNotBlockStoredAccountRestoration()
    async throws {
    let credentials = makeCredentials()
    let credentialStore = StubCredentialStore(loadResult: .success(credentials))
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let syncRepository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    try syncRepository.preparePendingAccountCleanup(
      memberID: credentials.memberID + 1,
      at: Date()
    )
    try syncRepository.beginPendingAccountCleanupAttempt(
      memberID: credentials.memberID + 1
    )
    let bootstrapper = AppBootstrapper(
      modelContainerFactory: { container },
      accountSessionStoreFactory: { accountSessionStore },
      appCapabilities: .production,
      installationMarkerUserDefaults: makeInstallationUserDefaults(
        markerPresent: true
      )
    )

    bootstrapper.start()

    try await waitUntil {
      accountSessionStore.state == .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    }

    XCTAssertEqual(credentialStore.removeCount, 0)
    XCTAssertEqual(accountSessionStore.signedInMemberID, credentials.memberID)
    XCTAssertEqual(
      accountSessionStore.accessTokenProvider.accessToken,
      credentials.accessToken
    )
  }

  func testCleanupRecoveryReadFailureKeepsCredentialRestrictedAndBlocksOverwrite()
    throws {
    let credentials = makeCredentials()
    let credentialStore = MutableSessionCredentialStore(
      credentials: credentials
    )
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    accountSessionStore.restore()

    accountSessionStore.deferRestorationWithoutDeletingCredentials()

    XCTAssertEqual(
      accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted,
          provider: credentials.provider,
          providerUserIdentifier: credentials.providerUserIdentifier
        )
      )
    )
    XCTAssertNil(accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertEqual(credentialStore.credentials, credentials)
    XCTAssertThrowsError(
      try accountSessionStore.establishSession(
        credentials: AccountCredentials(
          memberID: credentials.memberID + 1,
          accessToken: "replacement-access",
          refreshToken: "replacement-refresh",
          onboardingCompleted: true
        )
      )
    )
    XCTAssertEqual(credentialStore.credentials, credentials)
  }

  private func makeCredentials() -> AccountCredentials {
    AccountCredentials(
      memberID: 7,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      onboardingCompleted: true
    )
  }

  private func makeInstallationUserDefaults(
    markerPresent: Bool
  ) -> UserDefaults {
    let suiteName = "com.teammoru.MoruTests.installation.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    if markerPresent {
      userDefaults.set(
        true,
        forKey: AppBootstrapper.installationMarkerKey
      )
    }
    return userDefaults
  }

  private func assertInvalidStoredData(_ data: Data) throws {
    let service = "com.teammoru.MoruTests.\(UUID().uuidString)"
    let account = "corrupted"
    let store = KeychainCredentialStore(
      service: service,
      account: account
    )
    try? store.remove()
    defer { try? store.remove() }

    let status = SecItemAdd(
      KeychainCredentialStore.addAttributes(
        service: service,
        account: account,
        data: data
      ) as CFDictionary,
      nil
    )
    XCTAssertEqual(status, errSecSuccess)

    XCTAssertThrowsError(try store.load()) {
      XCTAssertEqual(
        $0 as? CredentialStoreError,
        .invalidStoredData
      )
      XCTAssertFalse(String(describing: $0).contains("not-json"))
    }
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
      guard clock.now < deadline else {
        return XCTFail("Timed out waiting for account session restoration.")
      }

      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

nonisolated private final class StubCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private let loadResult: Result<AccountCredentials?, Error>
  private var storedLoadCount = 0
  private var storedRemoveCount = 0
  private var storedSavedCredentials: AccountCredentials?

  init(loadResult: Result<AccountCredentials?, Error>) {
    self.loadResult = loadResult
  }

  var loadCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedLoadCount
  }

  var savedCredentials: AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedSavedCredentials
  }

  var removeCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedRemoveCount
  }

  func load() throws -> AccountCredentials? {
    lock.lock()
    storedLoadCount += 1
    lock.unlock()
    return try loadResult.get()
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.lock()
    storedSavedCredentials = credentials
    lock.unlock()
  }

  func remove() throws {
    lock.lock()
    storedRemoveCount += 1
    lock.unlock()
  }
}

nonisolated private final class MutableSessionCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCredentials: AccountCredentials?

  init(credentials: AccountCredentials?) {
    storedCredentials = credentials
  }

  var credentials: AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
  }

  func load() throws -> AccountCredentials? {
    credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.lock()
    storedCredentials = credentials
    lock.unlock()
  }

  func remove() throws {
    lock.lock()
    storedCredentials = nil
    lock.unlock()
  }
}

@MainActor
private final class BlockingBootstrapPreflight: AppBootstrapPreflightPreparing {
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var events: [String] = []

  func prepare(dependencies: DependencyContainer) async {
    events.append("started")
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    events.append("finished")
  }

  func waitUntilStarted() async -> Bool {
    for _ in 0..<100 where continuation == nil {
      await Task.yield()
    }
    return continuation != nil
  }

  func finish() {
    continuation?.resume()
    continuation = nil
  }
}
