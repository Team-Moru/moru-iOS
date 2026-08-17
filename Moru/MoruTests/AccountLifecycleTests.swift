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
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
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
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
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
  func testAmbiguousWithdrawalFailureEntersRestrictedRecoveryAndSkipsCleanup() async {
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
    XCTAssertNil(fixture.tokenProvider.accessToken)
    let withdrawalAccessTokens = await fixture.remote.withdrawalAccessTokens
    XCTAssertEqual(withdrawalAccessTokens, ["access-token"])
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )
    XCTAssertNil(fixture.accountSessionStore.signedInMemberID)
    XCTAssertNil(fixture.accountSessionStore.currentAccountSessionIdentity)
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
  func testWithdrawalCleanupFailureKeepsRestrictedConfirmedRecovery() async {
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
    XCTAssertNil(fixture.tokenProvider.accessToken)
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
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
        XCTAssertEqual(error, .withdrawalStateUnavailable)
      } catch {
        XCTFail("Expected AccountLifecycleError, got \(error)")
      }

      XCTAssertFalse(events.values.contains("remote withdrawal"))
      XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
      XCTAssertEqual(
        fixture.accountSessionStore.state,
        .withdrawalPending(
          SignedInAccount(memberID: 92, onboardingCompleted: true)
        )
      )
      XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
    }
  }

  @MainActor
  func testUndocumentedBadRequestStaysAmbiguousAndPreservesCredential() async {
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
      ["prepare", "attempting", "remote withdrawal"]
    )
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertEqual(cleaner.completedPhases, [.prepare, .attempting])
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )
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
    XCTAssertNil(
      fixture.accountSessionStore.accessTokenProvider.accessToken
    )
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )
  }

  @MainActor
  func testAmbiguousTransportWithdrawalRetrySendsDeleteAgainAndCompletes() async throws {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let timeout = APIError.transport(code: -1001, message: "timeout")
    let fixture = makePhaseFixture(
      events: events,
      cleaner: cleaner,
      withdrawalErrors: [timeout, nil]
    )

    do {
      try await fixture.service.withdraw()
      XCTFail("The first ambiguous DELETE must not be reported as success.")
    } catch let error as APIError {
      XCTAssertEqual(error, timeout)
    } catch {
      XCTFail("Expected the transport error, got \(error)")
    }

    try await fixture.service.withdraw()

    XCTAssertEqual(
      events.values,
      [
        "prepare",
        "attempting",
        "remote withdrawal",
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
  func testPersistentAttemptingMarkerRetriesActualDeleteAndThenFinalizes() async throws {
    let events = AccountLifecycleEventRecorder()
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: makeCredentials(),
      events: events
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    sessionStore.restore()
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    let remote = AccountLifecycleAuthRemoteDataSource(
      events: events,
      logoutError: nil,
      withdrawalErrors: [
        APIError.transport(code: -1001, message: "timeout"),
        nil,
      ]
    )
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: sessionStore,
      accountScopedDataCleaner: SwiftDataRoutineSyncAccountCleaner(
        repository: repository
      )
    )

    do {
      try await service.withdraw()
      XCTFail("The first timeout must remain ambiguous.")
    } catch let error as APIError {
      XCTAssertEqual(
        error,
        APIError.transport(code: -1001, message: "timeout")
      )
    }

    XCTAssertEqual(
      try repository.pendingAccountCleanupRecovery().ambiguousMemberIDs,
      [92]
    )
    XCTAssertEqual(sessionStore.signedInMemberID, nil)

    try await service.withdraw()

    let retryRequestCount = await remote.withdrawalRequestCount
    XCTAssertEqual(retryRequestCount, 2)
    XCTAssertEqual(try repository.pendingAccountCleanupRecovery(), .none)
    XCTAssertNil(credentialStore.credentials)
    XCTAssertEqual(sessionStore.state, .signedOut)
  }

  @MainActor
  func testRecoveredRemoteConfirmationCompletesLocallyWithoutSecondDelete()
    async throws {
    let events = AccountLifecycleEventRecorder()
    let credentials = makeCredentials()
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: credentials,
      events: events
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    try repository.preparePendingAccountCleanup(memberID: 92, at: Date())
    try repository.beginPendingAccountCleanupAttempt(memberID: 92)
    try repository.confirmPendingAccountCleanup(memberID: 92)
    XCTAssertTrue(
      try sessionStore.preparePendingWithdrawalRetry(matching: [92])
    )
    let remote = AccountLifecycleAuthRemoteDataSource(
      events: events,
      logoutError: nil,
      withdrawalError: nil
    )
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: sessionStore,
      accountScopedDataCleaner: SwiftDataRoutineSyncAccountCleaner(
        repository: repository
      )
    )

    try await service.withdraw()

    let recoveredRequestCount = await remote.withdrawalRequestCount
    XCTAssertEqual(recoveredRequestCount, 0)
    XCTAssertEqual(try repository.pendingAccountCleanupRecovery(), .none)
    XCTAssertNil(credentialStore.credentials)
    XCTAssertNil(tokenProvider.accessToken)
    XCTAssertEqual(sessionStore.state, .signedOut)
  }

  @MainActor
  func testConcurrentWithdrawalCallsShareOneActiveDelete() async throws {
    let events = AccountLifecycleEventRecorder()
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: makeCredentials(),
      events: events
    )
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    sessionStore.restore()
    let remote = BlockingAccountLifecycleAuthRemoteDataSource()
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: sessionStore,
      accountScopedDataCleaner: PhaseAwareAccountLifecycleDataCleaner(
        events: events
      )
    )

    let first = Task { try await service.withdraw() }
    await remote.waitUntilWithdrawalStarts()
    let second = Task { try await service.withdraw() }
    await Task.yield()

    let activeRequestCount = await remote.withdrawalRequestCount
    XCTAssertEqual(activeRequestCount, 1)
    await remote.releaseWithdrawal()
    try await first.value
    try await second.value
    let finalRequestCount = await remote.withdrawalRequestCount
    XCTAssertEqual(finalRequestCount, 1)
    XCTAssertEqual(sessionStore.state, .signedOut)
  }

  @MainActor
  func testLogoutInFlightRejectsWithdrawalBeforeDeleteStarts() async throws {
    let events = AccountLifecycleEventRecorder()
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: makeCredentials(),
      events: events
    )
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    sessionStore.restore()
    let remote = BlockingLogoutAccountLifecycleAuthRemoteDataSource()
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: sessionStore,
      accountScopedDataCleaner: NoAccountScopedDataCleaner()
    )

    let logoutTask = Task { try await service.logout() }
    await remote.waitUntilLogoutStarts()

    do {
      try await service.withdraw()
      XCTFail("Withdrawal must not enter while logout owns the credential.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .sessionUnavailable)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    let withdrawalRequestCount = await remote.withdrawalRequestCount
    XCTAssertEqual(withdrawalRequestCount, 0)
    XCTAssertEqual(credentialStore.credentials, makeCredentials())

    await remote.releaseLogout()
    try await logoutTask.value

    XCTAssertNil(credentialStore.credentials)
    XCTAssertEqual(sessionStore.state, .signedOut)
  }

  @MainActor
  func testLogoutInFlightRejectsReplacementCredentialSave() async throws {
    let events = AccountLifecycleEventRecorder()
    let originalCredentials = makeCredentials()
    let credentialStore = AccountLifecycleCredentialStore(
      credentials: originalCredentials,
      events: events
    )
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    sessionStore.restore()
    let remote = BlockingLogoutAccountLifecycleAuthRemoteDataSource()
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: sessionStore,
      accountScopedDataCleaner: NoAccountScopedDataCleaner()
    )
    let replacementCredentials = AccountCredentials(
      memberID: 93,
      accessToken: "replacement-access",
      refreshToken: "replacement-refresh",
      onboardingCompleted: false,
      provider: .google
    )

    let logoutTask = Task { try await service.logout() }
    await remote.waitUntilLogoutStarts()

    XCTAssertThrowsError(
      try sessionStore.establishSession(credentials: replacementCredentials)
    ) { error in
      XCTAssertEqual(error as? CredentialStoreError, .invalidCredentials)
    }
    XCTAssertEqual(credentialStore.credentials, originalCredentials)
    XCTAssertEqual(tokenProvider.accessToken, originalCredentials.accessToken)

    await remote.releaseLogout()
    try await logoutTask.value

    XCTAssertNil(credentialStore.credentials)
    XCTAssertNil(tokenProvider.accessToken)
    XCTAssertEqual(sessionStore.state, .signedOut)
  }

  @MainActor
  func testPendingWithdrawalRejectsLogoutAndPreservesRecoveryCredential() async {
    let events = AccountLifecycleEventRecorder()
    let fixture = makePhaseFixture(
      events: events,
      cleaner: PhaseAwareAccountLifecycleDataCleaner(
        events: events
      ),
      withdrawalError: APIError.transport(code: -1001, message: "timeout")
    )

    do { try await fixture.service.withdraw() } catch {}

    do {
      try await fixture.service.logout()
      XCTFail("Logout must not discard an ambiguous withdrawal credential.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .sessionUnavailable)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertNil(fixture.accountSessionStore.signedInMemberID)
  }

  @MainActor
  func testUndocumentedAuthenticationMissingConflictAndGoneStayAmbiguous() async {
    for statusCode in [401, 404, 409, 410] {
      let events = AccountLifecycleEventRecorder()
      let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
      let fixture = makePhaseFixture(
        events: events,
        cleaner: cleaner,
        withdrawalError: APIError.server(
          statusCode: statusCode,
          code: "UNCONFIRMED_CONTRACT",
          message: "meaning not documented"
        )
      )

      do {
        try await fixture.service.withdraw()
        XCTFail("HTTP \(statusCode) must not be inferred as deletion success.")
      } catch {}

      XCTAssertEqual(
        events.values,
        ["prepare", "attempting", "remote withdrawal"],
        "HTTP \(statusCode) must retain the attempting marker until the backend contract is confirmed."
      )
      XCTAssertEqual(cleaner.completedPhases, [.prepare, .attempting])
      XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
      XCTAssertNil(fixture.accountSessionStore.signedInMemberID)
      XCTAssertNil(fixture.accountSessionStore.currentAccountSessionIdentity)
    }
  }

  @MainActor
  func testMember4091RemainsPendingWithoutCleanup() async {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let fixture = makePhaseFixture(
      events: events,
      cleaner: cleaner,
      withdrawalError: APIError.server(
        statusCode: 409,
        code: "MEMBER4091",
        message: "documented withdrawal conflict"
      )
    )

    do {
      try await fixture.service.withdraw()
      XCTFail("MEMBER4091 must not be reported as deletion success.")
    } catch let error as APIError {
      XCTAssertEqual(
        error,
        APIError.server(
          statusCode: 409,
          code: "MEMBER4091",
          message: "documented withdrawal conflict"
        )
      )
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }

    XCTAssertEqual(
      events.values,
      ["prepare", "attempting", "remote withdrawal"]
    )
    XCTAssertEqual(cleaner.completedPhases, [.prepare, .attempting])
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )
    XCTAssertNil(fixture.accountSessionStore.signedInMemberID)
    XCTAssertNil(fixture.accountSessionStore.currentAccountSessionIdentity)
    let requestCount = await fixture.remote.withdrawalRequestCount
    XCTAssertEqual(requestCount, 1)
  }

  @MainActor
  func testAuth4091RequiresAppleReauthenticationAndKeepsDeletionPending()
    async throws {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let refreshedLogin = LoginResponseDTO(
      memberId: 92,
      accessToken: "reauthenticated-access-token",
      refreshToken: "reauthenticated-refresh-token",
      isNewMember: false,
      onboardingCompleted: true
    )
    let fixture = makePhaseFixture(
      events: events,
      cleaner: cleaner,
      withdrawalErrors: [
        APIError.server(
          statusCode: 409,
          code: "AUTH4091",
          message: "Apple reauthentication required"
        ),
        nil,
      ],
      loginResponse: refreshedLogin
    )

    do {
      try await fixture.service.withdraw()
      XCTFail("AUTH4091 must not be reported as deletion success.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .appleReauthenticationRequired)
    } catch {
      XCTFail("Expected Apple reauthentication requirement, got \(error)")
    }

    XCTAssertEqual(
      events.values,
      ["prepare", "attempting", "remote withdrawal"]
    )
    XCTAssertEqual(cleaner.completedPhases, [.prepare, .attempting])
    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )

    let authorization = makeAppleWithdrawalAuthorization()
    try await fixture.service.reauthenticateAppleWithdrawal(
      with: authorization
    )

    let loginProviders = await fixture.remote.loginProviders
    let loginRequests = await fixture.remote.loginRequests
    XCTAssertEqual(loginProviders, [.apple])
    XCTAssertEqual(
      loginRequests,
      [
        SocialLoginRequestDTO(
          token: authorization.token,
          authorizationCode: authorization.authorizationCode
        ),
      ]
    )
    XCTAssertEqual(
      fixture.credentialStore.credentials,
      AccountCredentials(
        memberID: 92,
        accessToken: "reauthenticated-access-token",
        refreshToken: "reauthenticated-refresh-token",
        onboardingCompleted: true,
        provider: .apple,
        providerUserIdentifier: "apple-user-92"
      )
    )
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(
          memberID: 92,
          onboardingCompleted: true,
          provider: .apple,
          providerUserIdentifier: "apple-user-92"
        )
      )
    )

    try await fixture.service.withdraw()

    let withdrawalTokens = await fixture.remote.withdrawalAccessTokens
    XCTAssertEqual(
      withdrawalTokens,
      ["access-token", "reauthenticated-access-token"]
    )
    XCTAssertEqual(fixture.accountSessionStore.state, .signedOut)
    XCTAssertNil(fixture.credentialStore.credentials)
  }

  @MainActor
  func testAppleWithdrawalReauthenticationRejectsDifferentAccount() async {
    let events = AccountLifecycleEventRecorder()
    let cleaner = PhaseAwareAccountLifecycleDataCleaner(events: events)
    let fixture = makePhaseFixture(
      events: events,
      cleaner: cleaner,
      withdrawalError: APIError.server(
        statusCode: 409,
        code: "AUTH4091",
        message: "Apple reauthentication required"
      ),
      loginResponse: LoginResponseDTO(
        memberId: 93,
        accessToken: "other-access-token",
        refreshToken: "other-refresh-token",
        isNewMember: false,
        onboardingCompleted: true
      )
    )

    do {
      try await fixture.service.withdraw()
      XCTFail("Expected Apple reauthentication requirement.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .appleReauthenticationRequired)
    } catch {
      XCTFail("Expected Apple reauthentication requirement, got \(error)")
    }

    do {
      try await fixture.service.reauthenticateAppleWithdrawal(
        with: makeAppleWithdrawalAuthorization()
      )
      XCTFail("A different Apple account must be rejected.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .sessionUnavailable)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertEqual(fixture.credentialStore.credentials, makeCredentials())
    XCTAssertNil(fixture.accountSessionStore.accessTokenProvider.accessToken)
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )
    let withdrawalRequestCount = await fixture.remote.withdrawalRequestCount
    XCTAssertEqual(withdrawalRequestCount, 1)
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
    XCTAssertNil(
      fixture.accountSessionStore.accessTokenProvider.accessToken
    )
    XCTAssertEqual(
      fixture.accountSessionStore.state,
      .withdrawalPending(
        SignedInAccount(memberID: 92, onboardingCompleted: true)
      )
    )
  }

  @MainActor
  func testWithdrawalBlocksAccountReplacementUntilConfirmedCleanupSettles() async {
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

    do {
      try await service.withdraw()
      XCTFail("The rejected provider account switch must be reported.")
    } catch let error as AccountLifecycleError {
      XCTAssertEqual(error, .localCleanupFailed)
    } catch {
      XCTFail("Expected AccountLifecycleError, got \(error)")
    }

    XCTAssertNil(credentialStore.credentials)
    XCTAssertNil(tokenProvider.accessToken)
    XCTAssertEqual(sessionStore.state, .signedOut)
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
        "credential remove",
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
        + "서버 처리 결과를 확인할 수 없어 다시 시도해야 해요."
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
  func testWithdrawalViewModelKeepsPendingStateWhenAppleReauthenticationIsCancelled()
    async {
    let lifecycleService = AccountLifecycleServiceSpy(
      withdrawalErrors: [AccountLifecycleError.appleReauthenticationRequired, nil]
    )
    let viewModel = makeViewModel(lifecycleService: lifecycleService)
    viewModel.loadProfileSettings()

    await viewModel.withdrawalConfirmationButtonDidTap()

    XCTAssertEqual(lifecycleService.withdrawalCallCount, 1)
    XCTAssertTrue(viewModel.requiresAppleWithdrawalReauthentication)
    XCTAssertTrue(viewModel.canBeginAppleWithdrawalReauthentication)
    XCTAssertEqual(
      viewModel.accountErrorMessage,
      "Apple로 다시 인증한 뒤 회원탈퇴를 계속해 주세요. "
        + "로컬 데이터는 유지되며, 인증 전에는 삭제를 완료하지 않아요."
    )

    XCTAssertTrue(viewModel.appleWithdrawalReauthenticationWillBegin())
    XCTAssertTrue(viewModel.isAppleWithdrawalReauthenticationInProgress)
    await viewModel.appleWithdrawalReauthenticationDidComplete(.cancelled)

    XCTAssertEqual(lifecycleService.reauthenticationCallCount, 0)
    XCTAssertEqual(lifecycleService.withdrawalCallCount, 1)
    XCTAssertTrue(viewModel.requiresAppleWithdrawalReauthentication)
    XCTAssertFalse(viewModel.isAppleWithdrawalReauthenticationInProgress)
    XCTAssertTrue(viewModel.canBeginAppleWithdrawalReauthentication)
    XCTAssertEqual(
      viewModel.accountErrorMessage,
      "Apple 재인증을 취소했어요. 회원탈퇴는 완료되지 않았으며 다시 시도할 수 있어요."
    )

    XCTAssertTrue(viewModel.appleWithdrawalReauthenticationWillBegin())
    await viewModel.appleWithdrawalReauthenticationDidComplete(
      .authorized(makeAppleWithdrawalAuthorization())
    )

    XCTAssertEqual(lifecycleService.reauthenticationCallCount, 1)
    XCTAssertEqual(lifecycleService.withdrawalCallCount, 2)
    XCTAssertFalse(viewModel.requiresAppleWithdrawalReauthentication)
    XCTAssertFalse(viewModel.isAccountLifecycleInProgress)
  }

  @MainActor
  func testLifecycleAccessibilityIdentifiersAreStableAndUnique() {
    let identifiers = [
      ProfileView.accountLogoutAccessibilityIdentifier,
      ProfileView.accountWithdrawalAccessibilityIdentifier,
      ProfileView.accountWithdrawalRetryAccessibilityIdentifier,
      ProfileView.appleWithdrawalReauthenticationAccessibilityIdentifier,
    ]

    XCTAssertEqual(Set(identifiers).count, identifiers.count)
    XCTAssertEqual(identifiers, [
      "profile.account.logout",
      "profile.account.withdrawal",
      "profile.account.withdrawal-retry",
      "profile.account.withdrawal.apple-reauthentication",
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
    XCTAssertFalse(description.contains("access-token"))
    XCTAssertFalse(debugDescription.contains("access-token"))
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
    withdrawalError: Error? = nil,
    withdrawalErrors: [Error?]? = nil,
    loginResponse: LoginResponseDTO? = nil
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
      withdrawalErrors: withdrawalErrors ?? [withdrawalError],
      loginResponse: loginResponse
    )
    let service = DefaultAccountLifecycleService(
      authRemoteDataSource: remote,
      accountSessionStore: accountSessionStore,
      accountScopedDataCleaner: cleaner,
      providerSessionSignOut: AccountLifecyclePhaseProvider(events: events)
    )
    return AccountLifecyclePhaseFixture(
      service: service,
      remote: remote,
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

  private func makeAppleWithdrawalAuthorization() -> SocialAuthorization {
    SocialAuthorization(
      provider: .apple,
      token: "reauthenticated-identity-token",
      authorizationCode: "reauthenticated-authorization-code",
      providerUserIdentifier: "apple-user-92"
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
  let remote: AccountLifecycleAuthRemoteDataSource
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
  private let withdrawalErrors: [Error?]
  private let loginResponse: LoginResponseDTO?
  private(set) var logoutRefreshTokens: [String] = []
  private(set) var loginProviders: [AuthProvider] = []
  private(set) var loginRequests: [SocialLoginRequestDTO] = []
  private var withdrawalCallCount = 0
  private(set) var withdrawalAccessTokens: [String] = []

  var withdrawalRequestCount: Int { withdrawalCallCount }

  init(
    events: AccountLifecycleEventRecorder,
    logoutError: Error?,
    withdrawalError: Error?,
    loginResponse: LoginResponseDTO? = nil
  ) {
    self.init(
      events: events,
      logoutError: logoutError,
      withdrawalErrors: [withdrawalError],
      loginResponse: loginResponse
    )
  }

  init(
    events: AccountLifecycleEventRecorder,
    logoutError: Error?,
    withdrawalErrors: [Error?],
    loginResponse: LoginResponseDTO? = nil
  ) {
    self.events = events
    self.logoutError = logoutError
    self.withdrawalErrors = withdrawalErrors
    self.loginResponse = loginResponse
  }

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    loginProviders.append(provider)
    loginRequests.append(request)
    guard let loginResponse else {
      throw AccountLifecycleTestError.remoteFailed
    }
    return loginResponse
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

    let error: Error? = if withdrawalErrors.indices.contains(withdrawalCallCount) {
      withdrawalErrors[withdrawalCallCount]
    } else {
      withdrawalErrors.last ?? nil
    }
    withdrawalCallCount += 1

    if let error {
      throw error
    }

    return WithdrawalResponseDTO(status: .completed, message: "withdrawn")
  }

  func withdraw(accessToken: String) async throws -> WithdrawalResponseDTO {
    withdrawalAccessTokens.append(accessToken)
    return try await withdraw()
  }
}

private actor BlockingAccountLifecycleAuthRemoteDataSource:
  AuthRemoteDataSource {
  private var continuation: CheckedContinuation<Void, Never>?
  private var startedCount = 0
  private(set) var withdrawalAccessTokens: [String] = []

  var withdrawalRequestCount: Int { startedCount }

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
    throw AccountLifecycleTestError.remoteFailed
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    startedCount += 1
    await withCheckedContinuation { continuation = $0 }
    return WithdrawalResponseDTO(status: .completed, message: "withdrawn")
  }

  func withdraw(accessToken: String) async throws -> WithdrawalResponseDTO {
    withdrawalAccessTokens.append(accessToken)
    return try await withdraw()
  }

  func waitUntilWithdrawalStarts() async {
    while startedCount == 0 {
      await Task.yield()
    }
  }

  func releaseWithdrawal() {
    continuation?.resume()
    continuation = nil
  }
}

private actor BlockingLogoutAccountLifecycleAuthRemoteDataSource:
  AuthRemoteDataSource {
  private var logoutContinuation: CheckedContinuation<Void, Never>?
  private var logoutStartedCount = 0
  private(set) var withdrawalRequestCount = 0

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
    logoutStartedCount += 1
    await withCheckedContinuation { logoutContinuation = $0 }
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    withdrawalRequestCount += 1
    return WithdrawalResponseDTO(status: .completed, message: "withdrawn")
  }

  func waitUntilLogoutStarts() async {
    while logoutStartedCount == 0 {
      await Task.yield()
    }
  }

  func releaseLogout() {
    logoutContinuation?.resume()
    logoutContinuation = nil
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
  private var reauthenticationErrors: [Error?]
  private(set) var withdrawalCallCount = 0
  private(set) var reauthenticationCallCount = 0

  init(
    withdrawalErrors: [Error?],
    reauthenticationErrors: [Error?] = []
  ) {
    self.withdrawalErrors = withdrawalErrors
    self.reauthenticationErrors = reauthenticationErrors
  }

  func logout() async throws {}

  func withdraw() async throws {
    let error = withdrawalErrors[withdrawalCallCount]
    withdrawalCallCount += 1

    if let error {
      throw error
    }
  }

  func reauthenticateAppleWithdrawal(
    with authorization: SocialAuthorization
  ) async throws {
    let error: Error? = if reauthenticationErrors.indices.contains(
      reauthenticationCallCount
    ) {
      reauthenticationErrors[reauthenticationCallCount]
    } else {
      nil
    }
    reauthenticationCallCount += 1

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
