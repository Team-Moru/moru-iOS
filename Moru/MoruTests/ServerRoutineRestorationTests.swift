//
//  ServerRoutineRestorationTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest

@testable import Moru

@MainActor
final class ServerRoutineRestorationTests: XCTestCase {
  func testStoredSessionRestoresEmptyLocalStoreAndRoutesHome()
    async throws {
    let memberID: Int64 = 101
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()],
      suspendedDetailIDs: [501]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote,
      storedCredentials: credentials(memberID: memberID, completed: true)
    )
    fixture.coordinator.start()

    fixture.accountSessionStore.restore()
    try await waitUntil {
      await remote.detailRequests.count == 1
    }

    XCTAssertEqual(fixture.sessionStore.phase, .loading)
    XCTAssertEqual(
      destination(for: fixture),
      .splash(showStartCTA: false)
    )
    XCTAssertNil(try fixture.profileRepository.fetchProfile())
    XCTAssertEqual(try fixture.routineRepository.fetchRoutines(), [])

    await remote.resumeDetail(routineGroupID: 501)
    try await waitUntil {
      if case .restored(_, routineCount: 1) =
        fixture.coordinator.restorationState {
        return true
      }
      return false
    }

    let profile = try XCTUnwrap(
      fixture.profileRepository.fetchProfile()
    )
    let routine = try XCTUnwrap(
      fixture.routineRepository.fetchRoutines().first
    )
    XCTAssertEqual(profile.displayName, "모루 사용자")
    XCTAssertEqual(profile.selectedVoice, .aoede)
    XCTAssertEqual(routine.name, "서버 아침 루틴")
    XCTAssertEqual(routine.summary, "서버에서 만든 루틴")
    XCTAssertEqual(routine.goalTags, [])
    XCTAssertTrue(routine.isActive)
    XCTAssertEqual(routine.steps.map(\.title), [
      "물 마시기",
      "호흡하기",
      "오늘의 다짐",
    ])
    XCTAssertEqual(routine.steps.map(\.type), [.confirm, .timer, .input])
    XCTAssertEqual(routine.steps.map(\.order), [0, 1, 2])
    XCTAssertEqual(routine.steps.map(\.estimatedSeconds), [nil, 90, nil])
    XCTAssertTrue(routine.steps.allSatisfy { $0.instruction.isEmpty })
    XCTAssertTrue(routine.steps.allSatisfy { $0.presetItemID == nil })
    XCTAssertTrue(routine.steps.allSatisfy(\.isRequired))

    let alarm = try XCTUnwrap(routine.alarmSchedule)
    XCTAssertEqual(alarm.hour, 6)
    XCTAssertEqual(alarm.minute, 45)
    XCTAssertEqual(alarm.weekdays, Weekday.displayOrder)
    XCTAssertEqual(alarm.soundName, "moru-default")
    XCTAssertTrue(alarm.isEnabled)
    XCTAssertTrue(alarm.includeWeather)
    XCTAssertFalse(alarm.includeFortune)

    let groupBinding = try XCTUnwrap(
      fixture.syncRepository.binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: routine.id
      )
    )
    XCTAssertEqual(groupBinding.remoteID, 501)
    XCTAssertNil(groupBinding.parentEntityKind)
    for (step, remoteID) in zip(routine.steps, [601, 602, 603]) {
      let binding = try XCTUnwrap(
        fixture.syncRepository.binding(
          memberID: memberID,
          entityKind: .routine,
          localEntityID: step.id
        )
      )
      XCTAssertEqual(binding.remoteID, Int64(remoteID))
      XCTAssertEqual(binding.parentEntityKind, .routineGroup)
      XCTAssertEqual(binding.parentLocalEntityID, routine.id)
    }
    XCTAssertEqual(
      try fixture.container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).count,
      4,
      "Nested server step IDs have no local entity kind and must not be bound."
    )
    XCTAssertEqual(
      try fixture.syncRepository.mutations(memberID: memberID),
      []
    )

    XCTAssertEqual(fixture.sessionStore.phase, .ready)
    XCTAssertEqual(destination(for: fixture), .main)

    let homeViewModel = HomeViewModel(
      loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
        routineRepository: fixture.routineRepository,
        routineRunRepository: SwiftDataRoutineRunRepository(
          modelContext: fixture.container.mainContext
        ),
        localProfileRepository: fixture.profileRepository
      )
    )
    homeViewModel.load()
    XCTAssertEqual(homeViewModel.state.loadState, .content)
    XCTAssertEqual(homeViewModel.state.todayRoutine?.id, routine.id)
    XCTAssertEqual(homeViewModel.state.todayRoutine?.title, routine.name)
  }

  func testIncompleteServerOnboardingKeepsExistingOnboardingFlow()
    async throws {
    let memberID: Int64 = 102
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(false)],
      remote: remote
    )
    fixture.coordinator.start()

    try fixture.establishSession(memberID: memberID, completed: true)
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    try await waitUntil {
      fixture.coordinator.restorationState
        == .onboardingRequired(identity)
    }

    XCTAssertNil(try fixture.profileRepository.fetchProfile())
    XCTAssertEqual(try fixture.routineRepository.fetchRoutines(), [])
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
    XCTAssertEqual(fixture.sessionStore.phase, .onboardingRequired)
    XCTAssertEqual(
      destination(for: fixture, didStartOnboarding: true),
      .onboarding
    )
  }

  func testExistingLocalDataIsNeverFetchedOverOrOverwritten()
    async throws {
    let memberID: Int64 = 103
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let localProfile = LocalProfile(
      displayName: "보존할 사용자",
      selectedVoice: .kore
    )
    let localRoutine = Routine(
      name: "보존할 로컬 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "로컬 단계", order: 0),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 8,
        minute: 10,
        weekdays: [.monday]
      )
    )
    try fixture.profileRepository.saveProfile(localProfile)
    try fixture.routineRepository.saveRoutine(localRoutine)
    fixture.sessionStore.load()
    fixture.coordinator.start()

    try fixture.establishSession(memberID: memberID, completed: true)
    try await waitUntil {
      fixture.coordinator.latestResolution != nil
    }

    XCTAssertEqual(
      try fixture.profileRepository.fetchProfile(),
      localProfile
    )
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines(),
      [localRoutine]
    )
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
    XCTAssertEqual(fixture.sessionStore.phase, .ready)
    XCTAssertEqual(destination(for: fixture), .main)
  }

  func testSameAccountReloginDoesNotDuplicateRoutineOrBackfillUpload()
    async throws {
    let memberID: Int64 = 104
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    try await waitUntil {
      if case .restored = fixture.coordinator.restorationState {
        return true
      }
      return false
    }

    let firstRoutineIDs = try fixture.routineRepository.fetchRoutines()
      .map(\.id)
    let backfiller = RoutineSyncLoginBackfiller(
      routineRepository: fixture.routineRepository,
      syncRepository: fixture.syncRepository
    )
    try backfiller.backfillLocalRoutineGroups(memberID: memberID)
    XCTAssertEqual(
      try fixture.syncRepository.mutations(memberID: memberID),
      []
    )

    let firstIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    try fixture.establishSession(memberID: memberID, completed: true)
    let secondIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    XCTAssertNotEqual(firstIdentity.sessionID, secondIdentity.sessionID)
    try await waitUntil {
      let hasLocalDataState = fixture.coordinator.restorationState
        == .localDataPresent(secondIdentity)
      let requestCount = await fixture.statusService.requestIdentities.count
      return hasLocalDataState && requestCount == 2
    }

    try backfiller.backfillLocalRoutineGroups(memberID: memberID)
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().map(\.id),
      firstRoutineIDs
    )
    XCTAssertEqual(
      try fixture.syncRepository.mutations(memberID: memberID),
      []
    )
    let remoteCalls = await remote.calls
    XCTAssertEqual(
      remoteCalls.filter {
        if case .list = $0 { return true }
        return false
      }.count,
      1
    )
  }

  func testAccountSwitchDiscardsLatePreviousAccountResponse()
    async throws {
    let firstMemberID: Int64 = 105
    let secondMemberID: Int64 = 106
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [firstMemberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()],
      suspendedDetailIDs: [501]
    )
    let fixture = try makeFixture(
      statusOutcomes: [
        firstMemberID: .completed(true),
        secondMemberID: .completed(false),
      ],
      remote: remote
    )
    fixture.coordinator.start()

    try fixture.establishSession(
      memberID: firstMemberID,
      completed: true
    )
    try await waitUntil {
      await remote.detailRequests.count == 1
    }
    let firstIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    XCTAssertEqual(fixture.sessionStore.phase, .loading)

    try fixture.establishSession(
      memberID: secondMemberID,
      completed: false
    )
    let secondIdentity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    XCTAssertNotEqual(firstIdentity, secondIdentity)
    try await waitUntil {
      fixture.coordinator.restorationState
        == .onboardingRequired(secondIdentity)
    }

    await remote.resumeDetail(routineGroupID: 501)
    await drainMainActor()

    XCTAssertNil(try fixture.profileRepository.fetchProfile())
    XCTAssertEqual(try fixture.routineRepository.fetchRoutines(), [])
    XCTAssertTrue(
      try fixture.container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).isEmpty
    )
    XCTAssertEqual(
      fixture.coordinator.latestResolution?.identity,
      secondIdentity
    )
    XCTAssertEqual(
      fixture.coordinator.restorationState,
      .onboardingRequired(secondIdentity)
    )
    XCTAssertEqual(fixture.sessionStore.phase, .onboardingRequired)
  }

  func testStatusNetworkFailureDoesNotCreateAnyLocalData()
    async throws {
    let memberID: Int64 = 107
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .offline],
      remote: remote
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )

    try await waitUntil {
      fixture.coordinator.restorationState == .failed(identity)
    }

    XCTAssertNil(try fixture.profileRepository.fetchProfile())
    XCTAssertEqual(try fixture.routineRepository.fetchRoutines(), [])
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
    XCTAssertEqual(fixture.sessionStore.phase, .onboardingRequired)
  }

  private func makeFixture(
    statusOutcomes: [Int64: RestorationStatusServiceStub.Outcome],
    remote: RestorationRoutineGroupRemoteStub,
    storedCredentials: AccountCredentials? = nil
  ) throws -> RestorationFixture {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let profileRepository = SwiftDataLocalProfileRepository(
      modelContext: container.mainContext
    )
    let syncRepository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    let routineRepository = SwiftDataRoutineRepository(
      modelContext: container.mainContext
    )
    let accountSessionStore = AccountSessionStore(
      credentialStore: RestorationCredentialStore(
        credentials: storedCredentials
      ),
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let sessionStore = SessionStore(
      localProfileRepository: profileRepository
    )
    sessionStore.load()
    let statusService = RestorationStatusServiceStub(
      outcomesByMemberID: statusOutcomes
    )
    let restorer = DefaultServerRoutineRestorationService(
      remoteService: remote,
      persistence: SwiftDataServerRoutineRestorationRepository(
        modelContext: container.mainContext,
        syncRepository: syncRepository
      ),
      sessionIdentityProvider: accountSessionStore,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let coordinator = OnboardingStatusRuntimeCoordinator(
      remoteService: statusService,
      accountSessionStore: accountSessionStore,
      localCompletionProvider: {
        switch sessionStore.phase {
        case .ready:
          true
        case .onboardingRequired:
          false
        case .loading, .failed:
          nil
        }
      },
      routineRestorer: restorer,
      onRestorationBegan: {
        sessionStore.beginServerRoutineRestoration()
      },
      onRestorationFinished: {
        sessionStore.finishServerRoutineRestoration()
      }
    )

    return RestorationFixture(
      container: container,
      profileRepository: profileRepository,
      routineRepository: routineRepository,
      syncRepository: syncRepository,
      accountSessionStore: accountSessionStore,
      sessionStore: sessionStore,
      statusService: statusService,
      coordinator: coordinator
    )
  }

  private func destination(
    for fixture: RestorationFixture,
    didStartOnboarding: Bool = false
  ) -> AppRootDestination {
    AppRouter.rootDestination(
      sessionPhase: fixture.sessionStore.phase,
      hasLocalProfile: fixture.sessionStore.profile != nil,
      accountState: fixture.accountSessionStore.state,
      accountFeaturesEnabled: true,
      didStartOnboarding: didStartOnboarding,
      didCompleteOnboardingTrial: false,
      didCompleteAccountEntry: false
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
        return XCTFail("Timed out waiting for server routine restoration.")
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private func drainMainActor() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }
}

@MainActor
private struct RestorationFixture {
  let container: ModelContainer
  let profileRepository: SwiftDataLocalProfileRepository
  let routineRepository: SwiftDataRoutineRepository
  let syncRepository: SwiftDataRoutineSyncRepository
  let accountSessionStore: AccountSessionStore
  let sessionStore: SessionStore
  let statusService: RestorationStatusServiceStub
  let coordinator: OnboardingStatusRuntimeCoordinator

  func establishSession(
    memberID: Int64,
    completed: Bool
  ) throws {
    try accountSessionStore.establishSession(
      credentials: credentials(
        memberID: memberID,
        completed: completed
      )
    )
  }
}

private actor RestorationStatusServiceStub: OnboardingStatusRemoteServing {
  enum Outcome: Sendable {
    case completed(Bool)
    case offline
  }

  private let outcomesByMemberID: [Int64: Outcome]
  private(set) var requestIdentities: [AccountSessionIdentity] = []

  init(outcomesByMemberID: [Int64: Outcome]) {
    self.outcomesByMemberID = outcomesByMemberID
  }

  func fetchStatus(
    for identity: AccountSessionIdentity
  ) async throws -> ServerOnboardingStatus {
    requestIdentities.append(identity)
    switch outcomesByMemberID[identity.memberID] ?? .offline {
    case .completed(let completed):
      return ServerOnboardingStatus(isCompleted: completed)
    case .offline:
      throw URLError(.notConnectedToInternet)
    }
  }
}

private actor RestorationRoutineGroupRemoteStub:
  AccountRoutineGroupRemoteServing {
  enum Call: Equatable, Sendable {
    case list(memberID: Int64)
    case detail(routineGroupID: Int64, memberID: Int64)
  }

  private let summariesByMemberID: [Int64: [ServerRoutineGroupSummary]]
  private let detailsByGroupID: [Int64: ServerRoutineGroupDetail]
  private var suspendedDetailIDs: Set<Int64>
  private var continuations: [
    Int64: CheckedContinuation<ServerRoutineGroupDetail, Error>
  ] = [:]
  private(set) var calls: [Call] = []

  var detailRequests: [Call] {
    calls.filter {
      if case .detail = $0 { return true }
      return false
    }
  }

  init(
    summariesByMemberID: [Int64: [ServerRoutineGroupSummary]],
    detailsByGroupID: [Int64: ServerRoutineGroupDetail],
    suspendedDetailIDs: Set<Int64> = []
  ) {
    self.summariesByMemberID = summariesByMemberID
    self.detailsByGroupID = detailsByGroupID
    self.suspendedDetailIDs = suspendedDetailIDs
  }

  func fetchRoutineGroups(
    memberID: Int64
  ) async throws -> [ServerRoutineGroupSummary] {
    calls.append(.list(memberID: memberID))
    return summariesByMemberID[memberID] ?? []
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    calls.append(
      .detail(routineGroupID: routineGroupID, memberID: memberID)
    )
    guard let detail = detailsByGroupID[routineGroupID] else {
      throw AccountRoutineGroupRemoteError.invalidResponse
    }
    guard suspendedDetailIDs.contains(routineGroupID) else {
      return detail
    }
    return try await withCheckedThrowingContinuation { continuation in
      continuations[routineGroupID] = continuation
    }
  }

  func resumeDetail(routineGroupID: Int64) {
    suspendedDetailIDs.remove(routineGroupID)
    guard let detail = detailsByGroupID[routineGroupID] else {
      continuations.removeValue(forKey: routineGroupID)?.resume(
        throwing: AccountRoutineGroupRemoteError.invalidResponse
      )
      return
    }
    continuations.removeValue(forKey: routineGroupID)?.resume(
      returning: detail
    )
  }

  func fetchActiveRoutineGroup(
    identity: AccountSessionIdentity
  ) async throws -> ServerActiveRoutineGroup? {
    nil
  }

  func fetchTodayRoutineGroupSummary(
    identity: AccountSessionIdentity
  ) async throws -> ServerTodayRoutineGroupSummary? {
    nil
  }
}

nonisolated private final class RestorationCredentialStore:
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

nonisolated private func credentials(
  memberID: Int64,
  completed: Bool
) -> AccountCredentials {
  AccountCredentials(
    memberID: memberID,
    accessToken: "access-\(memberID)-\(UUID().uuidString)",
    refreshToken: "refresh-\(memberID)",
    onboardingCompleted: completed,
    provider: .google
  )
}

nonisolated private func serverGroupSummary()
  -> ServerRoutineGroupSummary {
  ServerRoutineGroupSummary(
    routineGroupID: 501,
    title: "서버 목록 제목",
    isActive: true,
    routineCount: 3,
    totalDurationSeconds: 90
  )
}

nonisolated private func serverGroupDetail()
  -> ServerRoutineGroupDetail {
  ServerRoutineGroupDetail(
    routineGroupID: 501,
    title: "서버 아침 루틴",
    description: "서버에서 만든 루틴",
    alarmDaysRaw: "MON,TUE,WED,THU,FRI,SAT,SUN",
    alarmTimeRaw: "06:45",
    weatherNotificationEnabled: true,
    routines: [
      ServerRoutineItem(
        routineID: 601,
        title: "물 마시기",
        type: .check,
        durationSeconds: 0,
        steps: [
          ServerRoutineNestedStep(
            stepID: 701,
            content: "서버 중첩 내용은 합성하지 않음",
            orderIndex: 0
          ),
        ]
      ),
      ServerRoutineItem(
        routineID: 602,
        title: "호흡하기",
        type: .timer,
        durationSeconds: 90,
        steps: []
      ),
      ServerRoutineItem(
        routineID: 603,
        title: "오늘의 다짐",
        type: .input,
        durationSeconds: nil,
        steps: nil
      ),
    ]
  )
}
