//
//  OnboardingStatusRuntimeCoordinatorTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest

@testable import Moru

@MainActor
final class OnboardingStatusRuntimeCoordinatorTests: XCTestCase {
  func testSignedOutDoesNotFetchStatus() async {
    let fixture = makeFixture(outcomes: [.status(true)])

    fixture.coordinator.start()
    await drainMainActor()

    let requestCount = await fixture.service.requestCount
    XCTAssertEqual(requestCount, 0)
    XCTAssertNil(fixture.coordinator.latestResolution)
  }

  func testLoginStatePublicationFetchesAndPublishesStatus() async throws {
    let fixture = makeFixture(
      outcomes: [.status(true)],
      localCompleted: true
    )
    fixture.coordinator.start()

    try fixture.establishSession(memberID: 11, completed: false)
    try await waitUntil { fixture.coordinator.latestResolution != nil }

    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    let identities = await fixture.service.identities
    XCTAssertEqual(identities, [identity])
    XCTAssertEqual(
      fixture.coordinator.latestResolution,
      OnboardingStatusResolution(
        identity: identity,
        resolvedCompleted: true,
        source: .statusEndpoint,
        mismatches: [
          .loginResponse(loginCompleted: false, statusCompleted: true),
        ]
      )
    )
  }

  func testStoredCredentialRestoreFetchesAfterSignedInPublication() async throws {
    let credentials = makeCredentials(memberID: 12, completed: true)
    let fixture = makeFixture(
      outcomes: [.status(true)],
      storedCredentials: credentials
    )
    fixture.coordinator.start()

    fixture.accountSessionStore.restore()
    try await waitUntil { fixture.coordinator.latestResolution != nil }

    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    let identities = await fixture.service.identities
    XCTAssertEqual(identities, [identity])
    XCTAssertEqual(fixture.coordinator.latestResolution?.identity, identity)
    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, true)
  }

  func testAccountSwitchDoesNotPublishDelayedPreviousAccountResponse() async throws {
    let fixture = makeFixture(outcomes: [.suspended, .status(false)])
    fixture.coordinator.start()
    try fixture.establishSession(memberID: 21, completed: true)
    try await waitUntil { await fixture.service.requestCount == 1 }
    let firstIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )

    try fixture.establishSession(memberID: 22, completed: false)
    try await waitUntil { fixture.coordinator.latestResolution != nil }
    let secondIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    XCTAssertNotEqual(firstIdentity, secondIdentity)
    XCTAssertEqual(fixture.coordinator.latestResolution?.identity, secondIdentity)
    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, false)

    await fixture.service.resume(request: 0, completed: true)
    await drainMainActor()

    XCTAssertEqual(fixture.coordinator.latestResolution?.identity, secondIdentity)
    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, false)
    XCTAssertFalse(
      fixture.reporter.diagnostics.contains {
        if case .mismatch(let identity, _) = $0 {
          return identity == firstIdentity
        }
        return false
      }
    )
  }

  func testSameMemberReloginUsesSessionIDAndRejectsFirstResponse() async throws {
    let fixture = makeFixture(outcomes: [.suspended, .status(false)])
    fixture.coordinator.start()
    try fixture.establishSession(memberID: 31, completed: false)
    try await waitUntil { await fixture.service.requestCount == 1 }
    let firstIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )

    try fixture.establishSession(memberID: 31, completed: true)
    try await waitUntil { fixture.coordinator.latestResolution != nil }
    let secondIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    XCTAssertEqual(firstIdentity.memberID, secondIdentity.memberID)
    XCTAssertNotEqual(firstIdentity.sessionID, secondIdentity.sessionID)
    XCTAssertEqual(fixture.coordinator.latestResolution?.identity, secondIdentity)
    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, false)

    await fixture.service.resume(request: 0, completed: true)
    await drainMainActor()

    XCTAssertEqual(fixture.coordinator.latestResolution?.identity, secondIdentity)
    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, false)
  }

  func testCancellationTimeoutAndOfflineUseLoginFallbackWithoutChangingLocalState()
    async throws {
    let cases: [(RuntimeStatusServiceStub.Outcome, OnboardingStatusFallbackReason)] = [
      (.cancellation, .cancelled),
      (.timeout, .timeout),
      (.offline, .offline),
    ]

    for (outcome, expectedReason) in cases {
      let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
      let profileRepository = SwiftDataLocalProfileRepository(
        modelContext: container.mainContext
      )
      let profile = LocalProfile(
        displayName: "fallback 보존 프로필",
        selectedVoice: .kore
      )
      try profileRepository.saveProfile(profile)
      let sessionStore = SessionStore(localProfileRepository: profileRepository)
      sessionStore.load()
      let fixture = makeFixture(
        outcomes: [outcome],
        localCompletionProvider: { sessionStore.phase == .ready }
      )
      fixture.coordinator.start()
      try fixture.establishSession(memberID: 41, completed: true)
      try await waitUntil { fixture.coordinator.latestResolution != nil }
      let identity = try XCTUnwrap(
        fixture.accountSessionStore.currentAccountSessionIdentity
      )

      XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, true)
      XCTAssertEqual(
        fixture.coordinator.latestResolution?.source,
        .loginFallback(expectedReason)
      )
      XCTAssertEqual(
        fixture.reporter.diagnostics,
        [.fallback(identity: identity, reason: expectedReason)]
      )
      XCTAssertEqual(sessionStore.phase, .ready)
      XCTAssertEqual(sessionStore.profile, profile)
      XCTAssertEqual(try profileRepository.fetchProfile(), profile)
    }
  }

  func testStatusWinsOverLoginHintAndReportsMismatch() async throws {
    let fixture = makeFixture(outcomes: [.status(false)])
    fixture.coordinator.start()
    try fixture.establishSession(memberID: 51, completed: true)
    try await waitUntil { fixture.coordinator.latestResolution != nil }
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )

    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, false)
    XCTAssertEqual(fixture.coordinator.latestResolution?.source, .statusEndpoint)
    XCTAssertEqual(
      fixture.coordinator.latestResolution?.mismatches,
      [.loginResponse(loginCompleted: true, statusCompleted: false)]
    )
    XCTAssertEqual(
      fixture.reporter.diagnostics,
      [
        .mismatch(
          identity: identity,
          mismatch: .loginResponse(
            loginCompleted: true,
            statusCompleted: false
          )
        ),
      ]
    )
  }

  func testOfflineFallbackNamesLocalDifferenceAsLoginHintMismatch() async throws {
    let fixture = makeFixture(
      outcomes: [.offline],
      localCompleted: true
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: 52, completed: false)
    try await waitUntil { fixture.coordinator.latestResolution != nil }
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    let mismatch = OnboardingStatusMismatch.localFallbackHint(
      localCompleted: true,
      loginCompleted: false
    )

    XCTAssertEqual(
      fixture.coordinator.latestResolution?.source,
      .loginFallback(.offline)
    )
    XCTAssertEqual(fixture.coordinator.latestResolution?.mismatches, [mismatch])
    XCTAssertEqual(
      fixture.reporter.diagnostics,
      [
        .fallback(identity: identity, reason: .offline),
        .mismatch(identity: identity, mismatch: mismatch),
      ]
    )
  }

  func testUnavailableLocalStateSkipsLocalMismatchComparison() async throws {
    let fixture = makeFixture(
      outcomes: [.status(true)],
      localCompletionProvider: { nil }
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: 53, completed: true)
    try await waitUntil { fixture.coordinator.latestResolution != nil }

    XCTAssertEqual(fixture.coordinator.latestResolution?.resolvedCompleted, true)
    XCTAssertEqual(fixture.coordinator.latestResolution?.mismatches, [])
    XCTAssertEqual(fixture.reporter.diagnostics, [])
  }

  func testLocalAndServerMismatchesAreReportedInBothDirections() async throws {
    let cases = [
      (local: true, server: false),
      (local: false, server: true),
    ]

    for testCase in cases {
      let fixture = makeFixture(
        outcomes: [.status(testCase.server)],
        localCompleted: testCase.local
      )
      fixture.coordinator.start()
      try fixture.establishSession(
        memberID: 61,
        completed: testCase.server
      )
      try await waitUntil { fixture.coordinator.latestResolution != nil }
      let identity = try XCTUnwrap(
        fixture.accountSessionStore.currentAccountSessionIdentity
      )
      let mismatch = OnboardingStatusMismatch.localState(
        localCompleted: testCase.local,
        serverCompleted: testCase.server
      )

      XCTAssertEqual(fixture.coordinator.latestResolution?.mismatches, [mismatch])
      XCTAssertEqual(
        fixture.reporter.diagnostics,
        [.mismatch(identity: identity, mismatch: mismatch)]
      )
    }
  }

  func testServerFalseDoesNotChangeSwiftDataProfileRoutineOrSessionPhase()
    async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let profileRepository = SwiftDataLocalProfileRepository(
      modelContext: container.mainContext
    )
    let routineRepository = SwiftDataRoutineRepository(
      modelContext: container.mainContext
    )
    let profile = LocalProfile(displayName: "보존할 프로필", selectedVoice: .charon)
    let routine = Routine(name: "보존할 루틴", steps: [], isActive: true)
    try profileRepository.saveProfile(profile)
    try routineRepository.saveRoutine(routine)
    let sessionStore = SessionStore(localProfileRepository: profileRepository)
    sessionStore.load()
    let fixture = makeFixture(
      outcomes: [.status(false)],
      localCompletionProvider: { sessionStore.phase == .ready }
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: 71, completed: false)

    try await waitUntil { fixture.coordinator.latestResolution != nil }

    XCTAssertEqual(sessionStore.phase, .ready)
    XCTAssertEqual(sessionStore.profile, profile)
    XCTAssertEqual(try profileRepository.fetchProfile(), profile)
    XCTAssertEqual(try routineRepository.fetchRoutines(), [routine])
    XCTAssertEqual(
      fixture.coordinator.latestResolution?.mismatches,
      [.localState(localCompleted: true, serverCompleted: false)]
    )
  }

  private func makeFixture(
    outcomes: [RuntimeStatusServiceStub.Outcome],
    storedCredentials: AccountCredentials? = nil,
    localCompleted: Bool = false
  ) -> RuntimeStatusFixture {
    return makeFixture(
      outcomes: outcomes,
      storedCredentials: storedCredentials,
      localCompletionProvider: { localCompleted }
    )
  }

  private func makeFixture(
    outcomes: [RuntimeStatusServiceStub.Outcome],
    storedCredentials: AccountCredentials? = nil,
    localCompletionProvider: @escaping @MainActor () -> Bool?
  ) -> RuntimeStatusFixture {
    let credentialStore = RuntimeCredentialStore(credentials: storedCredentials)
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let service = RuntimeStatusServiceStub(outcomes: outcomes)
    let reporter = RuntimeStatusReporterSpy()
    let coordinator = OnboardingStatusRuntimeCoordinator(
      remoteService: service,
      accountSessionStore: accountSessionStore,
      localCompletionProvider: localCompletionProvider,
      reporter: reporter
    )
    return RuntimeStatusFixture(
      service: service,
      reporter: reporter,
      accountSessionStore: accountSessionStore,
      coordinator: coordinator
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !(await condition()) {
      guard clock.now < deadline else {
        return XCTFail("Timed out waiting for onboarding status runtime state.")
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private func drainMainActor() async {
    for _ in 0..<10 {
      await Task.yield()
    }
  }
}

@MainActor
private struct RuntimeStatusFixture {
  let service: RuntimeStatusServiceStub
  let reporter: RuntimeStatusReporterSpy
  let accountSessionStore: AccountSessionStore
  let coordinator: OnboardingStatusRuntimeCoordinator

  func establishSession(
    memberID: Int64,
    completed: Bool
  ) throws {
    try accountSessionStore.establishSession(
      credentials: makeCredentials(
        memberID: memberID,
        completed: completed
      )
    )
  }
}

nonisolated private func makeCredentials(
  memberID: Int64,
  completed: Bool
) -> AccountCredentials {
  AccountCredentials(
    memberID: memberID,
    accessToken: "access-\(memberID)-\(UUID().uuidString)",
    refreshToken: "refresh-\(memberID)",
    onboardingCompleted: completed
  )
}

private actor RuntimeStatusServiceStub: OnboardingStatusRemoteServing {
  enum Outcome: Sendable {
    case status(Bool)
    case suspended
    case cancellation
    case timeout
    case offline
  }

  private var outcomes: [Outcome]
  private var storedIdentities: [AccountSessionIdentity] = []
  private var continuations: [Int: CheckedContinuation<ServerOnboardingStatus, Error>] = [:]

  init(outcomes: [Outcome]) {
    self.outcomes = outcomes
  }

  var requestCount: Int {
    storedIdentities.count
  }

  var identities: [AccountSessionIdentity] {
    storedIdentities
  }

  func fetchStatus(
    for identity: AccountSessionIdentity
  ) async throws -> ServerOnboardingStatus {
    let request = storedIdentities.count
    storedIdentities.append(identity)
    let outcome = outcomes.removeFirst()

    switch outcome {
    case .status(let completed):
      return ServerOnboardingStatus(isCompleted: completed)
    case .suspended:
      return try await withCheckedThrowingContinuation { continuation in
        continuations[request] = continuation
      }
    case .cancellation:
      throw CancellationError()
    case .timeout:
      throw APIError.transport(
        code: URLError.timedOut.rawValue,
        message: "timeout"
      )
    case .offline:
      throw APIError.transport(
        code: URLError.notConnectedToInternet.rawValue,
        message: "offline"
      )
    }
  }

  func resume(request: Int, completed: Bool) {
    continuations.removeValue(forKey: request)?.resume(
      returning: ServerOnboardingStatus(isCompleted: completed)
    )
  }
}

nonisolated private final class RuntimeStatusReporterSpy:
  OnboardingStatusReporting,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedDiagnostics: [OnboardingStatusDiagnostic] = []

  var diagnostics: [OnboardingStatusDiagnostic] {
    lock.lock()
    defer { lock.unlock() }
    return storedDiagnostics
  }

  func report(_ diagnostic: OnboardingStatusDiagnostic) {
    lock.lock()
    storedDiagnostics.append(diagnostic)
    lock.unlock()
  }
}

nonisolated private final class RuntimeCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCredentials: AccountCredentials?

  init(credentials: AccountCredentials?) {
    storedCredentials = credentials
  }

  func load() throws -> AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
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
