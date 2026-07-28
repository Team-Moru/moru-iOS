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

  func testMemoryAccessTokenProviderNormalizesAndRemovesSnapshot() {
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
    let firstContext = provider.authorizationContext(forMemberID: 7)
    XCTAssertEqual(firstContext?.accessToken, "account-token")
    XCTAssertNil(provider.authorizationContext(forMemberID: 8))

    XCTAssertTrue(
      provider.replaceAccountSessionToken(
        with: "rotated-token",
        memberID: 7
      )
    )
    let rotatedContext = provider.authorizationContext(forMemberID: 7)
    XCTAssertEqual(rotatedContext?.accessToken, "rotated-token")
    XCTAssertEqual(rotatedContext?.sessionID, firstContext?.sessionID)

    provider.establishAccountSession(
      with: "new-session-token",
      memberID: 7
    )
    XCTAssertNotEqual(
      provider.authorizationContext(forMemberID: 7)?.sessionID,
      firstContext?.sessionID
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
    var restoredMemberIDs: [Int64] = []
    sessionStore.setSessionRestoredHandler { memberID in
      restoredMemberIDs.append(memberID)
    }

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
    XCTAssertEqual(tokenProvider.accessToken, credentials.accessToken)
    XCTAssertEqual(
      tokenProvider.authorizationContext(
        forMemberID: credentials.memberID
      )?.accessToken,
      credentials.accessToken
    )
    XCTAssertEqual(restoredMemberIDs, [credentials.memberID])
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
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: credentials.memberID,
          onboardingCompleted: credentials.onboardingCompleted
        )
      )
    )
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
      appCapabilities: .production
    )

    bootstrapper.start()

    guard case .ready(let app) = bootstrapper.state else {
      return XCTFail("Local app graph should be ready before account restoration.")
    }
    XCTAssertEqual(app.sessionStore.phase, .onboardingRequired)
    XCTAssertEqual(app.accountSessionStore.state, .restoring)
    XCTAssertEqual(credentialStore.loadCount, 0)

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
    await Task.yield()

    XCTAssertEqual(credentialStore.loadCount, 0)
    XCTAssertEqual(accountSessionStore.state, .signedOut)
  }

  private func makeCredentials() -> AccountCredentials {
    AccountCredentials(
      memberID: 7,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      onboardingCompleted: true
    )
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

  func remove() throws {}
}
