//
//  AccountLifecycleTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class AccountLifecycleTests: XCTestCase {
  @MainActor
  func testLogoutAttemptsServerThenAlwaysClearsLocalSession() async throws {
    let fixture = makeFixture(
      logoutError: APIError.transport(code: -1009, message: "offline")
    )

    try await fixture.service.logout()

    XCTAssertEqual(
      fixture.events.values,
      ["remote logout", "credential remove"]
    )
    let logoutRefreshTokens = await fixture.remote.logoutRefreshTokens
    XCTAssertEqual(logoutRefreshTokens, ["refresh-token"])
    XCTAssertEqual(fixture.cleaner.memberIDs, [])
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertNil(fixture.tokenProvider.accessToken)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testLogoutClearsSessionEvenWhenStoredCredentialsCannotBeLoaded() async throws {
    let fixture = makeFixture()
    fixture.credentialStore.loadError = CredentialStoreError.invalidStoredData

    try await fixture.service.logout()

    XCTAssertEqual(fixture.events.values, ["credential remove"])
    let logoutRefreshTokens = await fixture.remote.logoutRefreshTokens
    XCTAssertEqual(logoutRefreshTokens, [])
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertNil(fixture.tokenProvider.accessToken)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testGoogleLogoutClearsSDKSessionWhenStoredCredentialsCannotBeLoaded() async throws {
    let providerSignOut = AccountLifecycleProviderSignOut()
    let fixture = makeFixture(
      provider: .google,
      providerSessionSignOut: providerSignOut
    )
    fixture.credentialStore.loadError = CredentialStoreError.invalidStoredData

    try await fixture.service.logout()

    XCTAssertEqual(providerSignOut.providers, [.google])
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testLogoutAndReloginKeepLocalProfileRoutineAndRunData() async throws {
    let localData = try makeLocalDataFixture()
    let fixture = makeFixture()

    try await fixture.service.logout()
    try fixture.accountSessionStore.establishSession(
      credentials: makeCredentials()
    )

    XCTAssertEqual(
      try localData.profileRepository.fetchProfile(),
      localData.profile
    )
    XCTAssertEqual(
      try localData.routineRepository.fetchRoutines(),
      [localData.routine]
    )
    XCTAssertEqual(
      try localData.runRepository.fetchRuns(),
      [localData.run]
    )
  }

  @MainActor
  func testGoogleLogoutClearsProviderSDKSessionAndLocalCredentials() async throws {
    let providerSignOut = AccountLifecycleProviderSignOut()
    let fixture = makeFixture(
      provider: .google,
      providerSessionSignOut: providerSignOut
    )

    try await fixture.service.logout()

    XCTAssertEqual(providerSignOut.providers, [.google])
    XCTAssertEqual(
      fixture.events.values,
      ["remote logout", "credential remove"]
    )
  }

  @MainActor
  func testWithdrawalFailureKeepsSignedInAndSkipsEveryLocalCleanup() async {
    let remoteError = APIError.server(
      statusCode: 503,
      code: "COMMON503",
      message: "unavailable"
    )
    let fixture = makeFixture(withdrawalError: remoteError)

    do {
      try await fixture.service.withdraw()
      XCTFail("Withdrawal should surface the server failure.")
    } catch let error as APIError {
      XCTAssertEqual(error, remoteError)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }

    XCTAssertEqual(fixture.events.values, ["remote withdrawal"])
    XCTAssertEqual(fixture.cleaner.memberIDs, [])
    XCTAssertEqual(fixture.credentialStore.removeCallCount, 0)
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertEqual(fixture.tokenProvider.accessToken, "access-token")
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true))
    )
  }

  @MainActor
  func testWithdrawalCleansAccountScopeBeforeRemovingCredentials() async throws {
    let fixture = makeFixture()

    try await fixture.service.withdraw()

    XCTAssertEqual(
      fixture.events.values,
      ["remote withdrawal", "account cleanup 92", "credential remove"]
    )
    XCTAssertEqual(fixture.cleaner.memberIDs, [92])
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertNil(fixture.tokenProvider.accessToken)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testWithdrawalKeepsLocalProfileRoutineAndRunData() async throws {
    let localData = try makeLocalDataFixture()
    let fixture = makeFixture()

    try await fixture.service.withdraw()

    XCTAssertEqual(
      try localData.profileRepository.fetchProfile(),
      localData.profile
    )
    XCTAssertEqual(
      try localData.routineRepository.fetchRoutines(),
      [localData.routine]
    )
    XCTAssertEqual(
      try localData.runRepository.fetchRuns(),
      [localData.run]
    )
  }

  @MainActor
  func testWithdrawalCleanupFailureStillEndsDeletedServerSession() async {
    let fixture = makeFixture(cleanupError: AccountLifecycleTestError.cleanupFailed)

    do {
      try await fixture.service.withdraw()
      XCTFail("Local cleanup failure should be reported.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .localCleanupFailed)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertEqual(
      fixture.events.values,
      ["remote withdrawal", "account cleanup 92", "credential remove"]
    )
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertNil(fixture.tokenProvider.accessToken)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testCredentialRemovalFailureStillClearsMemoryAndPublishesSignedOut() async {
    let fixture = makeFixture()
    fixture.credentialStore.removeError = AccountLifecycleTestError.removeFailed

    do {
      try await fixture.service.logout()
      XCTFail("Credential removal failure should be reported.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .localCleanupFailed)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertEqual(
      fixture.events.values,
      ["remote logout", "credential remove"]
    )
    XCTAssertNotNil(fixture.credentialStore.credentials)
    XCTAssertNil(fixture.tokenProvider.accessToken)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testPersistentSignOutGuardBlocksRelaunchUntilNewLoginSucceeds() async throws {
    let suiteName = "com.teammoru.MoruTests.account-guard.\(UUID().uuidString)"
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let restorationGuard = UserDefaultsAccountSessionRestorationGuard(
      userDefaults: userDefaults
    )
    let fixture = makeFixture(restorationGuard: restorationGuard)
    fixture.credentialStore.removeError = AccountLifecycleTestError.removeFailed

    do {
      try await fixture.service.logout()
      XCTFail("Credential removal failure should be reported.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .localCleanupFailed)
    }

    XCTAssertTrue(restorationGuard.isRestorationBlocked)
    XCTAssertEqual(
      userDefaults.object(
        forKey: UserDefaultsAccountSessionRestorationGuard.defaultKey
      ) as? Bool,
      true
    )
    XCTAssertFalse(
      String(describing: userDefaults.dictionaryRepresentation())
        .contains("access-token")
    )
    XCTAssertFalse(
      String(describing: userDefaults.dictionaryRepresentation())
        .contains("refresh-token")
    )

    let relaunchedTokenProvider = MemoryAccessTokenProvider()
    let relaunchedStore = AccountSessionStore(
      credentialStore: fixture.credentialStore,
      accessTokenProvider: relaunchedTokenProvider,
      restorationGuard: UserDefaultsAccountSessionRestorationGuard(
        userDefaults: userDefaults
      )
    )
    relaunchedStore.restore()

    XCTAssertEqual(relaunchedStore.state, .signedOut)
    XCTAssertNil(relaunchedTokenProvider.accessToken)
    XCTAssertTrue(restorationGuard.isRestorationBlocked)

    fixture.credentialStore.removeError = nil
    try relaunchedStore.establishSession(credentials: makeCredentials())

    XCTAssertFalse(restorationGuard.isRestorationBlocked)
    XCTAssertEqual(
      relaunchedStore.state,
      .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true))
    )

    let nextLaunchTokenProvider = MemoryAccessTokenProvider()
    let nextLaunchStore = AccountSessionStore(
      credentialStore: fixture.credentialStore,
      accessTokenProvider: nextLaunchTokenProvider,
      restorationGuard: UserDefaultsAccountSessionRestorationGuard(
        userDefaults: userDefaults
      )
    )
    nextLaunchStore.restore()

    XCTAssertEqual(
      nextLaunchStore.state,
      .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true))
    )
    XCTAssertEqual(nextLaunchTokenProvider.accessToken, "access-token")
  }

  @MainActor
  func testWithdrawalViewModelFailureIsRetryableAndKeepsLocalProfileContent() async {
    let lifecycleService = AccountLifecycleServiceSpy(
      withdrawalErrors: [AccountLifecycleTestError.remoteFailed, nil]
    )
    let viewModel = makeViewModel(lifecycleService: lifecycleService)
    viewModel.loadProfileSettings()

    await viewModel.withdrawalConfirmationButtonDidTap()

    XCTAssertEqual(lifecycleService.withdrawalCallCount, 1)
    XCTAssertFalse(viewModel.isAccountLifecycleInProgress)
    XCTAssertEqual(
      viewModel.accountErrorMessage,
      "회원 탈퇴를 완료하지 못했어요. "
        + "계정 연결은 유지되며 다시 시도할 수 있어요."
    )
    guard case .content(let content) = viewModel.state else {
      return XCTFail("Account failure must not replace the local Profile state.")
    }
    XCTAssertEqual(content.profile.displayName, "로컬 유지 사용자")

    await viewModel.withdrawalConfirmationButtonDidTap()

    XCTAssertEqual(lifecycleService.withdrawalCallCount, 2)
    XCTAssertNil(viewModel.accountErrorMessage)
    XCTAssertFalse(viewModel.isAccountLifecycleInProgress)
  }

  @MainActor
  func testLifecycleAccessibilityIdentifiersAreStableAndUnique() {
    let identifiers = [
      ProfileView.accountLogoutAccessibilityIdentifier,
      ProfileView.accountWithdrawalAccessibilityIdentifier,
    ]

    XCTAssertEqual(Set(identifiers).count, identifiers.count)
    XCTAssertEqual(identifiers, [
      "profile.account.logout",
      "profile.account.withdrawal",
    ])
  }

  @MainActor
  func testLifecycleCredentialDescriptionRedactsRefreshToken() throws {
    let fixture = makeFixture()
    let credentials = try fixture.accountSessionStore.credentialsForAccountLifecycle()
    let description = String(describing: credentials)
    let debugDescription = String(reflecting: credentials)

    XCTAssertFalse(description.contains("refresh-token"))
    XCTAssertFalse(debugDescription.contains("refresh-token"))
    XCTAssertTrue(description.contains("<redacted>"))
  }

  @MainActor
  private func makeFixture(
    logoutError: Error? = nil,
    withdrawalError: Error? = nil,
    cleanupError: Error? = nil,
    provider: AuthProvider = .apple,
    providerSessionSignOut: any SocialProviderSessionSigningOut =
      NoopSocialProviderSessionSignOut(),
    restorationGuard: any AccountSessionRestorationGuarding =
      InMemoryAccountSessionRestorationGuard()
  ) -> AccountLifecycleFixture {
    let events = AccountLifecycleEventRecorder()
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: makeCredentials(provider: provider),
      events: events
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider,
      restorationGuard: restorationGuard
    )
    accountSessionStore.restore()
    let remote = AccountLifecycleAuthRemoteDataSource(
      events: events,
      logoutError: logoutError,
      withdrawalError: withdrawalError
    )
    let cleaner = AccountLifecycleDataCleaner(
      events: events,
      error: cleanupError
    )
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: accountSessionStore,
      accountScopedDataCleaner: cleaner,
      providerSessionSignOut: providerSessionSignOut
    )

    return AccountLifecycleFixture(
      service: service,
      remote: remote,
      cleaner: cleaner,
      credentialStore: credentialStore,
      tokenProvider: tokenProvider,
      accountSessionStore: accountSessionStore,
      events: events
    )
  }

  @MainActor
  private func makeViewModel(
    lifecycleService: any AccountLifecycleManaging
  ) -> ProfileViewModel {
    ProfileViewModel(
      profileSettingsUseCase: AccountLifecycleProfileSettingsUseCase(),
      voicePreviewPlayer: AccountLifecycleVoicePreviewPlayer(),
      alarmService: UnavailableProfileAlarmService(),
      accountLifecycleService: lifecycleService,
      resetUseCase: nil,
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
  }

  private func makeCredentials(
    provider: AuthProvider = .apple
  ) -> AccountCredentials {
    AccountCredentials(
      memberID: 92,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      onboardingCompleted: true,
      provider: provider
    )
  }

  @MainActor
  private func makeLocalDataFixture() throws -> AccountLifecycleLocalDataFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let profileRepository = SwiftDataLocalProfileRepository(
      modelContext: container.mainContext
    )
    let routineRepository = SwiftDataRoutineRepository(
      modelContext: container.mainContext
    )
    let runRepository = SwiftDataRoutineRunRepository(
      modelContext: container.mainContext
    )
    let profile = LocalProfile(displayName: "로컬 유지 사용자")
    let routine = Routine(
      name: "로컬 유지 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "로컬 유지 단계", order: 0),
      ]
    )
    let run = RoutineRun(routine: routine)
    try profileRepository.saveProfile(profile)
    try routineRepository.saveRoutine(routine)
    try runRepository.saveRun(run)

    return AccountLifecycleLocalDataFixture(
      container: container,
      profileRepository: profileRepository,
      routineRepository: routineRepository,
      runRepository: runRepository,
      profile: profile,
      routine: routine,
      run: run
    )
  }
}

@MainActor
private final class AccountLifecycleProviderSignOut:
  SocialProviderSessionSigningOut {
  private let events: AccountLifecycleEventRecorder?
  private(set) var providers: [AuthProvider] = []

  init(events: AccountLifecycleEventRecorder? = nil) {
    self.events = events
  }

  func signOut(provider: AuthProvider) {
    providers.append(provider)
    events?.record("provider sign out \(provider.serverValue)")
  }
}

@MainActor
private struct AccountLifecycleLocalDataFixture {
  let container: ModelContainer
  let profileRepository: SwiftDataLocalProfileRepository
  let routineRepository: SwiftDataRoutineRepository
  let runRepository: SwiftDataRoutineRunRepository
  let profile: LocalProfile
  let routine: Routine
  let run: RoutineRun
}

@MainActor
private struct AccountLifecycleFixture {
  let service: DefaultAccountLifecycleService
  let remote: AccountLifecycleAuthRemoteDataSource
  let cleaner: AccountLifecycleDataCleaner
  let credentialStore: AccountLifecycleCredentialStore
  let tokenProvider: MemoryAccessTokenProvider
  let accountSessionStore: AccountSessionStore
  let events: AccountLifecycleEventRecorder
}

private enum AccountLifecycleTestError: Error {
  case cleanupFailed
  case remoteFailed
  case removeFailed
}

nonisolated private final class AccountLifecycleEventRecorder:
  @unchecked Sendable {
  private let lock = NSLock()
  private var recordedValues: [String] = []

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recordedValues
  }

  func record(_ value: String) {
    lock.lock()
    recordedValues.append(value)
    lock.unlock()
  }
}

nonisolated private final class AccountLifecycleCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private let events: AccountLifecycleEventRecorder
  private var storedCredentials: AccountCredentials?
  private var storedRemoveCallCount = 0

  var loadError: Error?
  var removeError: Error?

  init(
    credentials: AccountCredentials?,
    events: AccountLifecycleEventRecorder
  ) {
    storedCredentials = credentials
    self.events = events
  }

  var credentials: AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
  }

  var removeCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedRemoveCallCount
  }

  func load() throws -> AccountCredentials? {
    if let loadError {
      throw loadError
    }

    return credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.lock()
    storedCredentials = credentials
    lock.unlock()
  }

  func remove() throws {
    events.record("credential remove")
    lock.lock()
    storedRemoveCallCount += 1

    if let removeError {
      lock.unlock()
      throw removeError
    }

    storedCredentials = nil
    lock.unlock()
  }
}

private actor AccountLifecycleAuthRemoteDataSource: AuthRemoteDataSource {
  private let events: AccountLifecycleEventRecorder
  private let logoutError: Error?
  private let withdrawalError: Error?
  private(set) var logoutRefreshTokens: [String] = []

  init(
    events: AccountLifecycleEventRecorder,
    logoutError: Error?,
    withdrawalError: Error?
  ) {
    self.events = events
    self.logoutError = logoutError
    self.withdrawalError = withdrawalError
  }

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    throw AccountLifecycleTestError.remoteFailed
  }

  func reissue(refreshToken: String) async throws -> TokenReissueResponseDTO {
    throw AccountLifecycleTestError.remoteFailed
  }

  func logout(refreshToken: String) async throws {
    events.record("remote logout")
    logoutRefreshTokens.append(refreshToken)

    if let logoutError {
      throw logoutError
    }
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    events.record("remote withdrawal")

    if let withdrawalError {
      throw withdrawalError
    }

    return WithdrawalResponseDTO(message: "withdrawn")
  }
}

nonisolated private final class AccountLifecycleDataCleaner:
  AccountScopedDataCleaning,
  @unchecked Sendable {
  private let lock = NSLock()
  private let events: AccountLifecycleEventRecorder
  private let error: Error?
  private var storedMemberIDs: [Int64] = []

  init(
    events: AccountLifecycleEventRecorder,
    error: Error?
  ) {
    self.events = events
    self.error = error
  }

  var memberIDs: [Int64] {
    lock.lock()
    defer { lock.unlock() }
    return storedMemberIDs
  }

  func removeAccountScopedData(memberID: Int64) async throws {
    events.record("account cleanup \(memberID)")
    lock.withLock {
      storedMemberIDs.append(memberID)
    }

    if let error {
      throw error
    }
  }
}

@MainActor
private final class AccountLifecycleServiceSpy: AccountLifecycleManaging {
  private var withdrawalErrors: [Error?]
  private(set) var withdrawalCallCount = 0

  init(withdrawalErrors: [Error?]) {
    self.withdrawalErrors = withdrawalErrors
  }

  func logout() async throws {}

  func withdraw() async throws {
    let error = withdrawalErrors[withdrawalCallCount]
    withdrawalCallCount += 1

    if let error {
      throw error
    }
  }
}

@MainActor
private final class AccountLifecycleProfileSettingsUseCase:
  ProfileSettingsUseCaseProtocol {
  private let result = ProfileSettingsLoadResult(
    profile: LocalProfile(displayName: "로컬 유지 사용자"),
    fallbackNotice: nil
  )

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    result
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult {
    result
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

@MainActor
private final class AccountLifecycleVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}
