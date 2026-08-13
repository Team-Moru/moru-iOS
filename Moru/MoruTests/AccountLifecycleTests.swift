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
  func testLogoutPurgesAccountAudioBeforeRemovingCredentials() async throws {
    let fixture = makeFixture(includeRoutineTTSAudioCacheCleaner: true)

    try await fixture.service.logout()

    XCTAssertEqual(
      fixture.events.values,
      ["remote logout", "audio cleanup 92", "credential remove"]
    )
    XCTAssertEqual(fixture.audioCacheCleaner?.memberIDs, [92])
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testLogoutKeepsRestorableSessionWhenAccountAudioPurgeFails() async {
    let fixture = makeFixture(
      includeRoutineTTSAudioCacheCleaner: true,
      routineTTSAudioCleanupError: AccountLifecycleTestError.cleanupFailed
    )

    do {
      try await fixture.service.logout()
      XCTFail("Audio cleanup failure must stop credential removal.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .localCleanupFailed)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertEqual(
      fixture.events.values,
      ["remote logout", "audio cleanup 92"]
    )
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true))
    )
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
    XCTAssertEqual(providerSignOut.reasons, [.logout])
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
    XCTAssertEqual(providerSignOut.reasons, [.logout])
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
  func testWithdrawalCleanupFailureKeepsSessionForConfirmedCleanupRecovery() async {
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
      ["remote withdrawal", "account cleanup 92"]
    )
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertEqual(fixture.tokenProvider.accessToken, "access-token")
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true))
    )
  }

  @MainActor
  func testWithdrawalPersistsEveryCleanupPhaseBeforeRemovingMatchingCredentials() async throws {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let fixture = makePhaseFixture(events: events, cleaner: cleaner)

    try await fixture.service.withdraw()

    XCTAssertEqual(
      events.values,
      [
        "prepare",
        "attempting",
        "remote withdrawal",
        "confirmed",
        "localDataCleaned",
        "provider withdrawal",
        "credential remove",
        "finalize",
      ]
    )
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
  }

  @MainActor
  func testWithdrawalPrepareOrAttemptFailureNeverCallsRemoteWithdrawal() async {
    for phase in [
      AccountLifecycleCleanupPhase.prepare,
      .attempting,
    ] {
      let events = AccountLifecycleEventRecorder()
      let cleaner = PhaseAwareAccountLifecycleDataCleaner(
        events: events,
        failingPhase: phase
      )
      let fixture = makePhaseFixture(events: events, cleaner: cleaner)

      do {
        try await fixture.service.withdraw()
        XCTFail("Expected local cleanup failure for \(phase)")
      } catch let error as AccountLifecycleError {
        XCTAssertEqual(error, .localCleanupFailed)
      } catch {
        XCTFail("Expected AccountLifecycleError, got \(error)")
      }

      XCTAssertFalse(events.values.contains("remote withdrawal"))
      XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
      XCTAssertEqual(
        fixture.accountSessionStore.state,
        .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true))
      )
    }
  }

  @MainActor
  func testDefinitiveWithdrawalFailureCancelsMarkerAndKeepsSession() async {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let fixture = makePhaseFixture(
      events: events,
      cleaner: cleaner,
      withdrawalError: APIError.server(statusCode: 400, code: "BAD", message: "no")
    )

    do {
      try await fixture.service.withdraw()
      XCTFail("Expected definitive remote failure")
    } catch {}

    XCTAssertEqual(
      events.values,
      ["prepare", "attempting", "remote withdrawal", "cancelled"]
    )
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
  }

  @MainActor
  func testAmbiguousTransportWithdrawalKeepsAttemptingMarkerAndSession() async {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let fixture = makePhaseFixture(
      events: events,
      cleaner: cleaner,
      withdrawalError: APIError.transport(code: -1001, message: "timeout")
    )

    do {
      try await fixture.service.withdraw()
      XCTFail("Expected ambiguous transport failure")
    } catch {}

    XCTAssertEqual(events.values, ["prepare", "attempting", "remote withdrawal"])
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertEqual(cleaner.completedPhases, [.prepare, .attempting])
  }

  @MainActor
  func testConfirmedCleanupFailurePreservesCredentialsAndSkipsProviderSignOut() async {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(
      events: events,
      failingPhase: .localDataCleaned
    )
    let fixture = makePhaseFixture(events: events, cleaner: cleaner)

    do {
      try await fixture.service.withdraw()
      XCTFail("Expected confirmed local cleanup failure")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .localCleanupFailed)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertEqual(
      events.values,
      ["prepare", "attempting", "remote withdrawal", "confirmed", "localDataCleaned"]
    )
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertEqual(fixture.accountSessionStore.state, .signedIn(SignedInAccount(memberID: 92, onboardingCompleted: true)))
  }

  @MainActor
  func testWithdrawalDoesNotDeleteNewAccountThatReplacesCapturedAccountDuringProviderAwait() async throws {
    let events = AccountLifecycleEventRecorder()
    let capturedCredentials = makeCredentials()
    let replacementCredentials = AccountCredentials(
      memberID: 93,
      accessToken: "account-b-access",
      refreshToken: "account-b-refresh",
      onboardingCompleted: false,
      provider: .google
    )
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: capturedCredentials,
      events: events
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider,
      restorationGuard: InMemoryAccountSessionRestorationGuard()
    )
    sessionStore.restore()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: AccountLifecycleAuthRemoteDataSource(
        events: events,
        logoutError: nil,
        withdrawalError: nil
      ),
      accountSessionStore: sessionStore,
      accountScopedDataCleaner: cleaner,
      providerSessionSignOut: AccountLifecycleAccountSwitchingProvider(
        accountSessionStore: sessionStore,
        replacementCredentials: replacementCredentials,
        events: events
      )
    )

    try await service.withdraw()

    XCTAssertEqual(credentialStore.credentials, replacementCredentials)
    XCTAssertEqual(tokenProvider.accessToken, replacementCredentials.accessToken)
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: replacementCredentials.memberID,
          onboardingCompleted: replacementCredentials.onboardingCompleted,
          provider: replacementCredentials.provider
        )
      )
    )
    XCTAssertEqual(
      cleaner.completedPhases,
      [.prepare, .attempting, .confirmed, .localDataCleaned, .finalize]
    )
    XCTAssertEqual(
      events.values,
      [
        "prepare",
        "attempting",
        "remote withdrawal",
        "confirmed",
        "localDataCleaned",
        "provider switches account",
        "finalize",
      ]
    )
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
  func testMemberScopedStoredSessionRemovalNeverDeletesAnotherAccount() throws {
    let fixture = makeFixture()

    XCTAssertFalse(
      try fixture.accountSessionStore.removeStoredSessionIfMatching(memberID: 93)
    )
    XCTAssertEqual(fixture.credentialStore.credentials?.memberID, 92)
    XCTAssertEqual(fixture.tokenProvider.accessToken, "access-token")

    XCTAssertTrue(
      try fixture.accountSessionStore.removeStoredSessionIfMatching(memberID: 92)
    )
    XCTAssertNil(fixture.credentialStore.credentials)
    XCTAssertNil(fixture.tokenProvider.accessToken)
  }

  @MainActor
  private func makeFixture(
    logoutError: Error? = nil,
    withdrawalError: Error? = nil,
    cleanupError: Error? = nil,
    provider: AuthProvider = .apple,
    providerSessionSignOut: any SocialProviderSessionSigningOut =
      NoopSocialProviderSessionSignOut(),
    includeRoutineTTSAudioCacheCleaner: Bool = false,
    routineTTSAudioCleanupError: Error? = nil,
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
    let audioCacheCleaner = includeRoutineTTSAudioCacheCleaner
      ? AccountLifecycleRoutineTTSAudioCacheCleaner(
          events: events,
          error: routineTTSAudioCleanupError
        )
      : nil
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: accountSessionStore,
      accountScopedDataCleaner: cleaner,
      providerSessionSignOut: providerSessionSignOut,
      routineTTSAudioCacheCleaner: audioCacheCleaner
    )

    return AccountLifecycleFixture(
      service: service,
      remote: remote,
      cleaner: cleaner,
      credentialStore: credentialStore,
      tokenProvider: tokenProvider,
      accountSessionStore: accountSessionStore,
      audioCacheCleaner: audioCacheCleaner,
      events: events
    )
  }

  @MainActor
  private func makePhaseFixture(
    events: AccountLifecycleEventRecorder,
    cleaner: PhaseAwareAccountLifecycleDataCleaner,
    withdrawalError: Error? = nil
  ) -> AccountLifecyclePhaseFixture {
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: makeCredentials(),
      events: events
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider,
      restorationGuard: InMemoryAccountSessionRestorationGuard()
    )
    accountSessionStore.restore()
    let remote = AccountLifecycleAuthRemoteDataSource(
      events: events,
      logoutError: nil,
      withdrawalError: withdrawalError
    )
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: accountSessionStore,
      accountScopedDataCleaner: cleaner,
      providerSessionSignOut: AccountLifecyclePhaseProvider(events: events)
    )
    return AccountLifecyclePhaseFixture(
      service: service,
      credentialStore: credentialStore,
      accountSessionStore: accountSessionStore
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
  private(set) var reasons: [SocialProviderSessionSignOutReason] = []

  init(events: AccountLifecycleEventRecorder? = nil) {
    self.events = events
  }

  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws {
    providers.append(provider)
    reasons.append(reason)
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
  let audioCacheCleaner: AccountLifecycleRoutineTTSAudioCacheCleaner?
  let events: AccountLifecycleEventRecorder
}

@MainActor
private struct AccountLifecyclePhaseFixture {
  let service: DefaultAccountLifecycleService
  let credentialStore: AccountLifecycleCredentialStore
  let accountSessionStore: AccountSessionStore
}

private enum AccountLifecycleCleanupPhase: Equatable {
  case prepare
  case attempting
  case confirmed
  case localDataCleaned
  case cancelled
  case finalize
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

@MainActor
private final class AccountLifecyclePhaseProvider:
  SocialProviderSessionSigningOut {
  private let events: AccountLifecycleEventRecorder

  init(events: AccountLifecycleEventRecorder) {
    self.events = events
  }

  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws {
    if reason == .withdrawal {
      events.record("provider withdrawal")
    }
  }
}

@MainActor
private final class AccountLifecycleAccountSwitchingProvider:
  SocialProviderSessionSigningOut {
  private let accountSessionStore: AccountSessionStore
  private let replacementCredentials: AccountCredentials
  private let events: AccountLifecycleEventRecorder

  init(
    accountSessionStore: AccountSessionStore,
    replacementCredentials: AccountCredentials,
    events: AccountLifecycleEventRecorder
  ) {
    self.accountSessionStore = accountSessionStore
    self.replacementCredentials = replacementCredentials
    self.events = events
  }

  func signOut(
    provider: AuthProvider,
    reason: SocialProviderSessionSignOutReason
  ) async throws {
    events.record("provider switches account")
    try accountSessionStore.establishSession(credentials: replacementCredentials)
    await Task.yield()
  }
}

nonisolated private final class PhaseAwareAccountLifecycleDataCleaner:
  AccountScopedDataCleaning,
  @unchecked Sendable {
  private let lock = NSLock()
  private let events: AccountLifecycleEventRecorder
  private let failingPhase: AccountLifecycleCleanupPhase?
  private var phases: [AccountLifecycleCleanupPhase] = []

  init(
    events: AccountLifecycleEventRecorder,
    failingPhase: AccountLifecycleCleanupPhase? = nil
  ) {
    self.events = events
    self.failingPhase = failingPhase
  }

  var completedPhases: [AccountLifecycleCleanupPhase] {
    lock.lock()
    defer { lock.unlock() }
    return phases
  }

  func removeAccountScopedData(memberID: Int64) async throws {
    try record(.localDataCleaned, event: "localDataCleaned")
  }

  func preparePendingAccountCleanup(memberID: Int64) async throws {
    try record(.prepare, event: "prepare")
  }

  func beginPendingAccountCleanupAttempt(memberID: Int64) async throws {
    try record(.attempting, event: "attempting")
  }

  func confirmPendingAccountCleanup(memberID: Int64) async throws {
    try record(.confirmed, event: "confirmed")
  }

  func cancelPendingAccountCleanup(memberID: Int64) async throws {
    try record(.cancelled, event: "cancelled")
  }

  func completePendingAccountCleanup(memberID: Int64) async throws {
    try record(.localDataCleaned, event: "localDataCleaned")
  }

  func finalizePendingAccountCleanup(memberID: Int64) async throws {
    try record(.finalize, event: "finalize")
  }

  func recoverPendingAccountCleanups() async throws -> PendingAccountCleanupRecovery {
    .none
  }

  private func record(
    _ phase: AccountLifecycleCleanupPhase,
    event: String
  ) throws {
    events.record(event)
    lock.lock()
    phases.append(phase)
    lock.unlock()
    if failingPhase == phase {
      throw AccountLifecycleTestError.cleanupFailed
    }
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

nonisolated private final class AccountLifecycleRoutineTTSAudioCacheCleaner:
  RoutineTTSAudioCacheCleaning,
  @unchecked Sendable {
  private let lock = NSLock()
  private let events: AccountLifecycleEventRecorder
  private let error: Error?
  private var storedMemberIDs: [Int64] = []

  init(events: AccountLifecycleEventRecorder, error: Error?) {
    self.events = events
    self.error = error
  }

  var memberIDs: [Int64] {
    lock.withLock { storedMemberIDs }
  }

  func removeAllRoutineTTSAudio() async throws {}

  func removeRoutineTTSAudio(memberID: Int64) async throws {
    events.record("audio cleanup \(memberID)")
    lock.withLock { storedMemberIDs.append(memberID) }
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
