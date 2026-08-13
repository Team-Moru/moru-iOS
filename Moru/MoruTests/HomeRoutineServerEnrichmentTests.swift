//
//  HomeRoutineServerEnrichmentTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class HomeRoutineServerEnrichmentTests: XCTestCase {
  @MainActor
  func testFullyBoundSnapshotMapsAndOverlaysTodayHomeContent() async throws {
    let fixture = HomeEnrichmentFixture()
    let useCase = fixture.makeUseCase()

    let enrichment = try await useCase.execute(localResult: fixture.localResult)

    guard case .applied(let snapshot) = enrichment else {
      return XCTFail("A complete binding should produce an applicable snapshot.")
    }
    XCTAssertEqual(snapshot.localRoutineID, fixture.routine.id)
    XCTAssertEqual(snapshot.completionRate, 0.5)
    XCTAssertEqual(snapshot.routines.map(\.localStepID), fixture.routine.steps.map(\.id))
    XCTAssertEqual(snapshot.routines.map(\.isCompleted), [true, false])
    XCTAssertEqual(snapshot.routines.map(\.completedTimeSeconds), [61, nil])

    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutineLoadUseCase(result: fixture.localResult),
      enrichHomeRoutinesUseCase: useCase
    )
    viewModel.load()
    await waitUntil { viewModel.routineServerState == .applied }

    let today = try XCTUnwrap(viewModel.state.todayRoutine)
    XCTAssertEqual(today.steps.map(\.isCompleted), [true, false])
    XCTAssertEqual(today.steps[0].detail, "1:01")
    XCTAssertEqual(today.stepSummaryText, "2개 스텝 · 3분")
    XCTAssertEqual(today.estimatedDurationText, "소요 시간 3분")
    XCTAssertEqual(today.completionText, "1/2 완료")
    XCTAssertEqual(today.progressText, "50%")
    XCTAssertEqual(today.progress, 0.5)
    XCTAssertEqual(viewModel.state.todayProgress.percentText, "50%")
    XCTAssertEqual(viewModel.state.todayProgress.completedText, "1/2 완료")
  }

  @MainActor
  func testBothRemoteReadsReceiveTheExactCapturedSessionIdentity()
    async throws {
    let fixture = HomeEnrichmentFixture()
    let service = HomeRemoteService(
      active: fixture.remoteActive,
      today: fixture.remoteToday
    )

    _ = try await fixture.makeUseCase(remoteService: service).execute(
      localResult: fixture.localResult
    )

    let identities = await service.requestIdentities
    let expected = try XCTUnwrap(
      fixture.identityProvider.currentAccountSessionIdentity
    )
    XCTAssertEqual(identities.count, 2)
    XCTAssertTrue(identities.allSatisfy { $0 == expected })
  }

  @MainActor
  func testIncoherentRemoteCountAndRateFallsBack() async throws {
    let fixture = HomeEnrichmentFixture(completionRate: 0.73)

    let result = try await fixture.makeUseCase().execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.inconsistentRemoteSnapshot))
  }

  @MainActor
  func testNoActiveReturnsNoActiveOnlyWhenLocalIsAlsoEmpty() async throws {
    let service = HomeRemoteService(active: nil, today: nil)
    let fixture = HomeEnrichmentFixture(remoteService: service)
    let empty = fixture.localResult(
      replacingManualRoutines: [],
      todayRoutine: .some(nil)
    )

    XCTAssertTrue(empty.manualRoutines.isEmpty)
    XCTAssertNil(empty.todayRoutine)

    let result = try await fixture.makeUseCase().execute(localResult: empty)

    XCTAssertEqual(result, .noActive)
  }

  @MainActor
  func testRemoteNoActiveDoesNotEraseLocalActiveRoutine() async throws {
    let service = HomeRemoteService(active: nil, today: nil)
    let fixture = HomeEnrichmentFixture(remoteService: service)

    let result = try await fixture.makeUseCase().execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.remoteHasNoActiveLocalHasActive))
  }

  @MainActor
  func testMissingAndWrongActiveGroupBindingsFallBack() async throws {
    let fixture = HomeEnrichmentFixture()
    let missing = HomeSyncStateReader(bindings: fixture.stepBindings)
    let missingResult = try await fixture.makeUseCase(syncReader: missing).execute(
      localResult: fixture.localResult
    )
    XCTAssertEqual(
      missingResult,
      .fallback(.activeGroupBindingMissing)
    )

    let wrongRemote = fixture.bindings(overridingGroupRemoteID: 999)
    let wrongRemoteResult = try await fixture.makeUseCase(
      syncReader: HomeSyncStateReader(bindings: wrongRemote)
    ).execute(localResult: fixture.localResult)
    XCTAssertEqual(
      wrongRemoteResult,
      .fallback(.activeGroupIdentityMismatch)
    )
  }

  @MainActor
  func testWrongGroupBindingMetadataFallsBack() async throws {
    let fixture = HomeEnrichmentFixture()
    let malformed = fixture.bindings(
      groupBinding: fixture.binding(
        localID: fixture.routine.id,
        remoteID: fixture.groupRemoteID,
        kind: .routine,
        namespace: .staging,
        memberID: 777
      )
    )

    let result = try await fixture.makeUseCase(
      syncReader: HomeSyncStateReader(bindings: malformed)
    ).execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.activeGroupIdentityMismatch))
  }

  @MainActor
  func testMissingRoutineBindingFallsBack() async throws {
    let fixture = HomeEnrichmentFixture()
    var bindings = fixture.allBindings
    bindings.removeValue(forKey: fixture.routine.steps[1].id)

    let result = try await fixture.makeUseCase(
      syncReader: HomeSyncStateReader(bindings: bindings)
    ).execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.activeRoutineBindingMissing))
  }

  @MainActor
  func testDuplicateRoutineRemoteBindingFallsBack() async throws {
    let fixture = HomeEnrichmentFixture()
    var bindings = fixture.allBindings
    bindings[fixture.routine.steps[1].id] = fixture.binding(
      localID: fixture.routine.steps[1].id,
      remoteID: fixture.stepRemoteIDs[0],
      kind: .routine,
      parentID: fixture.routine.id
    )

    let result = try await fixture.makeUseCase(
      syncReader: HomeSyncStateReader(bindings: bindings)
    ).execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.activeRoutineIdentityMismatch))
  }

  @MainActor
  func testWrongRoutineParentAndMetadataFallBack() async throws {
    let fixture = HomeEnrichmentFixture()
    var bindings = fixture.allBindings
    bindings[fixture.routine.steps[0].id] = fixture.binding(
      localID: fixture.routine.steps[0].id,
      remoteID: fixture.stepRemoteIDs[0],
      kind: .routine,
      namespace: .staging,
      parentID: UUID()
    )

    let result = try await fixture.makeUseCase(
      syncReader: HomeSyncStateReader(bindings: bindings)
    ).execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.activeRoutineIdentityMismatch))
  }

  @MainActor
  func testExtraRemoteRoutineAndIncompleteBindingSetFallBack() async throws {
    let fixture = HomeEnrichmentFixture(
      remoteRoutines: [
        HomeEnrichmentFixture.remoteStep(id: 101, completed: true),
        HomeEnrichmentFixture.remoteStep(id: 102, completed: false),
        HomeEnrichmentFixture.remoteStep(id: 103, completed: false),
      ],
      completionRate: 0.33
    )

    let result = try await fixture.makeUseCase().execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.activeRoutineIdentityMismatch))
  }

  @MainActor
  func testMultipleLocalActiveRoutinesAreRejectedAsAmbiguous() async throws {
    let fixture = HomeEnrichmentFixture()
    let second = HomeEnrichmentFixture.makeRoutine(name: "두 번째")
    let local = fixture.localResult(
      replacingManualRoutines: [fixture.routine, second],
      todayRoutine: fixture.routine
    )

    let result = try await fixture.makeUseCase().execute(localResult: local)

    XCTAssertEqual(result, .fallback(.localActiveAmbiguous))
  }

  @MainActor
  func testRemoteActiveAndTodayMustBothExistAndAgree() async throws {
    let fixture = HomeEnrichmentFixture()
    let onlyActive = HomeRemoteService(active: fixture.remoteActive, today: nil)
    let onlyActiveResult = try await fixture.makeUseCase(
      remoteService: onlyActive
    ).execute(localResult: fixture.localResult)
    XCTAssertEqual(
      onlyActiveResult,
      .fallback(.inconsistentRemoteSnapshot)
    )

    let disagreeingToday = ServerTodayRoutineGroupSummary(
      completedCount: 0,
      totalCount: 2,
      completionRate: 0
    )
    let inconsistent = HomeRemoteService(
      active: fixture.remoteActive,
      today: disagreeingToday
    )
    let inconsistentResult = try await fixture.makeUseCase(
      remoteService: inconsistent
    ).execute(localResult: fixture.localResult)
    XCTAssertEqual(
      inconsistentResult,
      .fallback(.inconsistentRemoteSnapshot)
    )
  }

  @MainActor
  func testSignedOutSkipsBothRemoteCallsAndSyncReads() async throws {
    let service = HomeRemoteService(active: nil, today: nil)
    let fixture = HomeEnrichmentFixture(remoteService: service, identity: nil)
    let reader = HomeSyncStateReader(bindings: fixture.allBindings)

    let result = try await fixture.makeUseCase(syncReader: reader).execute(
      localResult: fixture.localResult
    )

    XCTAssertEqual(result, .fallback(.signedOut))
    let requestCounts = await service.requestCounts
    XCTAssertEqual(requestCounts, .zero)
    XCTAssertEqual(reader.bindingReadCount, 0)
    XCTAssertEqual(reader.pendingReadCount, 0)
  }

  @MainActor
  func testOfflineTimeoutAndServerFailuresKeepLocalFallback() async throws {
    for failure in HomeRemoteFailure.allCases {
      let service = HomeRemoteService(
        active: nil,
        today: nil,
        failure: failure
      )
      let fixture = HomeEnrichmentFixture(remoteService: service)

      let result = try await fixture.makeUseCase().execute(localResult: fixture.localResult)

      XCTAssertEqual(result, .fallback(.remoteUnavailable), "Failure: \(failure)")
    }
  }

  @MainActor
  func testDifferentMemberSwitchDiscardsDeferredResponse() async {
    await assertSessionSwitchDiscardsResponse(
      switchedIdentity: AccountSessionIdentity(memberID: 52, sessionID: UUID())
    )
  }

  @MainActor
  func testSameMemberNewSessionDiscardsDeferredResponse() async {
    await assertSessionSwitchDiscardsResponse(
      switchedIdentity: AccountSessionIdentity(memberID: 41, sessionID: UUID())
    )
  }

  @MainActor
  func testCancelledOlderLoadCannotOverwriteLatestHomeContent() async throws {
    let fixture = HomeEnrichmentFixture()
    let enricher = SequencedHomeEnricher()
    let loader = SequencedHomeLoader(results: [fixture.localResult, fixture.localResult])
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: loader,
      enrichHomeRoutinesUseCase: enricher
    )
    var didDiscardStaleResult = false
    viewModel.onStaleRoutineServerResultDiscarded = {
      didDiscardStaleResult = true
    }

    viewModel.load()
    await enricher.waitForRequestCount(1)
    viewModel.load()
    await enricher.waitForRequestCount(2)
    XCTAssertTrue(enricher.wasCancelled(at: 0))

    let latest = fixture.snapshot(completionRate: 1, completed: [true, true])
    enricher.resume(at: 1, returning: .applied(latest))
    await waitUntil { viewModel.routineServerState == .applied }
    enricher.resume(
      at: 0,
      returning: .applied(fixture.snapshot(completionRate: 0, completed: [false, false]))
    )
    await waitUntil { didDiscardStaleResult }

    XCTAssertEqual(viewModel.state.todayRoutine?.progress, 1)
    XCTAssertEqual(viewModel.state.todayRoutine?.steps.map(\.isCompleted), [true, true])
  }

  @MainActor
  func testPendingExecutionForMatchedGroupPreventsStaleRegression() async throws {
    let fixture = HomeEnrichmentFixture()
    let reader = HomeSyncStateReader(
      bindings: fixture.allBindings,
      pendingGroupIDs: [fixture.routine.id]
    )

    let result = try await fixture.makeUseCase(syncReader: reader).execute(
      localResult: fixture.localResult
    )

    XCTAssertEqual(result, .fallback(.pendingLocalExecution))
  }

  @MainActor
  func testPendingExecutionForUnrelatedGroupDoesNotBlockEnrichment() async throws {
    let fixture = HomeEnrichmentFixture()
    let reader = HomeSyncStateReader(
      bindings: fixture.allBindings,
      pendingGroupIDs: [UUID()]
    )

    let result = try await fixture.makeUseCase(syncReader: reader).execute(
      localResult: fixture.localResult
    )

    guard case .applied = result else {
      return XCTFail("An unrelated execution must not block the active group.")
    }
  }

  @MainActor
  func testSwiftDataPendingExecutionPreventsServerProgressRegression()
    async throws {
    let fixture = HomeEnrichmentFixture()
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    var assignments = [
      RoutineServerBindingAssignment(
        entityKind: .routineGroup,
        localEntityID: fixture.routine.id,
        remoteID: fixture.groupRemoteID
      ),
    ]
    assignments += zip(
      fixture.routine.steps,
      fixture.stepRemoteIDs
    ).map { step, remoteID in
      RoutineServerBindingAssignment(
        entityKind: .routine,
        localEntityID: step.id,
        remoteID: remoteID,
        parentEntityKind: .routineGroup,
        parentLocalEntityID: fixture.routine.id
      )
    }
    _ = try repository.recordRemoteIDs(
      assignments,
      memberID: fixture.memberID,
      at: HomeEnrichmentFixture.referenceDate
    )
    _ = try repository.enqueue(
      command: .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          runLocalID: UUID(),
          groupLocalID: fixture.routine.id,
          routineLocalID: fixture.routine.steps[0].id,
          runStartedAt: HomeEnrichmentFixture.referenceDate,
          runCompletedAt: nil,
          timeZoneIdentifier: "Asia/Seoul",
          result: RoutineSyncExecutionResultSnapshot(
            localID: UUID(),
            completedAt: HomeEnrichmentFixture.referenceDate,
            skipped: false,
            durationSeconds: 30,
            inputText: nil,
            transcript: nil
          )
        )
      ),
      memberID: fixture.memberID,
      at: HomeEnrichmentFixture.referenceDate
    )
    let mutationsBefore = try repository.mutations(
      memberID: fixture.memberID
    )
    let useCase = fixture.makeUseCase(
      syncReader: DefaultHomeRoutineSyncStateReader(repository: repository)
    )

    let result = try await useCase.execute(localResult: fixture.localResult)

    XCTAssertEqual(result, .fallback(.pendingLocalExecution))
    XCTAssertEqual(
      try repository.mutations(memberID: fixture.memberID),
      mutationsBefore
    )
  }

  @MainActor
  func testServerOverlayNeverRegressesLocalStepOrAggregateProgress() async throws {
    let fixture = HomeEnrichmentFixture(
      remoteRoutines: [
        HomeEnrichmentFixture.remoteStep(id: 101, completed: false),
        HomeEnrichmentFixture.remoteStep(id: 102, completed: false),
      ],
      completionRate: 0
    )
    let localRun = HomeEnrichmentFixture.makeRun(
      routine: fixture.routine,
      completedStepIndexes: [0]
    )
    let local = fixture.localResult(replacingRuns: [fixture.routine.id: localRun])
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutineLoadUseCase(result: local),
      enrichHomeRoutinesUseCase: fixture.makeUseCase()
    )

    viewModel.load()
    await waitUntil { viewModel.routineServerState == .applied }

    XCTAssertEqual(viewModel.state.todayRoutine?.steps.map(\.isCompleted), [true, false])
    XCTAssertEqual(viewModel.state.todayRoutine?.progress, 0.5)
    XCTAssertEqual(viewModel.state.todayProgress.progress, 0.5)
    XCTAssertEqual(viewModel.state.todayProgress.completedText, "1/2 완료")
  }

  @MainActor
  func testDisjointLocalAndServerCompletionsKeepTodayProgressCoherent()
    async throws {
    let fixture = HomeEnrichmentFixture()
    let localRun = HomeEnrichmentFixture.makeRun(
      routine: fixture.routine,
      completedStepIndexes: [1]
    )
    let local = fixture.localResult(
      replacingRuns: [fixture.routine.id: localRun]
    )
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutineLoadUseCase(result: local),
      enrichHomeRoutinesUseCase: fixture.makeUseCase()
    )

    viewModel.load()
    await waitUntil { viewModel.routineServerState == .applied }

    XCTAssertEqual(
      viewModel.state.todayRoutine?.steps.map(\.isCompleted),
      [true, true]
    )
    XCTAssertEqual(viewModel.state.todayRoutine?.progress, 1)
    XCTAssertEqual(viewModel.state.todayProgress.progress, 1)
    XCTAssertEqual(viewModel.state.todayProgress.percentText, "100%")
    XCTAssertEqual(viewModel.state.todayProgress.completedText, "2/2 완료")
  }

  @MainActor
  func testUnscheduledActiveRoutineKeepsLocalAheadProgressCoherent()
    async throws {
    let fixture = HomeEnrichmentFixture()
    let localRun = HomeEnrichmentFixture.makeRun(
      routine: fixture.routine,
      completedStepIndexes: [0, 1]
    )
    let local = fixture.localResult(
      todayRoutine: .some(nil),
      replacingRuns: [fixture.routine.id: localRun]
    )
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutineLoadUseCase(result: local),
      enrichHomeRoutinesUseCase: fixture.makeUseCase()
    )

    viewModel.load()
    await waitUntil { viewModel.routineServerState == .applied }

    XCTAssertNil(viewModel.state.todayRoutine)
    XCTAssertEqual(viewModel.state.activeRoutines.first?.progress, 1)
    XCTAssertEqual(viewModel.state.todayProgress.progress, 1)
    XCTAssertEqual(viewModel.state.todayProgress.percentText, "100%")
    XCTAssertEqual(viewModel.state.todayProgress.completedText, "2/2 완료")
  }

  @MainActor
  func testEditedRoutineRunPlanMismatchKeepsCompleteLocalSnapshot()
    async throws {
    let fixture = HomeEnrichmentFixture()
    let removedStep = fixture.routine.steps[1]
    var historicalRun = HomeEnrichmentFixture.makeRun(
      routine: fixture.routine,
      completedStepIndexes: [0]
    )
    historicalRun.plannedSteps.append(
      RoutineStepSnapshot(
        stepID: UUID(),
        stepTitle: "이전 실행 스냅샷",
        stepType: .confirm,
        stepOrder: 2
      )
    )
    historicalRun.results.append(
      RoutineStepResult(
        stepID: removedStep.id,
        stepTitle: removedStep.title,
        stepType: removedStep.type,
        completedAt: Date()
      )
    )
    let local = fixture.localResult(
      replacingRuns: [fixture.routine.id: historicalRun]
    )
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutineLoadUseCase(result: local),
      enrichHomeRoutinesUseCase: fixture.makeUseCase()
    )

    viewModel.load()
    await waitUntil {
      viewModel.routineServerState
        == .fallback(.activeRoutineIdentityMismatch)
    }

    XCTAssertEqual(viewModel.state.todayRoutine?.steps.count, 3)
    XCTAssertEqual(viewModel.state.todayRoutine?.stepSummaryText, "3개 스텝 · 3분")
    XCTAssertEqual(viewModel.state.todayProgress.completedText, "2/3 완료")
    XCTAssertEqual(
      viewModel.state.todayProgress.progress,
      2.0 / 3.0,
      accuracy: 0.000_001
    )
  }

  @MainActor
  func testEnrichmentUsesOnlyReadOperations() async throws {
    let fixture = HomeEnrichmentFixture()
    let reader = HomeSyncStateReader(bindings: fixture.allBindings)

    _ = try await fixture.makeUseCase(syncReader: reader).execute(
      localResult: fixture.localResult
    )

    XCTAssertEqual(reader.bindingReadCount, 3)
    XCTAssertEqual(reader.pendingReadCount, 1)
    XCTAssertEqual(reader.observedMemberIDs, [41, 41, 41, 41])
  }

  @MainActor
  func testServerProjectionDayMismatchSkipsRemoteAndKeepsLocal()
    async throws {
    let service = HomeRemoteService(active: nil, today: nil)
    let fixture = HomeEnrichmentFixture(remoteService: service)
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let date = ISO8601DateFormatter().date(
      from: "2026-08-13T12:00:00Z"
    )!
    let useCase = fixture.makeUseCase(
      localCalendar: losAngeles,
      now: { date }
    )
    let local = fixture.localResult(loadedAt: date)

    let result = try await useCase.execute(localResult: local)

    XCTAssertEqual(result, .fallback(.serverProjectionDayMismatch))
    let requestCounts = await service.requestCounts
    XCTAssertEqual(requestCounts, .zero)
  }

  @MainActor
  func testProjectionDayCrossingDuringRequestsRejectsBothResponses()
    async throws {
    let beforeMidnight = ISO8601DateFormatter().date(
      from: "2026-08-13T14:59:50Z"
    )!
    let afterMidnight = ISO8601DateFormatter().date(
      from: "2026-08-13T15:00:10Z"
    )!
    let clock = MutableHomeClock(beforeMidnight)
    let remote = DeferredHomeRemoteService()
    let fixture = HomeEnrichmentFixture(remoteService: remote)
    var seoul = Calendar(identifier: .gregorian)
    seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let useCase = fixture.makeUseCase(
      localCalendar: seoul,
      now: { clock.value }
    )
    let local = fixture.localResult(loadedAt: beforeMidnight)
    let task = Task {
      try await useCase.execute(localResult: local)
    }

    await remote.waitForBothRequests()
    clock.value = afterMidnight
    await remote.resume(
      active: fixture.remoteActive,
      today: fixture.remoteToday
    )

    let result = try await task.value
    XCTAssertEqual(result, .fallback(.serverProjectionDayMismatch))
  }

  @MainActor
  func testLoadingStateImmediatelyRetainsVisibleLocalContent() async {
    let fixture = HomeEnrichmentFixture()
    let enricher = SequencedHomeEnricher()
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutineLoadUseCase(result: fixture.localResult),
      enrichHomeRoutinesUseCase: enricher
    )

    viewModel.load()
    await enricher.waitForRequestCount(1)

    XCTAssertEqual(viewModel.state.loadState, .content)
    XCTAssertEqual(viewModel.state.todayRoutine?.id, fixture.routine.id)
    XCTAssertEqual(viewModel.routineServerState, .loading)
    enricher.resume(at: 0, returning: .fallback(.remoteUnavailable))
  }

  @MainActor
  private func assertSessionSwitchDiscardsResponse(
    switchedIdentity: AccountSessionIdentity
  ) async {
    let remote = DeferredHomeRemoteService()
    let fixture = HomeEnrichmentFixture(remoteService: remote)
    let task = Task {
      try await fixture.makeUseCase().execute(localResult: fixture.localResult)
    }
    await remote.waitForBothRequests()
    fixture.identityProvider.currentAccountSessionIdentity = switchedIdentity
    await remote.resume(active: fixture.remoteActive, today: fixture.remoteToday)

    do {
      _ = try await task.value
      XCTFail("A response from an obsolete account session must be cancelled.")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, got \(error).")
    }
  }

  @MainActor
  private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
  ) async {
    for _ in 0..<1_000 where !predicate() {
      await Task.yield()
    }
    XCTAssertTrue(predicate(), "Timed out waiting for asynchronous Home state.")
  }
}

@MainActor
private final class HomeEnrichmentFixture {
  nonisolated static let referenceDate = Date(
    timeIntervalSince1970: 1_786_622_400
  )

  let memberID: Int64 = 41
  let groupRemoteID: Int64 = 91
  let stepRemoteIDs: [Int64] = [101, 102]
  let routine: Routine
  let remoteActive: ServerActiveRoutineGroup
  let remoteToday: ServerTodayRoutineGroupSummary
  let remoteService: any AccountRoutineGroupRemoteServing
  let identityProvider: MutableHomeSessionIdentityProvider

  init(
    remoteService: (any AccountRoutineGroupRemoteServing)? = nil,
    identity: AccountSessionIdentity? = AccountSessionIdentity(
      memberID: 41,
      sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
    ),
    remoteRoutines: [ServerActiveRoutine] = [
      HomeEnrichmentFixture.remoteStep(id: 101, completed: true),
      HomeEnrichmentFixture.remoteStep(id: 102, completed: false),
    ],
    completionRate: Double = 0.5
  ) {
    routine = Self.makeRoutine(name: "로컬 루틴")
    remoteActive = ServerActiveRoutineGroup(
      routineGroupID: groupRemoteID,
      title: "서버 제목",
      totalDurationSeconds: 181,
      completionRate: completionRate,
      routines: remoteRoutines
    )
    remoteToday = ServerTodayRoutineGroupSummary(
      completedCount: remoteRoutines.filter(\.isCompleted).count,
      totalCount: remoteRoutines.count,
      completionRate: completionRate
    )
    self.remoteService = remoteService ?? HomeRemoteService(
      active: remoteActive,
      today: remoteToday
    )
    identityProvider = MutableHomeSessionIdentityProvider(identity: identity)
  }

  var localResult: HomeRoutineLoadResult {
    HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "모루"),
      todayRoutine: routine,
      manualRoutines: [routine],
      todayRunsByRoutineID: [:],
      streak: RoutineStreak(currentDays: 0, bestDays: 0, completedWeekdays: []),
      loadedAt: Self.referenceDate
    )
  }

  var allBindings: [UUID: RoutineServerBinding] {
    bindings(groupBinding: binding(
      localID: routine.id,
      remoteID: groupRemoteID,
      kind: .routineGroup
    ))
  }

  var stepBindings: [UUID: RoutineServerBinding] {
    Dictionary(uniqueKeysWithValues: zip(routine.steps, stepRemoteIDs).map { step, remoteID in
      (
        step.id,
        binding(
          localID: step.id,
          remoteID: remoteID,
          kind: .routine,
          parentID: routine.id
        )
      )
    })
  }

  func bindings(
    groupBinding: RoutineServerBinding? = nil
  ) -> [UUID: RoutineServerBinding] {
    var result = stepBindings
    if let groupBinding {
      result[routine.id] = groupBinding
    }
    return result
  }

  func bindings(overridingGroupRemoteID remoteID: Int64) -> [UUID: RoutineServerBinding] {
    bindings(groupBinding: binding(
      localID: routine.id,
      remoteID: remoteID,
      kind: .routineGroup
    ))
  }

  func binding(
    localID: UUID,
    remoteID: Int64,
    kind: RoutineSyncEntityKind,
    namespace: RoutineSyncServerNamespace = .production,
    memberID: Int64 = 41,
    parentID: UUID? = nil
  ) -> RoutineServerBinding {
    RoutineServerBinding(
      id: UUID(),
      serverNamespace: namespace,
      memberID: memberID,
      entityKind: kind,
      localEntityID: localID,
      remoteID: remoteID,
      remoteRevision: nil,
      parentEntityKind: parentID == nil ? nil : .routineGroup,
      parentLocalEntityID: parentID,
      createdAt: .distantPast,
      updatedAt: .distantPast
    )
  }

  func makeUseCase(
    remoteService: (any AccountRoutineGroupRemoteServing)? = nil,
    syncReader: (any HomeRoutineSyncStateReading)? = nil,
    localCalendar: Calendar? = nil,
    now: (@Sendable () -> Date)? = nil
  ) -> EnrichHomeRoutinesUseCase {
    let referenceDate = Self.referenceDate
    return EnrichHomeRoutinesUseCase(
      remoteService: remoteService ?? self.remoteService,
      sessionIdentityProvider: identityProvider,
      syncStateReader: syncReader ?? HomeSyncStateReader(bindings: allBindings),
      localCalendar: localCalendar ?? Self.seoulCalendar(),
      now: now ?? { referenceDate }
    )
  }

  func localResult(
    replacingManualRoutines routines: [Routine]? = nil,
    todayRoutine: Routine?? = nil,
    replacingRuns runs: [UUID: RoutineRun]? = nil,
    loadedAt: Date? = nil
  ) -> HomeRoutineLoadResult {
    let base = localResult
    return HomeRoutineLoadResult(
      profile: base.profile,
      todayRoutine: todayRoutine ?? base.todayRoutine,
      manualRoutines: routines ?? base.manualRoutines,
      todayRunsByRoutineID: runs ?? base.todayRunsByRoutineID,
      streak: base.streak,
      loadedAt: loadedAt ?? base.loadedAt
    )
  }

  func snapshot(
    completionRate: Double,
    completed: [Bool]
  ) -> HomeBoundActiveRoutineSnapshot {
    HomeBoundActiveRoutineSnapshot(
      localRoutineID: routine.id,
      completionRate: completionRate,
      routines: zip(routine.steps, completed).map { step, isCompleted in
        HomeBoundRoutineProgress(
          localStepID: step.id,
          isCompleted: isCompleted,
          completedTimeSeconds: isCompleted ? 60 : nil
        )
      },
      today: HomeBoundTodayProgress(
        completedCount: completed.filter { $0 }.count,
        totalCount: completed.count,
        completionRate: completionRate
      )
    )
  }

  nonisolated static func remoteStep(
    id: Int64,
    completed: Bool
  ) -> ServerActiveRoutine {
    ServerActiveRoutine(
      routineID: id,
      title: "서버 스텝 \(id)",
      isCompleted: completed,
      completedTimeSeconds: completed ? 61 : nil
    )
  }

  nonisolated static func seoulCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }

  static func makeRoutine(name: String) -> Routine {
    Routine(
      name: name,
      steps: [
        RoutineStep(
          type: .confirm,
          title: "첫 단계",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          type: .timer,
          title: "둘째 단계",
          order: 1,
          estimatedSeconds: 120
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 0,
        weekdays: Weekday.allCases
      ),
      isActive: true,
      createdAt: .distantPast,
      updatedAt: .distantPast
    )
  }

  static func makeRun(
    routine: Routine,
    completedStepIndexes: Set<Int>
  ) -> RoutineRun {
    RoutineRun(
      routine: routine,
      startedAt: Date(),
      results: routine.steps.enumerated().compactMap { index, step in
        guard completedStepIndexes.contains(index) else {
          return nil
        }
        return RoutineStepResult(
          stepID: step.id,
          stepTitle: step.title,
          stepType: step.type,
          completedAt: Date()
        )
      }
    )
  }
}

@MainActor
private final class MutableHomeSessionIdentityProvider:
  CurrentAccountSessionIdentityProviding {
  var currentAccountSessionIdentity: AccountSessionIdentity?

  init(identity: AccountSessionIdentity?) {
    currentAccountSessionIdentity = identity
  }
}

@MainActor
private final class HomeSyncStateReader: HomeRoutineSyncStateReading {
  private let bindings: [UUID: RoutineServerBinding]
  private let pendingGroupIDs: Set<UUID>
  private(set) var bindingReadCount = 0
  private(set) var pendingReadCount = 0
  private(set) var observedMemberIDs: [Int64] = []

  init(
    bindings: [UUID: RoutineServerBinding],
    pendingGroupIDs: Set<UUID> = []
  ) {
    self.bindings = bindings
    self.pendingGroupIDs = pendingGroupIDs
  }

  func binding(
    memberID: Int64,
    entityKind: RoutineSyncEntityKind,
    localEntityID: UUID
  ) throws -> RoutineServerBinding? {
    bindingReadCount += 1
    observedMemberIDs.append(memberID)
    return bindings[localEntityID]
  }

  func hasPendingRoutineExecution(
    memberID: Int64,
    groupLocalID: UUID
  ) throws -> Bool {
    pendingReadCount += 1
    observedMemberIDs.append(memberID)
    return pendingGroupIDs.contains(groupLocalID)
  }
}

private struct HomeRemoteRequestCounts: Equatable, Sendable {
  var active = 0
  var today = 0

  static let zero = HomeRemoteRequestCounts()
}

nonisolated private final class MutableHomeClock: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Date

  init(_ value: Date) {
    storedValue = value
  }

  var value: Date {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storedValue
    }
    set {
      lock.lock()
      storedValue = newValue
      lock.unlock()
    }
  }
}

private enum HomeRemoteFailure: Error, CaseIterable, Sendable {
  case offline
  case timeout
  case server
}

private actor HomeRemoteService: AccountRoutineGroupRemoteServing {
  private let active: ServerActiveRoutineGroup?
  private let today: ServerTodayRoutineGroupSummary?
  private let failure: HomeRemoteFailure?
  private var counts = HomeRemoteRequestCounts.zero
  private var identities: [AccountSessionIdentity] = []

  init(
    active: ServerActiveRoutineGroup?,
    today: ServerTodayRoutineGroupSummary?,
    failure: HomeRemoteFailure? = nil
  ) {
    self.active = active
    self.today = today
    self.failure = failure
  }

  var requestCounts: HomeRemoteRequestCounts { counts }
  var requestIdentities: [AccountSessionIdentity] { identities }

  func fetchRoutineGroups(memberID: Int64) async throws -> [ServerRoutineGroupSummary] {
    throw HomeRemoteFailure.server
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    throw HomeRemoteFailure.server
  }

  func fetchActiveRoutineGroup(
    identity: AccountSessionIdentity
  ) async throws -> ServerActiveRoutineGroup? {
    counts.active += 1
    identities.append(identity)
    if let failure { throw failure }
    return active
  }

  func fetchTodayRoutineGroupSummary(
    identity: AccountSessionIdentity
  ) async throws -> ServerTodayRoutineGroupSummary? {
    counts.today += 1
    identities.append(identity)
    if let failure { throw failure }
    return today
  }
}

private actor DeferredHomeRemoteService: AccountRoutineGroupRemoteServing {
  private var activeContinuation:
    CheckedContinuation<ServerActiveRoutineGroup?, Error>?
  private var todayContinuation:
    CheckedContinuation<ServerTodayRoutineGroupSummary?, Error>?
  private var activeRequested = false
  private var todayRequested = false

  func fetchRoutineGroups(memberID: Int64) async throws -> [ServerRoutineGroupSummary] {
    throw HomeRemoteFailure.server
  }

  func fetchRoutineGroupDetail(
    routineGroupID: Int64,
    memberID: Int64
  ) async throws -> ServerRoutineGroupDetail {
    throw HomeRemoteFailure.server
  }

  func fetchActiveRoutineGroup(
    identity: AccountSessionIdentity
  ) async throws -> ServerActiveRoutineGroup? {
    activeRequested = true
    return try await withCheckedThrowingContinuation { activeContinuation = $0 }
  }

  func fetchTodayRoutineGroupSummary(
    identity: AccountSessionIdentity
  ) async throws -> ServerTodayRoutineGroupSummary? {
    todayRequested = true
    return try await withCheckedThrowingContinuation { todayContinuation = $0 }
  }

  func waitForBothRequests() async {
    while !activeRequested || !todayRequested {
      await Task.yield()
    }
  }

  func resume(
    active: ServerActiveRoutineGroup?,
    today: ServerTodayRoutineGroupSummary?
  ) {
    activeContinuation?.resume(returning: active)
    activeContinuation = nil
    todayContinuation?.resume(returning: today)
    todayContinuation = nil
  }
}

@MainActor
private final class StaticHomeRoutineLoadUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let result: HomeRoutineLoadResult

  init(result: HomeRoutineLoadResult) {
    self.result = result
  }

  func execute() throws -> HomeRoutineLoadResult { result }
}

@MainActor
private final class SequencedHomeLoader: LoadHomeRoutinesUseCaseProtocol {
  private var results: [HomeRoutineLoadResult]

  init(results: [HomeRoutineLoadResult]) {
    self.results = results
  }

  func execute() throws -> HomeRoutineLoadResult {
    results.removeFirst()
  }
}

@MainActor
private final class SequencedHomeEnricher: EnrichHomeRoutinesUseCaseProtocol {
  private struct Request {
    var continuation: CheckedContinuation<HomeRoutineServerEnrichment, Error>?
    var task: Task<Void, Never>?
  }

  private var requests: [Request] = []

  func execute(
    localResult: HomeRoutineLoadResult
  ) async throws -> HomeRoutineServerEnrichment {
    let index = requests.count
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        requests.append(Request(continuation: continuation, task: nil))
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.markCancelled(at: index)
      }
    }
  }

  func waitForRequestCount(_ count: Int) async {
    while requests.count < count {
      await Task.yield()
    }
  }

  func wasCancelled(at index: Int) -> Bool {
    requests[index].task != nil
  }

  func resume(
    at index: Int,
    returning result: HomeRoutineServerEnrichment
  ) {
    requests[index].continuation?.resume(returning: result)
    requests[index].continuation = nil
  }

  private func markCancelled(at index: Int) {
    guard requests.indices.contains(index) else { return }
    requests[index].task = Task {}
  }
}
