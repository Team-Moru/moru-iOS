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
  func testActualOnboardingAccountEntryLoginReplacesProvisionalData()
    async throws {
    let memberID: Int64 = 100
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()],
      suspendedDetailIDs: [501]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    fixture.sessionStore.load()

    let marker = try XCTUnwrap(fixture.provisionalStore.marker())
    XCTAssertEqual(marker.profileID, onboardingResult.profile.id)
    XCTAssertEqual(marker.routineIDs, [onboardingResult.routine.id])
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .provisional(marker)
    )
    XCTAssertEqual(
      destination(
        for: fixture,
        didCompleteOnboardingTrial: true
      ),
      .accountEntry(nil)
    )

    let syncSender = RestorationRoutineSyncSenderStub()
    let syncRuntime = RoutineSyncRuntimeCoordinator(
      sender: syncSender,
      sessionIdentityProvider: fixture.accountSessionStore,
      loginBackfiller: RoutineSyncLoginBackfiller(
        routineRepository: fixture.routineRepository,
        syncRepository: fixture.syncRepository
      ),
      isSceneActive: true,
      restorationBackfillBarrier: fixture.restorationBackfillBarrier
    )
    fixture.coordinator.start()

    try fixture.establishSession(memberID: memberID, completed: true)
    // Matches AppRouter's synchronous account-state callback ordering.
    fixture.coordinator.accountSessionDidChange()
    syncRuntime.accountSessionDidChange()
    try await waitUntil {
      await remote.detailRequests.count == 1
    }
    try await waitUntil {
      !syncRuntime.isDraining
        && syncRuntime.lastStopReason == .restorationPending
    }

    XCTAssertEqual(fixture.sessionStore.phase, .loading)
    XCTAssertEqual(
      destination(
        for: fixture,
        didCompleteOnboardingTrial: true,
        didCompleteAccountEntry: true
      ),
      .splash(showStartCTA: false)
    )
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().map(\.id),
      [onboardingResult.routine.id]
    )
    XCTAssertNotNil(try fixture.provisionalStore.marker())
    XCTAssertTrue(
      try fixture.syncRepository.mutations(memberID: memberID).isEmpty
    )
    XCTAssertEqual(syncSender.callCount, 0)

    await remote.resumeDetail(routineGroupID: 501)
    try await waitUntil {
      if case .restored(_, routineCount: 1) =
        fixture.coordinator.restorationState {
        return true
      }
      return false
    }
    try await waitUntil {
      !syncRuntime.isDraining && syncRuntime.lastStopReason == .idle
    }

    let restoredRoutine = try XCTUnwrap(
      fixture.routineRepository.fetchRoutines().first
    )
    XCTAssertNotEqual(restoredRoutine.id, onboardingResult.routine.id)
    XCTAssertEqual(restoredRoutine.name, "서버 아침 루틴")
    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .established
    )
    XCTAssertNotNil(
      try fixture.syncRepository.binding(
        memberID: memberID,
        entityKind: .routineGroup,
        localEntityID: restoredRoutine.id
      )
    )
    XCTAssertTrue(
      try fixture.syncRepository.mutations(memberID: memberID).isEmpty
    )
    XCTAssertEqual(syncSender.callCount, 1)
    XCTAssertEqual(fixture.sessionStore.phase, .ready)
    XCTAssertEqual(
      destination(
        for: fixture,
        didCompleteOnboardingTrial: true,
        didCompleteAccountEntry: true
      ),
      .main
    )

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
    XCTAssertEqual(homeViewModel.state.todayRoutine?.id, restoredRoutine.id)
  }

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

  func testMakeSnapshotOverridesConflictingActiveFlagsUsingAuthoritativeID()
    throws {
    let summaries = [
      ServerRoutineGroupSummary(
        routineGroupID: 501,
        title: "루틴 A",
        isActive: true,
        routineCount: 3,
        totalDurationSeconds: 90
      ),
      ServerRoutineGroupSummary(
        routineGroupID: 502,
        title: "루틴 B",
        isActive: true,
        routineCount: 3,
        totalDurationSeconds: 90
      ),
    ]
    let details = [
      serverGroupDetail(),
      secondServerGroupDetail(),
    ]

    let snapshot = try ServerRoutineRestorationMapper.makeSnapshot(
      summaries: summaries,
      details: details,
      activeGroupResolution: .override(502),
      at: Date(timeIntervalSince1970: 0)
    )

    let activeRoutines = snapshot.routines.filter(\.isActive)
    XCTAssertEqual(activeRoutines.count, 1)
    XCTAssertEqual(activeRoutines.first?.name, "서버 저녁 루틴")
  }

  func testMakeSnapshotDeactivatesAllGroupsWhenNoAuthoritativeActiveGroupExists()
    throws {
    let summaries = [
      ServerRoutineGroupSummary(
        routineGroupID: 501,
        title: "루틴 A",
        isActive: true,
        routineCount: 3,
        totalDurationSeconds: 90
      ),
      ServerRoutineGroupSummary(
        routineGroupID: 502,
        title: "루틴 B",
        isActive: true,
        routineCount: 3,
        totalDurationSeconds: 90
      ),
    ]
    let details = [
      serverGroupDetail(),
      secondServerGroupDetail(),
    ]

    let snapshot = try ServerRoutineRestorationMapper.makeSnapshot(
      summaries: summaries,
      details: details,
      activeGroupResolution: .override(nil),
      at: Date(timeIntervalSince1970: 0)
    )

    XCTAssertEqual(snapshot.routines.count, 2)
    XCTAssertTrue(snapshot.routines.allSatisfy { !$0.isActive })
  }

  func testMultipleActiveGroupsResolveViaFetchActiveRoutineGroupEndpoint()
    async throws {
    let memberID: Int64 = 103
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [
        memberID: [
          ServerRoutineGroupSummary(
            routineGroupID: 501,
            title: "루틴 A",
            isActive: true,
            routineCount: 3,
            totalDurationSeconds: 90
          ),
          ServerRoutineGroupSummary(
            routineGroupID: 502,
            title: "루틴 B",
            isActive: true,
            routineCount: 3,
            totalDurationSeconds: 90
          ),
        ],
      ],
      detailsByGroupID: [
        501: serverGroupDetail(),
        502: secondServerGroupDetail(),
      ],
      activeRoutineGroupByMemberID: [
        memberID: ServerActiveRoutineGroup(
          routineGroupID: 502,
          title: "루틴 B",
          totalDurationSeconds: 90,
          completionRate: 0,
          routines: []
        ),
      ]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote,
      storedCredentials: credentials(memberID: memberID, completed: true)
    )
    fixture.coordinator.start()
    fixture.accountSessionStore.restore()

    try await waitUntil {
      if case .restored(_, routineCount: 2) =
        fixture.coordinator.restorationState {
        return true
      }
      return false
    }

    let routines = try fixture.routineRepository.fetchRoutines()
    XCTAssertEqual(routines.count, 2)
    XCTAssertEqual(
      routines.filter(\.isActive).map(\.name),
      ["서버 저녁 루틴"]
    )
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

  func testIncompleteServerOnboardingKeepsProvisionalDataAndReleasesBackfill()
    async throws {
    let memberID: Int64 = 108
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(false)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    fixture.sessionStore.load()
    XCTAssertNotNil(try fixture.provisionalStore.marker())

    let syncSender = RestorationRoutineSyncSenderStub()
    let syncRuntime = RoutineSyncRuntimeCoordinator(
      sender: syncSender,
      sessionIdentityProvider: fixture.accountSessionStore,
      loginBackfiller: RoutineSyncLoginBackfiller(
        routineRepository: fixture.routineRepository,
        syncRepository: fixture.syncRepository
      ),
      isSceneActive: true,
      restorationBackfillBarrier: fixture.restorationBackfillBarrier
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: false)
    fixture.coordinator.accountSessionDidChange()
    syncRuntime.accountSessionDidChange()
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )

    try await waitUntil {
      fixture.coordinator.restorationState == .localDataPresent(identity)
        && !syncRuntime.isDraining
        && syncRuntime.lastStopReason == .idle
    }

    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().map(\.id),
      [onboardingResult.routine.id]
    )
    XCTAssertEqual(
      try fixture.profileRepository.fetchProfile()?.id,
      onboardingResult.profile.id
    )
    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .established
    )
    let mutations = try fixture.syncRepository.mutations(
      memberID: memberID
    )
    XCTAssertEqual(
      Set(mutations.map(\.operation)),
      [.createRoutineGroup, .setRoutineGroupActive]
    )
    XCTAssertTrue(
      fixture.restorationBackfillBarrier.allowsBackfill(for: identity)
    )
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
    XCTAssertEqual(fixture.sessionStore.phase, .ready)
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

  func testEditedProvisionalRoutineBecomesEstablishedAndIsNotReplaced()
    async throws {
    let memberID: Int64 = 109
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    var editedRoutine = onboardingResult.routine
    editedRoutine.name = "사용자가 편집한 루틴"
    editedRoutine.updatedAt = editedRoutine.updatedAt.addingTimeInterval(1)
    try fixture.routineRepository.saveRoutine(editedRoutine)
    fixture.sessionStore.load()

    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .established
    )

    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    try await waitUntil {
      fixture.coordinator.latestResolution != nil
    }

    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines(),
      [editedRoutine]
    )
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
    XCTAssertEqual(fixture.sessionStore.phase, .ready)
  }

  func testAddedAndDeletedProvisionalRoutinesBecomeEstablished()
    async throws {
    let addedMemberID: Int64 = 114
    let addedRemote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [addedMemberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let addedFixture = try makeFixture(
      statusOutcomes: [addedMemberID: .completed(true)],
      remote: addedRemote
    )
    let onboardingResult = try await completeLocalOnboarding(
      in: addedFixture
    )
    let addedRoutine = Routine(
      name: "사용자가 추가한 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "추가 단계", order: 0),
      ],
      isActive: false
    )
    try addedFixture.routineRepository.saveRoutine(addedRoutine)
    addedFixture.sessionStore.load()

    XCTAssertNil(try addedFixture.provisionalStore.marker())
    XCTAssertEqual(
      try addedFixture.provisionalStore.localDataState(),
      .established
    )

    addedFixture.coordinator.start()
    try addedFixture.establishSession(
      memberID: addedMemberID,
      completed: true
    )
    addedFixture.coordinator.accountSessionDidChange()
    try await waitUntil {
      addedFixture.coordinator.latestResolution != nil
    }

    XCTAssertEqual(
      Set(try addedFixture.routineRepository.fetchRoutines().map(\.id)),
      Set([onboardingResult.routine.id, addedRoutine.id])
    )
    let addedRemoteCalls = await addedRemote.calls
    XCTAssertEqual(addedRemoteCalls, [])

    let deletedMemberID: Int64 = 115
    let deletedRemote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [deletedMemberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let deletedFixture = try makeFixture(
      statusOutcomes: [deletedMemberID: .completed(true)],
      remote: deletedRemote
    )
    let deletedOnboardingResult = try await completeLocalOnboarding(
      in: deletedFixture
    )
    try deletedFixture.routineRepository.deleteRoutine(
      id: deletedOnboardingResult.routine.id
    )
    deletedFixture.sessionStore.load()

    XCTAssertNil(try deletedFixture.provisionalStore.marker())
    XCTAssertEqual(
      try deletedFixture.provisionalStore.localDataState(),
      .established
    )

    deletedFixture.coordinator.start()
    try deletedFixture.establishSession(
      memberID: deletedMemberID,
      completed: true
    )
    deletedFixture.coordinator.accountSessionDidChange()
    try await waitUntil {
      deletedFixture.coordinator.latestResolution != nil
    }

    XCTAssertTrue(
      try deletedFixture.routineRepository.fetchRoutines().isEmpty
    )
    XCTAssertEqual(
      try deletedFixture.profileRepository.fetchProfile(),
      deletedOnboardingResult.profile
    )
    let deletedRemoteCalls = await deletedRemote.calls
    XCTAssertEqual(deletedRemoteCalls, [])
  }

  func testEditedProvisionalProfileBecomesEstablished()
    async throws {
    let memberID: Int64 = 116
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    var editedProfile = onboardingResult.profile
    editedProfile.displayName = "사용자가 편집한 프로필"
    editedProfile.updatedAt = editedProfile.updatedAt.addingTimeInterval(1)
    try fixture.profileRepository.saveProfile(editedProfile)
    fixture.sessionStore.load()

    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .established
    )

    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    try await waitUntil {
      fixture.coordinator.latestResolution != nil
    }

    XCTAssertEqual(try fixture.profileRepository.fetchProfile(), editedProfile)
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines(),
      [onboardingResult.routine]
    )
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
  }

  func testMismatchedMarkerFailsClosedWithoutDeletingLocalData()
    async throws {
    let memberID: Int64 = 110
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    let marker = try XCTUnwrap(fixture.provisionalStore.marker())
    let persistedRoutine = try XCTUnwrap(
      fixture.container.mainContext.fetch(
        FetchDescriptor<PersistedRoutine>()
      ).first
    )
    persistedRoutine.name = "marker 밖에서 변경된 루틴"
    try fixture.container.mainContext.save()
    fixture.sessionStore.load()

    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .established
    )
    XCTAssertEqual(try fixture.provisionalStore.marker(), marker)

    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    try await waitUntil {
      fixture.coordinator.latestResolution != nil
    }

    let retainedRoutine = try XCTUnwrap(
      fixture.routineRepository.fetchRoutines().first
    )
    XCTAssertEqual(retainedRoutine.id, onboardingResult.routine.id)
    XCTAssertEqual(retainedRoutine.name, "marker 밖에서 변경된 루틴")
    XCTAssertEqual(try fixture.provisionalStore.marker(), marker)
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
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

  func testStatusNetworkFailureKeepsProvisionalDataBlocksBackfillAndRetries()
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
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    fixture.sessionStore.load()
    let marker = try XCTUnwrap(fixture.provisionalStore.marker())
    let syncSender = RestorationRoutineSyncSenderStub()
    let syncRuntime = RoutineSyncRuntimeCoordinator(
      sender: syncSender,
      sessionIdentityProvider: fixture.accountSessionStore,
      loginBackfiller: RoutineSyncLoginBackfiller(
        routineRepository: fixture.routineRepository,
        syncRepository: fixture.syncRepository
      ),
      isSceneActive: true,
      restorationBackfillBarrier: fixture.restorationBackfillBarrier
    )
    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    syncRuntime.accountSessionDidChange()
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )

    try await waitUntil {
      fixture.coordinator.restorationState == .failed(identity)
    }
    try await waitUntil {
      !syncRuntime.isDraining
        && syncRuntime.lastStopReason == .restorationPending
    }

    XCTAssertEqual(
      try fixture.profileRepository.fetchProfile()?.id,
      onboardingResult.profile.id
    )
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().map(\.id),
      [onboardingResult.routine.id]
    )
    XCTAssertEqual(try fixture.provisionalStore.marker(), marker)
    XCTAssertTrue(
      try fixture.syncRepository.mutations(memberID: memberID).isEmpty
    )
    XCTAssertTrue(
      try fixture.container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).isEmpty
    )
    XCTAssertEqual(syncSender.callCount, 0)
    XCTAssertTrue(
      fixture.restorationBackfillBarrier.isPending(for: identity)
    )
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
    guard case .failed = fixture.sessionStore.phase else {
      return XCTFail("Expected retryable restoration failure UI.")
    }

    await fixture.statusService.setOutcome(
      .completed(true),
      memberID: memberID
    )
    XCTAssertTrue(
      fixture.coordinator.retryRestorationForCurrentSession()
    )
    XCTAssertEqual(fixture.sessionStore.phase, .loading)
    try await waitUntil {
      if case .restored = fixture.coordinator.restorationState {
        return true
      }
      return false
    }
    try await waitUntil {
      !syncRuntime.isDraining && syncRuntime.lastStopReason == .idle
    }

    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().first?.name,
      "서버 아침 루틴"
    )
    XCTAssertTrue(
      try fixture.syncRepository.mutations(memberID: memberID).isEmpty
    )
    XCTAssertEqual(fixture.sessionStore.phase, .ready)
  }

  func testRoutineDetailFailureKeepsWholeProvisionalTransactionUntouched()
    async throws {
    let memberID: Int64 = 113
    let missingSummary = ServerRoutineGroupSummary(
      routineGroupID: 502,
      title: "누락된 상세",
      isActive: false,
      routineCount: 0,
      totalDurationSeconds: 0
    )
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [
        memberID: [serverGroupSummary(), missingSummary],
      ],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    fixture.sessionStore.load()
    let marker = try XCTUnwrap(fixture.provisionalStore.marker())
    fixture.coordinator.start()

    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    try await waitUntil {
      fixture.coordinator.restorationState == .failed(identity)
    }

    XCTAssertEqual(
      try fixture.profileRepository.fetchProfile()?.id,
      onboardingResult.profile.id
    )
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().map(\.id),
      [onboardingResult.routine.id]
    )
    XCTAssertEqual(try fixture.provisionalStore.marker(), marker)
    XCTAssertTrue(
      try fixture.container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineServerBinding>()
      ).isEmpty
    )
  }

  func testBindingConflictRollsBackProvisionalDeleteAndServerInsert()
    async throws {
    let memberID: Int64 = 114
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote
    )
    let onboardingResult = try await completeLocalOnboarding(in: fixture)
    fixture.sessionStore.load()
    let marker = try XCTUnwrap(fixture.provisionalStore.marker())
    let conflictingLocalID = UUID()
    _ = try fixture.syncRepository.recordRemoteID(
      501,
      revision: nil,
      memberID: memberID,
      entityKind: .routineGroup,
      localEntityID: conflictingLocalID,
      at: .distantPast
    )
    fixture.coordinator.start()

    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    let identity = try XCTUnwrap(
      fixture.accountSessionStore.currentAccountSessionIdentity
    )
    try await waitUntil {
      fixture.coordinator.restorationState == .failed(identity)
    }

    XCTAssertEqual(
      try fixture.profileRepository.fetchProfile()?.id,
      onboardingResult.profile.id
    )
    XCTAssertEqual(
      try fixture.routineRepository.fetchRoutines().map(\.id),
      [onboardingResult.routine.id]
    )
    XCTAssertEqual(try fixture.provisionalStore.marker(), marker)
    let bindings = try fixture.container.mainContext.fetch(
      FetchDescriptor<PersistedRoutineServerBinding>()
    )
    XCTAssertEqual(bindings.count, 1)
    XCTAssertEqual(bindings.first?.localEntityID, conflictingLocalID)
  }

  func testProvisionalMarkerSurvivesRelaunchAndStoredSessionRestoresServerData()
    async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("Moru.store")
    let memberID: Int64 = 111
    var provisionalRoutineID: UUID?

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let fixture = try makeFixture(
        statusOutcomes: [:],
        remote: RestorationRoutineGroupRemoteStub(
          summariesByMemberID: [:],
          detailsByGroupID: [:]
        ),
        container: container
      )
      let result = try await completeLocalOnboarding(in: fixture)
      provisionalRoutineID = result.routine.id
      XCTAssertNotNil(try fixture.provisionalStore.marker())
    }

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let remote = RestorationRoutineGroupRemoteStub(
        summariesByMemberID: [memberID: [serverGroupSummary()]],
        detailsByGroupID: [501: serverGroupDetail()]
      )
      let fixture = try makeFixture(
        statusOutcomes: [memberID: .completed(true)],
        remote: remote,
        storedCredentials: credentials(
          memberID: memberID,
          completed: true
        ),
        container: container,
        holdUIForStoredSessionRestoration: true
      )
      guard case .provisional = try fixture.provisionalStore
        .localDataState() else {
        return XCTFail("Provisional marker did not survive relaunch.")
      }
      XCTAssertEqual(fixture.sessionStore.phase, .loading)
      XCTAssertEqual(
        destination(for: fixture),
        .splash(showStartCTA: false)
      )
      fixture.coordinator.start()
      fixture.accountSessionStore.restore()
      fixture.coordinator.accountSessionDidChange()

      try await waitUntil {
        if case .restored = fixture.coordinator.restorationState {
          return true
        }
        return false
      }

      let restoredRoutine = try XCTUnwrap(
        fixture.routineRepository.fetchRoutines().first
      )
      XCTAssertNotEqual(restoredRoutine.id, provisionalRoutineID)
      XCTAssertEqual(restoredRoutine.name, "서버 아침 루틴")
      XCTAssertNil(try fixture.provisionalStore.marker())
      XCTAssertEqual(fixture.sessionStore.phase, .ready)
    }
  }

  func testV5MigrationWithoutMarkerTreatsExistingDataAsEstablished()
    async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("Moru.store")
    let memberID: Int64 = 112
    let profile = LocalProfile(displayName: "기존 설치 사용자")
    let routine = Routine(
      name: "기존 설치 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "기존 단계", order: 0),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 8,
        minute: 0,
        weekdays: [.monday]
      )
    )

    do {
      let schema = Schema(versionedSchema: MoruSchemaV5.self)
      let configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(
        for: schema,
        configurations: [configuration]
      )
      container.mainContext.insert(
        SwiftDataMapper.makePersistedProfile(from: profile)
      )
      container.mainContext.insert(
        SwiftDataMapper.makePersistedRoutine(from: routine)
      )
      try container.mainContext.save()
    }

    let migrated = try ModelContainer.moruContainer(storeURL: storeURL)
    let remote = RestorationRoutineGroupRemoteStub(
      summariesByMemberID: [memberID: [serverGroupSummary()]],
      detailsByGroupID: [501: serverGroupDetail()]
    )
    let fixture = try makeFixture(
      statusOutcomes: [memberID: .completed(true)],
      remote: remote,
      container: migrated
    )
    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .established
    )

    fixture.coordinator.start()
    try fixture.establishSession(memberID: memberID, completed: true)
    fixture.coordinator.accountSessionDidChange()
    try await waitUntil {
      fixture.coordinator.latestResolution != nil
    }

    XCTAssertEqual(try fixture.profileRepository.fetchProfile(), profile)
    XCTAssertEqual(try fixture.routineRepository.fetchRoutines(), [routine])
    let remoteCalls = await remote.calls
    XCTAssertEqual(remoteCalls, [])
  }

  func testFullLocalResetAlsoClearsProvisionalMarker() async throws {
    let fixture = try makeFixture(
      statusOutcomes: [:],
      remote: RestorationRoutineGroupRemoteStub(
        summariesByMemberID: [:],
        detailsByGroupID: [:]
      )
    )
    _ = try await completeLocalOnboarding(in: fixture)
    XCTAssertNotNil(try fixture.provisionalStore.marker())

    try SwiftDataLocalDataResetRepository(
      modelContext: fixture.container.mainContext
    ).resetToFreshInstallState()

    XCTAssertNil(try fixture.provisionalStore.marker())
    XCTAssertEqual(
      try fixture.provisionalStore.localDataState(),
      .empty
    )
  }

  private func completeLocalOnboarding(
    in fixture: RestorationFixture
  ) async throws -> CompleteOnboardingResult {
    try await CompleteOnboardingUseCase(
      onboardingRepository: fixture.onboardingRepository,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    ).execute(
      CompleteOnboardingRequest(
        suggestionInput: RoutineSuggestionInput(
          experience: .wantsRecommendation,
          goalTags: ["health"],
          selectedKeywords: ["물 마시기", "스트레칭"],
          freeformText: "온보딩에서 만든 임시 루틴",
          wakeUpHour: 7,
          wakeUpMinute: 10,
          weekdays: Weekday.displayOrder
        ),
        selectedVoice: .aoede,
        includeWeather: true,
        includeFortune: true
      )
    )
  }

  private func makeFixture(
    statusOutcomes: [Int64: RestorationStatusServiceStub.Outcome],
    remote: RestorationRoutineGroupRemoteStub,
    storedCredentials: AccountCredentials? = nil,
    container suppliedContainer: ModelContainer? = nil,
    holdUIForStoredSessionRestoration: Bool = false
  ) throws -> RestorationFixture {
    let container: ModelContainer
    if let suppliedContainer {
      container = suppliedContainer
    } else {
      container = try ModelContainer.moruContainer(
        isStoredInMemoryOnly: true
      )
    }
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
    if holdUIForStoredSessionRestoration {
      accountSessionStore.prepareForRestoration()
    }
    let onboardingRepository = SwiftDataOnboardingRepository(
      modelContext: container.mainContext,
      routineSyncRepository: syncRepository,
      signedInMemberProvider: accountSessionStore
    )
    let provisionalStore = SwiftDataProvisionalOnboardingDataStore(
      modelContext: container.mainContext
    )
    let sessionStore = SessionStore(
      localProfileRepository: profileRepository
    )
    sessionStore.load()
    if holdUIForStoredSessionRestoration {
      sessionStore.beginServerRoutineRestoration()
    }
    let statusService = RestorationStatusServiceStub(
      outcomesByMemberID: statusOutcomes
    )
    let restorationBackfillBarrier = RoutineRestorationBackfillBarrier()
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
      restorationBackfillBarrier: restorationBackfillBarrier,
      onRestorationBegan: {
        sessionStore.beginServerRoutineRestoration()
      },
      onRestorationFinished: {
        sessionStore.finishServerRoutineRestoration()
      },
      onRestorationFailed: {
        sessionStore.failServerRoutineRestoration()
      },
      restorationUIHeldForAccountRestore:
        holdUIForStoredSessionRestoration
    )

    return RestorationFixture(
      container: container,
      profileRepository: profileRepository,
      routineRepository: routineRepository,
      onboardingRepository: onboardingRepository,
      provisionalStore: provisionalStore,
      syncRepository: syncRepository,
      accountSessionStore: accountSessionStore,
      sessionStore: sessionStore,
      statusService: statusService,
      restorationBackfillBarrier: restorationBackfillBarrier,
      coordinator: coordinator
    )
  }

  private func destination(
    for fixture: RestorationFixture,
    didStartOnboarding: Bool = false,
    didCompleteOnboardingTrial: Bool = false,
    didCompleteAccountEntry: Bool = false
  ) -> AppRootDestination {
    AppRouter.rootDestination(
      sessionPhase: fixture.sessionStore.phase,
      hasLocalProfile: fixture.sessionStore.profile != nil,
      accountState: fixture.accountSessionStore.state,
      accountFeaturesEnabled: true,
      didStartOnboarding: didStartOnboarding,
      didCompleteOnboardingTrial: didCompleteOnboardingTrial,
      didCompleteAccountEntry: didCompleteAccountEntry
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
  let onboardingRepository: SwiftDataOnboardingRepository
  let provisionalStore: SwiftDataProvisionalOnboardingDataStore
  let syncRepository: SwiftDataRoutineSyncRepository
  let accountSessionStore: AccountSessionStore
  let sessionStore: SessionStore
  let statusService: RestorationStatusServiceStub
  let restorationBackfillBarrier: RoutineRestorationBackfillBarrier
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

  private var outcomesByMemberID: [Int64: Outcome]
  private(set) var requestIdentities: [AccountSessionIdentity] = []

  init(outcomesByMemberID: [Int64: Outcome]) {
    self.outcomesByMemberID = outcomesByMemberID
  }

  func setOutcome(_ outcome: Outcome, memberID: Int64) {
    outcomesByMemberID[memberID] = outcome
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
  private let activeRoutineGroupByMemberID: [Int64: ServerActiveRoutineGroup]
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
    suspendedDetailIDs: Set<Int64> = [],
    activeRoutineGroupByMemberID: [Int64: ServerActiveRoutineGroup] = [:]
  ) {
    self.summariesByMemberID = summariesByMemberID
    self.detailsByGroupID = detailsByGroupID
    self.suspendedDetailIDs = suspendedDetailIDs
    self.activeRoutineGroupByMemberID = activeRoutineGroupByMemberID
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
      throw AccountRoutineGroupRemoteError.invalidResponse(
        reason: "test stub: no detail fixture for routineGroupID \(routineGroupID)"
      )
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
        throwing: AccountRoutineGroupRemoteError.invalidResponse(
          reason: "test stub: resumeDetail called with no fixture for routineGroupID \(routineGroupID)"
        )
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
    activeRoutineGroupByMemberID[identity.memberID]
  }

  func fetchTodayRoutineGroupSummary(
    identity: AccountSessionIdentity
  ) async throws -> ServerTodayRoutineGroupSummary? {
    nil
  }
}

@MainActor
private final class RestorationRoutineSyncSenderStub:
  RoutineSyncSending {
  private(set) var callCount = 0

  func sendNext(
    memberID _: Int64,
    at _: Date
  ) async throws -> RoutineSyncSendResult {
    callCount += 1
    return .idle
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

nonisolated private func secondServerGroupDetail()
  -> ServerRoutineGroupDetail {
  ServerRoutineGroupDetail(
    routineGroupID: 502,
    title: "서버 저녁 루틴",
    description: "서버에서 만든 두 번째 루틴",
    alarmDaysRaw: "SAT,SUN",
    alarmTimeRaw: "21:00",
    weatherNotificationEnabled: false,
    routines: [
      ServerRoutineItem(
        routineID: 611,
        title: "독서하기",
        type: .check,
        durationSeconds: 0,
        steps: []
      ),
    ]
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
