//
//  RoutineSyncCRUDIntegrationTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class RoutineSyncCRUDIntegrationTests: XCTestCase {
  @MainActor
  func testSignedInCreateCoalescesFullSnapshotAndInactiveCreateHasNoActiveSelection() throws {
    let fixture = try makeFixture(memberID: 7)
    let firstStep = makeStep(title: "물 마시기", order: 0)
    var routine = makeRoutine(
      name: "아침",
      steps: [firstStep],
      isActive: false
    )

    try fixture.routines.saveRoutine(routine)

    var mutations = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(mutations.count, 1)
    XCTAssertEqual(mutations[0].operation, .createRoutineGroup)
    XCTAssertEqual(mutations[0].state, .waitingForServerContract)
    XCTAssertEqual(
      try decodedCommand(mutations[0]),
      .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
    )

    routine.name = "더 좋은 아침"
    routine.steps.append(makeStep(title: "창문 열기", order: 1))
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)

    mutations = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(mutations.count, 1)
    XCTAssertEqual(
      try decodedCommand(mutations[0]),
      .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
    )
  }

  @MainActor
  func testLoginBackfillStagesSignedOutLocalGroupAndReusesGeneration() throws {
    let fixture = try makeFixture(memberID: nil)
    let routine = makeRoutine(name: "로컬", steps: [makeStep()], isActive: false)
    try fixture.routines.saveRoutine(routine)
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)

    fixture.member.signedInMemberID = 7
    let backfiller = RoutineSyncLoginBackfiller(
      routineRepository: fixture.routines,
      syncRepository: fixture.sync
    )
    try backfiller.backfillLocalRoutineGroups(
      memberID: 7,
      at: Date(timeIntervalSince1970: 20)
    )

    let first = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    XCTAssertEqual(first.operation, .createRoutineGroup)
    XCTAssertEqual(first.localEntityID, routine.id)
    XCTAssertEqual(
      try decodedCommand(first),
      .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
    )

    try backfiller.backfillLocalRoutineGroups(
      memberID: 7,
      at: Date(timeIntervalSince1970: 30)
    )

    let repeated = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(repeated.count, 1)
    XCTAssertEqual(repeated[0].id, first.id)
    XCTAssertEqual(repeated[0].generationID, first.generationID)
    XCTAssertEqual(repeated[0].generation, first.generation)
  }

  @MainActor
  func testLoginBackfillStagesOnboardingCompletionForCompletedLocalOnboarding()
    throws {
    let fixture = try makeFixture(memberID: nil)
    let routine = makeRoutine(
      name: "로컬 온보딩",
      steps: [makeStep()],
      isActive: false
    )
    let profile = LocalProfile()
    try fixture.onboarding.saveCompletion(profile: profile, routine: routine)
    fixture.member.signedInMemberID = 7
    let profileRepository = SwiftDataLocalProfileRepository(
      modelContext: fixture.container.mainContext
    )

    try RoutineSyncLoginBackfiller(
      routineRepository: fixture.routines,
      localProfileRepository: profileRepository,
      syncRepository: fixture.sync
    ).backfillLocalRoutineGroups(memberID: 7, at: .distantPast)

    let completion = try XCTUnwrap(
      try fixture.sync.mutations(memberID: 7).first {
        $0.operation == .completeOnboarding
      }
    )
    XCTAssertEqual(
      try decodedCommand(completion),
      .completeOnboarding(groupLocalID: routine.id)
    )
  }

  @MainActor
  func testLoginBackfillSkipsGroupAlreadyBoundToMember() throws {
    let fixture = try makeFixture(memberID: nil)
    let routine = makeRoutine(
      name: "이미 업로드됨",
      steps: [makeStep()],
      isActive: false
    )
    try fixture.routines.saveRoutine(routine)
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id
    )

    try RoutineSyncLoginBackfiller(
      routineRepository: fixture.routines,
      syncRepository: fixture.sync
    ).backfillLocalRoutineGroups(memberID: 7, at: .distantPast)

    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testLoginBackfillStagesNewestActiveGroupSelectionAfterCreates() throws {
    let fixture = try makeFixture(memberID: nil)
    var older = makeRoutine(
      name: "이전 활성 루틴",
      steps: [makeStep()],
      isActive: true
    )
    older.updatedAt = Date(timeIntervalSince1970: 20)
    var newer = makeRoutine(
      name: "최신 활성 루틴",
      steps: [makeStep()],
      isActive: true
    )
    newer.updatedAt = Date(timeIntervalSince1970: 30)
    try fixture.routines.saveRoutines([older, newer])

    try RoutineSyncLoginBackfiller(
      routineRepository: fixture.routines,
      syncRepository: fixture.sync
    ).backfillLocalRoutineGroups(memberID: 7, at: .distantPast)

    let mutations = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(
      mutations.filter { $0.operation == .createRoutineGroup }.count,
      2
    )
    let selection = try XCTUnwrap(
      mutations.first { $0.operation == .setRoutineGroupActive }
    )
    XCTAssertEqual(
      try decodedCommand(selection),
      .selectActiveRoutineGroup(selectedGroupLocalID: newer.id)
    )
  }

  @MainActor
  func testLoginBackfillFlowsThroughProductionPostAndSettlesBindings()
    async throws {
    let fixture = try makeFixture(memberID: nil)
    let step = makeStep()
    let routine = makeRoutine(
      name: "로그인 업로드",
      steps: [step],
      isActive: false
    )
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7

    let response = Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON201",
        "message": "Created",
        "result": {
          "routineGroupId": 41,
          "clientEntityId": "\(routine.id.uuidString.lowercased())",
          "routines": [
            {
              "routineId": 51,
              "clientEntityId": "\(step.id.uuidString.lowercased())",
              "type": "CHECK"
            }
          ]
        }
      }
      """.utf8
    )
    let apiClient = RoutineSyncBackfillAPIClient(response: response)
    let identity = AccountSessionIdentity(memberID: 7, sessionID: UUID())
    let identityProvider = RoutineSyncRuntimeIdentityProvider(
      identity: identity
    )
    let sender = RoutineSyncSender(
      repository: fixture.sync,
      requestPreparer: ProductionRoutineSyncRequestPreparer(
        repository: fixture.sync
      ),
      transport: ProductionRoutineSyncTransport(
        apiClient: apiClient,
        responseDecoder: ProductionRoutineSyncResponseDecoder()
      ),
      contract: .productionP0,
      sessionIdentityProvider: identityProvider,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: identityProvider,
      loginBackfiller: RoutineSyncLoginBackfiller(
        routineRepository: fixture.routines,
        syncRepository: fixture.sync
      ),
      isSceneActive: true
    )

    coordinator.wake()
    await waitUntilStopped(coordinator)

    let capturedRequest = await apiClient.capturedRequest()
    let capture = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(capture.identity, identity)
    XCTAssertEqual(capture.path, "/routine-groups")
    XCTAssertNotNil(UUID(uuidString: capture.idempotencyKey))
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: capture.body) as? [String: Any]
    )
    XCTAssertEqual(
      body["clientEntityId"] as? String,
      routine.id.uuidString.lowercased()
    )
    let routines = try XCTUnwrap(body["routines"] as? [[String: Any]])
    XCTAssertEqual(
      routines.first?["clientEntityId"] as? String,
      step.id.uuidString.lowercased()
    )
    XCTAssertEqual(
      try fixture.sync.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: routine.id
      )?.remoteID,
      41
    )
    XCTAssertEqual(
      try fixture.sync.binding(
        memberID: 7,
        entityKind: .routine,
        localEntityID: step.id
      )?.remoteID,
      51
    )
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(coordinator.lastStopReason, .some(.idle))
  }

  @MainActor
  func testGuestCreateThenCancelledLoginAccountEventKeepsOutboxAndTransportEmpty()
    async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let session = RoutineSyncCRUDSessionProvider(identity: nil)
    let sync = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    let relay = RoutineSyncWakeupRelay()
    let routines = SwiftDataRoutineRepository(
      modelContext: container.mainContext,
      routineSyncRepository: sync,
      signedInMemberProvider: session,
      routineSyncWakeupRelay: relay
    )
    let transport = RoutineSyncCRUDTransportProbe()
    let sender = RoutineSyncSender(
      repository: sync,
      requestPreparer: ProductionRoutineSyncRequestPreparer(repository: sync),
      transport: transport,
      contract: .productionP0,
      sessionIdentityProvider: session,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: session,
      wakeupRelay: relay,
      isSceneActive: true
    )

    try routines.saveRoutine(
      makeRoutine(name: "게스트 생성", steps: [makeStep()], isActive: false)
    )

    // A cancelled or failed login has no successful identity transition. An
    // account event alone must not turn the guest save into an implicit upload.
    coordinator.accountSessionDidChange()
    await waitUntilStopped(coordinator)

    XCTAssertTrue(
      try container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineSyncMutation>()
      ).isEmpty
    )
    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)
    let requestCount = await transport.requestCount()
    XCTAssertEqual(requestCount, 0)
    XCTAssertEqual(coordinator.lastStopReason, .some(.signedOut))
  }

  @MainActor
  func testPersistedGuestCreateStaysLocalAfterSignedOutRuntimeGraphRecreation()
    async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("moru.store")
    let routineID = try persistGuestRoutine(to: storeURL)

    let reopenedContainer = try ModelContainer.moruContainer(storeURL: storeURL)
    let session = RoutineSyncCRUDSessionProvider(identity: nil)
    let reopenedSync = SwiftDataRoutineSyncRepository(
      modelContext: reopenedContainer.mainContext
    )
    let reopenedRoutines = SwiftDataRoutineRepository(
      modelContext: reopenedContainer.mainContext,
      routineSyncRepository: reopenedSync,
      signedInMemberProvider: session
    )
    let transport = RoutineSyncCRUDTransportProbe()
    let sender = RoutineSyncSender(
      repository: reopenedSync,
      requestPreparer: ProductionRoutineSyncRequestPreparer(
        repository: reopenedSync
      ),
      transport: transport,
      contract: .productionP0,
      sessionIdentityProvider: session,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let coordinator = RoutineSyncRuntimeCoordinator(
      sender: sender,
      sessionIdentityProvider: session,
      isSceneActive: true
    )

    XCTAssertNotNil(try reopenedRoutines.routine(id: routineID))
    coordinator.accountSessionDidChange()
    await waitUntilStopped(coordinator)

    // Reopening SwiftData and rebuilding the signed-out runtime graph must not
    // itself scan a signed-out guest routine into a new create mutation.
    XCTAssertTrue(
      try reopenedContainer.mainContext.fetch(
        FetchDescriptor<PersistedRoutineSyncMutation>()
      ).isEmpty
    )
    XCTAssertTrue(try reopenedSync.mutations(memberID: 7).isEmpty)
    let requestCount = await transport.requestCount()
    XCTAssertEqual(requestCount, 0)
    XCTAssertEqual(coordinator.lastStopReason, .some(.signedOut))
  }

  @MainActor
  func testUnsentActiveGroupDeletionCancelsCreateAndSelectionWithoutNilReplacement() throws {
    let fixture = try makeFixture(memberID: 7)
    let step = makeStep()
    let routine = makeRoutine(name: "보낼 예정", steps: [step], isActive: true)
    try fixture.routines.saveRoutine(routine)
    XCTAssertEqual(try fixture.sync.mutations(memberID: 7).count, 2)

    let run = RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 10),
      completedAt: Date(timeIntervalSince1970: 20),
      results: [
        RoutineStepResult(
          stepID: step.id,
          stepTitle: step.title,
          stepType: step.type,
          completedAt: Date(timeIntervalSince1970: 20)
        )
      ]
    )
    try fixture.runs.saveRun(run)
    XCTAssertEqual(try fixture.sync.mutations(memberID: 7).count, 3)

    try fixture.routines.deleteRoutine(id: routine.id)

    XCTAssertNil(try fixture.routines.routine(id: routine.id))
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testNeverAttemptedBlockedCreateDoesNotRollbackLocalDeletion() throws {
    let fixture = try makeFixture(memberID: 7)
    let routine = makeRoutine(
      name: "invalid server snapshot",
      steps: [makeStep()],
      isActive: false
    )
    try fixture.routines.saveRoutine(routine)
    let create = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    try fixture.sync.blockAttempt(
      id: create.id,
      expectedGenerationID: create.generationID,
      reason: .invalidStoredRequest,
      at: Date(timeIntervalSince1970: 10)
    )
    let blocked = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    XCTAssertEqual(blocked.state, .blocked)
    XCTAssertNil(blocked.attempt)

    try fixture.routines.deleteRoutine(id: routine.id)

    XCTAssertNil(try fixture.routines.routine(id: routine.id))
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testAttemptedBlockedCreatePreservesDependentDeleteWithoutLocalRollback()
    throws {
    let fixture = try makeFixture(memberID: 7)
    let routine = makeRoutine(
      name: "ambiguous remote create",
      steps: [makeStep()],
      isActive: false
    )
    try fixture.routines.saveRoutine(routine)
    let create = try XCTUnwrap(
      try fixture.sync.admitEligibleMutations(
        memberID: 7,
        contract: .productionP0,
        at: Date(timeIntervalSince1970: 10)
      ).first
    )
    let command = try decodedCommand(create)
    let wire = try ProductionRoutineSyncRequestPreparer(
      repository: fixture.sync
    ).makeWireRequest(for: command, mutation: create)
    let attempt = try XCTUnwrap(
      fixture.sync.claimForDelivery(
        id: create.id,
        wireRequest: wire,
        at: Date(timeIntervalSince1970: 11)
      )
    )
    try fixture.sync.blockAttempt(
      id: create.id,
      expectedGenerationID: attempt.generationID,
      reason: .resultTTLExpired,
      at: Date(timeIntervalSince1970: 12)
    )

    try fixture.routines.deleteRoutine(id: routine.id)

    XCTAssertNil(try fixture.routines.routine(id: routine.id))
    let remaining = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(
      Set(remaining.map(\.operation)),
      [.createRoutineGroup, .deleteRoutineGroup]
    )
    XCTAssertEqual(
      remaining.first { $0.operation == .createRoutineGroup }?.state,
      .blocked
    )
    XCTAssertNotNil(
      remaining.first { $0.operation == .createRoutineGroup }?.attempt
    )
  }

  @MainActor
  func testRemovingChildFromPendingCreateCoalescesSnapshotAndCancelsExecution() throws {
    let fixture = try makeFixture(memberID: 7)
    let retainedStep = makeStep(title: "유지", order: 0)
    let removedStep = makeStep(title: "삭제", order: 1)
    var routine = makeRoutine(
      name: "생성 중",
      steps: [retainedStep, removedStep],
      isActive: false
    )
    try fixture.routines.saveRoutine(routine)
    let run = RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 10),
      completedAt: Date(timeIntervalSince1970: 20),
      results: [
        RoutineStepResult(
          stepID: removedStep.id,
          stepTitle: removedStep.title,
          stepType: removedStep.type,
          completedAt: Date(timeIntervalSince1970: 20)
        )
      ]
    )
    try fixture.runs.saveRun(run)
    XCTAssertEqual(
      Set(try fixture.sync.mutations(memberID: 7).map(\.operation)),
      [.createRoutineGroup, .saveRoutineExecution]
    )

    routine.steps.removeAll { $0.id == removedStep.id }
    routine.updatedAt = Date(timeIntervalSince1970: 30)
    try fixture.routines.saveRoutine(routine)

    let mutations = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(mutations.map(\.operation), [.createRoutineGroup])
    XCTAssertEqual(
      try decodedCommand(XCTUnwrap(mutations.first)),
      .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
    )
  }

  @MainActor
  func testBoundGroupStagesAddCancelAndDeleteChildThenDeleteGroup() throws {
    let fixture = try makeFixture(memberID: nil)
    let existingStep = makeStep(title: "기존", order: 0)
    var routine = makeRoutine(name: "바인딩", steps: [existingStep], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id,
      at: Date(timeIntervalSince1970: 10)
    )

    let newStep = makeStep(title: "새 단계", order: 1)
    routine.steps.append(newStep)
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)
    XCTAssertEqual(
      try fixture.sync.mutations(memberID: 7).map(\.operation),
      [.addRoutine]
    )

    routine.steps[1].title = "수정한 새 단계"
    routine.steps[1].estimatedSeconds = 30
    routine.updatedAt = Date(timeIntervalSince1970: 25)
    try fixture.routines.saveRoutine(routine)
    let coalescedAdd = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    XCTAssertEqual(
      try decodedCommand(coalescedAdd),
      .addRoutine(
        groupLocalID: routine.id,
        routine: RoutineSyncRoutineSnapshot(step: routine.steps[1])
      )
    )

    routine.steps.removeAll { $0.id == newStep.id }
    routine.updatedAt = Date(timeIntervalSince1970: 30)
    try fixture.routines.saveRoutine(routine)
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)

    _ = try fixture.sync.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: existingStep.id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: routine.id
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 40)
    )
    routine.steps.removeAll { $0.id == existingStep.id }
    routine.updatedAt = Date(timeIntervalSince1970: 50)
    try fixture.routines.saveRoutine(routine)
    XCTAssertEqual(
      try fixture.sync.mutations(memberID: 7).map(\.operation),
      [.deleteRoutine]
    )

    try fixture.routines.deleteRoutine(id: routine.id)
    XCTAssertTrue(
      try fixture.sync.mutations(memberID: 7).map(\.operation).contains(.deleteRoutineGroup)
    )
  }

  @MainActor
  func testDeletingUnsentChildCancelsPendingAddAndItsExecution() throws {
    let fixture = try makeFixture(memberID: nil)
    let existingStep = makeStep(title: "기존", order: 0)
    var routine = makeRoutine(name: "바인딩", steps: [existingStep], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id,
      at: Date(timeIntervalSince1970: 10)
    )

    let addedStep = makeStep(title: "추가", order: 1)
    routine.steps.append(addedStep)
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)
    let run = RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 20),
      completedAt: Date(timeIntervalSince1970: 30),
      results: [
        RoutineStepResult(
          stepID: addedStep.id,
          stepTitle: addedStep.title,
          stepType: addedStep.type,
          completedAt: Date(timeIntervalSince1970: 30)
        )
      ]
    )
    try fixture.runs.saveRun(run)
    XCTAssertEqual(
      Set(try fixture.sync.mutations(memberID: 7).map(\.operation)),
      [.addRoutine, .saveRoutineExecution]
    )

    routine.steps.removeAll { $0.id == addedStep.id }
    routine.updatedAt = Date(timeIntervalSince1970: 40)
    try fixture.routines.saveRoutine(routine)

    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testUnsupportedRoutineEditsStayLocalOnly() throws {
    let fixture = try makeFixture(memberID: nil)
    let step = makeStep(title: "기존", order: 0)
    var routine = makeRoutine(name: "원래 이름", steps: [step], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: routine.id,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: step.id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: routine.id
        ),
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 10)
    )

    routine.name = "바뀐 이름"
    routine.summary = "서버 PATCH 없는 설명"
    routine.steps[0].title = "바뀐 단계"
    routine.steps[0].order = 4
    routine.alarmSchedule = AlarmSchedule(
      hour: 7,
      minute: 30,
      weekdays: [.monday],
      includeWeather: true
    )
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)

    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(try fixture.routines.routine(id: routine.id), routine)
  }

  @MainActor
  func testWrongParentStepBindingDoesNotStageDeleteForAnotherGroup() throws {
    let fixture = try makeFixture(memberID: nil)
    let step = makeStep()
    var routine = makeRoutine(name: "첫 그룹", steps: [step], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: routine.id,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: step.id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: UUID()
        ),
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 10)
    )

    routine.steps = []
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)

    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testNewStepWithBindingToAnotherGroupRollsBackLocalSave() throws {
    let fixture = try makeFixture(memberID: nil)
    var routine = makeRoutine(name: "첫 그룹", steps: [makeStep()], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id,
      at: Date(timeIntervalSince1970: 10)
    )
    let conflictingStep = makeStep(title: "다른 그룹 단계", order: 1)
    _ = try fixture.sync.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: conflictingStep.id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: UUID()
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 11)
    )
    routine.steps.append(conflictingStep)
    routine.updatedAt = Date(timeIntervalSince1970: 20)

    XCTAssertThrowsError(try fixture.routines.saveRoutine(routine)) { error in
      XCTAssertEqual(error as? RoutineSyncRepositoryError, .invalidParentBinding)
    }
    XCTAssertEqual(try fixture.routines.routine(id: routine.id)?.steps.count, 1)
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testBoundActiveChangesCoalesceToOneAccountSelection() throws {
    let fixture = try makeFixture(memberID: nil)
    var first = makeRoutine(name: "첫째", steps: [makeStep()], isActive: false)
    var second = makeRoutine(name: "둘째", steps: [makeStep()], isActive: false)
    try fixture.routines.saveRoutines([first, second])
    fixture.member.signedInMemberID = 7
    for (localID, remoteID) in [(first.id, Int64(41)), (second.id, Int64(42))] {
      _ = try fixture.sync.recordRemoteID(
        remoteID,
        revision: nil,
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: localID,
        at: Date(timeIntervalSince1970: 10)
      )
    }

    first.isActive = true
    first.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(first)
    first.isActive = false
    first.updatedAt = Date(timeIntervalSince1970: 30)
    second.isActive = true
    second.updatedAt = Date(timeIntervalSince1970: 31)
    try fixture.routines.saveRoutines([first, second])

    let mutations = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(mutations.count, 1)
    XCTAssertEqual(
      try decodedCommand(mutations[0]),
      .selectActiveRoutineGroup(selectedGroupLocalID: second.id)
    )
  }

  @MainActor
  func testActiveSelectionKeepsNewestServerProjectableRoutine() throws {
    let fixture = try makeFixture(memberID: nil)
    var boundRoutine = makeRoutine(
      name: "서버 연결 루틴",
      steps: [makeStep()],
      isActive: false
    )
    var localOnlyRoutine = makeRoutine(
      name: "로컬 전용 루틴",
      steps: [makeStep()],
      isActive: false
    )
    try fixture.routines.saveRoutines([boundRoutine, localOnlyRoutine])

    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: boundRoutine.id
    )

    boundRoutine.isActive = true
    boundRoutine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(boundRoutine)

    localOnlyRoutine.isActive = true
    localOnlyRoutine.updatedAt = Date(timeIntervalSince1970: 30)
    try fixture.routines.saveRoutine(localOnlyRoutine)

    boundRoutine.isActive = false
    boundRoutine.updatedAt = Date(timeIntervalSince1970: 24)
    try fixture.routines.saveRoutine(boundRoutine)
    boundRoutine.isActive = true
    boundRoutine.updatedAt = Date(timeIntervalSince1970: 25)
    try fixture.routines.saveRoutine(boundRoutine)

    let selection = try XCTUnwrap(
      try fixture.sync.mutation(
        memberID: 7,
        operation: .setRoutineGroupActive,
        entityKind: .account,
        localEntityID: RoutineSyncCommand.accountSelectionID
      )
    )
    XCTAssertEqual(
      try decodedCommand(selection),
      .selectActiveRoutineGroup(selectedGroupLocalID: boundRoutine.id)
    )
  }

  @MainActor
  func testExecutionStagesPerResultForProjectableGroupAndDoesNotBackfillLegacyRun() throws {
    let fixture = try makeFixture(memberID: nil)
    let step = makeStep(title: "확인", order: 0)
    let routine = makeRoutine(name: "실행", steps: [step], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7

    let result = RoutineStepResult(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: Date(timeIntervalSince1970: 20),
      inputText: "비공개 입력",
      transcript: "비공개 전사",
      durationSeconds: 12
    )
    let run = RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 10),
      completedAt: Date(timeIntervalSince1970: 20),
      results: [result]
    )
    try fixture.runs.saveRun(run)
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)

    _ = try fixture.sync.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: step.id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: UUID()
        )
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 25)
    )
    let wrongParentResult = RoutineStepResult(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: Date(timeIntervalSince1970: 22),
      durationSeconds: 12
    )
    let wrongParentRun = RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 21),
      completedAt: Date(timeIntervalSince1970: 22),
      results: [wrongParentResult]
    )
    try fixture.runs.saveRun(wrongParentRun)
    XCTAssertTrue(try fixture.sync.mutations(memberID: 7).isEmpty)

    // This explicit new create is projectable, unlike the legacy local group.
    try fixture.routines.deleteRoutine(id: routine.id)
    let projectableRoutine = makeRoutine(name: "새 실행", steps: [step], isActive: false)
    try fixture.routines.saveRoutine(projectableRoutine)
    let projectableResult = RoutineStepResult(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: Date(timeIntervalSince1970: 30),
      inputText: "비공개 입력",
      transcript: "비공개 전사",
      durationSeconds: 12
    )
    var projectableRun = RoutineRun(
      routine: projectableRoutine,
      startedAt: Date(timeIntervalSince1970: 25),
      completedAt: Date(timeIntervalSince1970: 30),
      results: [projectableResult]
    )
    try fixture.runs.saveRun(projectableRun)

    let execution = try XCTUnwrap(
      try fixture.sync.mutations(memberID: 7).first {
        $0.operation == .saveRoutineExecution
      }
    )
    XCTAssertEqual(execution.localEntityID, projectableResult.id)
    XCTAssertEqual(execution.state, .waitingForServerContract)
    XCTAssertEqual(
      try decodedCommand(execution),
      .saveRoutineExecution(
        RoutineSyncExecutionSnapshot(
          run: projectableRun,
          result: projectableResult,
          timeZone: .current
        )
      )
    )

    projectableRun.results[0].transcript = "수정된 전사"
    try fixture.runs.saveRun(projectableRun)
    let executions = try fixture.sync.mutations(memberID: 7).filter {
      $0.operation == .saveRoutineExecution
    }
    XCTAssertEqual(executions.count, 1)
    XCTAssertEqual(executions[0].localEntityID, projectableResult.id)

    projectableRun.results = []
    try fixture.runs.saveRun(projectableRun)
    XCTAssertEqual(
      try fixture.sync.mutations(memberID: 7).filter { $0.operation == .saveRoutineExecution }.count,
      1
    )
  }

  @MainActor
  func testDeletingGroupDuringCreateAttemptKeepsLocalDeleteAndStagesSuccessor() throws {
    let fixture = try makeFixture(memberID: 7)
    let routine = makeRoutine(name: "보류", steps: [makeStep()], isActive: false)
    try fixture.routines.saveRoutine(routine)
    let mutation = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    _ = try fixture.sync.admitEligibleMutations(
      memberID: 7,
      contract: verifiedServerContract,
      at: Date(timeIntervalSince1970: 20)
    )
    _ = try XCTUnwrap(
      fixture.sync.claimForDelivery(
        id: mutation.id,
        at: Date(timeIntervalSince1970: 21)
      )
    )

    try fixture.routines.deleteRoutine(id: routine.id)

    XCTAssertNil(try fixture.routines.routine(id: routine.id))
    let remaining = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(Set(remaining.map(\.operation)), [.createRoutineGroup, .deleteRoutineGroup])
    XCTAssertEqual(
      remaining.first { $0.operation == .createRoutineGroup }?.state,
      .attempting
    )
    XCTAssertEqual(
      remaining.first { $0.operation == .deleteRoutineGroup }?.state,
      .waitingForServerContract
    )
  }

  @MainActor
  func testDeletingChildDuringAddAttemptStagesDeleteAfterAdd() throws {
    let fixture = try makeFixture(memberID: nil)
    let retained = makeStep(title: "기존", order: 0)
    var routine = makeRoutine(name: "그룹", steps: [retained], isActive: false)
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id,
      at: Date(timeIntervalSince1970: 10)
    )
    let added = makeStep(title: "추가 중", order: 1)
    routine.steps.append(added)
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)
    let add = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    _ = try fixture.sync.admitEligibleMutations(
      memberID: 7,
      contract: verifiedServerContract,
      at: Date(timeIntervalSince1970: 21)
    )
    _ = try XCTUnwrap(
      fixture.sync.claimForDelivery(id: add.id, at: Date(timeIntervalSince1970: 22))
    )

    routine.steps.removeAll { $0.id == added.id }
    routine.updatedAt = Date(timeIntervalSince1970: 30)
    try fixture.routines.saveRoutine(routine)

    XCTAssertEqual(try fixture.routines.routine(id: routine.id)?.steps, [retained])
    let remaining = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(Set(remaining.map(\.operation)), [.addRoutine, .deleteRoutine])
    XCTAssertEqual(remaining.first { $0.operation == .addRoutine }?.state, .attempting)
    XCTAssertEqual(
      remaining.first { $0.operation == .deleteRoutine }?.state,
      .waitingForServerContract
    )
  }

  @MainActor
  func testAttemptedBlockedAddPreservesChildDeleteWithoutLocalRollback()
    throws {
    let fixture = try makeFixture(memberID: nil)
    let retained = makeStep(title: "existing", order: 0)
    var routine = makeRoutine(
      name: "bound group",
      steps: [retained],
      isActive: false
    )
    try fixture.routines.saveRoutine(routine)
    fixture.member.signedInMemberID = 7
    _ = try fixture.sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id,
      at: Date(timeIntervalSince1970: 10)
    )
    let added = makeStep(title: "ambiguous add", order: 1)
    routine.steps.append(added)
    try fixture.routines.saveRoutine(routine)
    let add = try XCTUnwrap(
      try fixture.sync.admitEligibleMutations(
        memberID: 7,
        contract: .productionP0,
        at: Date(timeIntervalSince1970: 20)
      ).first
    )
    let command = try decodedCommand(add)
    let wire = try ProductionRoutineSyncRequestPreparer(
      repository: fixture.sync
    ).makeWireRequest(for: command, mutation: add)
    let attempt = try XCTUnwrap(
      fixture.sync.claimForDelivery(
        id: add.id,
        wireRequest: wire,
        at: Date(timeIntervalSince1970: 21)
      )
    )
    try fixture.sync.blockAttempt(
      id: add.id,
      expectedGenerationID: attempt.generationID,
      reason: .unknownConflict,
      at: Date(timeIntervalSince1970: 22)
    )

    routine.steps.removeAll { $0.id == added.id }
    try fixture.routines.saveRoutine(routine)

    XCTAssertEqual(try fixture.routines.routine(id: routine.id)?.steps, [retained])
    let remaining = try fixture.sync.mutations(memberID: 7)
    XCTAssertEqual(Set(remaining.map(\.operation)), [.addRoutine, .deleteRoutine])
    XCTAssertEqual(
      remaining.first { $0.operation == .addRoutine }?.state,
      .blocked
    )
  }

  @MainActor
  func testPartialCreateMappingRejectsWithoutChangingLatestCRUDChildGraph() throws {
    let fixture = try makeFixture(memberID: 7)
    let original = makeStep(title: "원래", order: 0)
    var routine = makeRoutine(name: "부분 매핑", steps: [original], isActive: false)
    try fixture.routines.saveRoutine(routine)
    let create = try XCTUnwrap(try fixture.sync.mutations(memberID: 7).first)
    _ = try fixture.sync.admitEligibleMutations(
      memberID: 7,
      contract: verifiedServerContract,
      at: Date(timeIntervalSince1970: 10)
    )
    _ = try XCTUnwrap(
      fixture.sync.claimForDelivery(id: create.id, at: Date(timeIntervalSince1970: 11))
    )
    XCTAssertThrowsError(
      try fixture.sync.completeCreateRoutineGroup(
        id: create.id,
        expectedGenerationID: create.generationID,
        assignments: [
          RoutineServerBindingAssignment(
            entityKind: .routineGroup,
            localEntityID: routine.id,
            remoteID: 41
          )
        ],
        childMappingsComplete: false,
        at: Date(timeIntervalSince1970: 12)
      )
    ) { error in
      XCTAssertEqual(
        error as? RoutineSyncRepositoryError,
        .incompleteChildMapping
      )
    }

    let added = makeStep(title: "나중 추가", order: 1)
    routine.steps.append(added)
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try fixture.routines.saveRoutine(routine)
    let reconciled = try XCTUnwrap(
      try fixture.sync.mutation(
        memberID: 7,
        operation: .createRoutineGroup,
        entityKind: .routineGroup,
        localEntityID: routine.id
      )
    )
    XCTAssertEqual(reconciled.state, .attempting)
    XCTAssertEqual(
      try decodedCommand(reconciled),
      .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
    )
  }

  @MainActor
  func testOnboardingSignedInStagesInitialCreateWithoutNetworkDependency() throws {
    let fixture = try makeFixture(memberID: 7)
    let routine = makeRoutine(name: "온보딩", steps: [makeStep()], isActive: false)

    try fixture.onboarding.saveCompletion(profile: LocalProfile(), routine: routine)

    let mutations = try fixture.sync.mutations(memberID: 7)
    let create = try XCTUnwrap(
      mutations.first { $0.operation == .createRoutineGroup }
    )
    let completion = try XCTUnwrap(
      mutations.first { $0.operation == .completeOnboarding }
    )
    XCTAssertEqual(create.state, .waitingForServerContract)
    XCTAssertEqual(completion.state, .waitingForServerContract)
    XCTAssertEqual(
      try decodedCommand(completion),
      .completeOnboarding(groupLocalID: routine.id)
    )
  }

  @MainActor
  func testOnboardingActiveRoutineDeactivatesExistingActiveRoutineInSameSave() throws {
    let fixture = try makeFixture(memberID: nil)
    let weekdays: [Weekday] = [.monday, .wednesday]
    let existing = Routine(
      name: "기존 활성",
      steps: [makeStep()],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 0,
        weekdays: weekdays,
        isEnabled: true
      ),
      isActive: true
    )
    try fixture.routines.saveRoutine(existing)
    fixture.member.signedInMemberID = 7
    let onboarding = makeRoutine(name: "온보딩 활성", steps: [makeStep()], isActive: true)

    try fixture.onboarding.saveCompletion(profile: LocalProfile(), routine: onboarding)

    let old = try XCTUnwrap(try fixture.routines.routine(id: existing.id))
    XCTAssertFalse(old.isActive)
    XCTAssertEqual(old.alarmSchedule?.weekdays, weekdays)
    XCTAssertFalse(old.alarmSchedule?.isEnabled ?? true)
    XCTAssertTrue(try fixture.routines.routine(id: onboarding.id)?.isActive ?? false)
    XCTAssertEqual(
      try fixture.sync.mutations(memberID: 7).map(\.operation).sorted { $0.rawValue < $1.rawValue },
      [.createRoutineGroup, .setRoutineGroupActive, .completeOnboarding]
        .sorted { $0.rawValue < $1.rawValue }
    )
  }

  @MainActor
  func testStageCancelActiveSelectionRejectsInvalidMember() throws {
    let fixture = try makeFixture(memberID: 7)
    XCTAssertThrowsError(
      try fixture.sync.stageCancelActiveSelection(
        memberID: 0,
        selectedGroupLocalID: UUID()
      )
    ) { error in
      XCTAssertEqual(error as? RoutineSyncRepositoryError, .invalidMemberID)
    }
  }

  @MainActor
  func testProductionDependencyGraphStagesCRUDWithoutCallingInjectedRoutineRemoteAPI() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let member = RoutineSyncCRUDMemberProvider(memberID: 7)
    let apiClient = RoutineSyncCountingAPIClient()
    let remoteService = DefaultAccountRoutineGroupRemoteService(apiClient: apiClient)
    let dependencies = DependencyContainer.local(
      modelContext: container.mainContext,
      signedInMemberProvider: member,
      accountRoutineGroupRemoteService: remoteService
    )
    let step = makeStep(title: "원격 호출 없음", order: 0)
    var routine = makeRoutine(name: "생성", steps: [step], isActive: false)

    try dependencies.routineRepository.saveRoutine(routine)
    routine.name = "일반 편집"
    routine.updatedAt = Date(timeIntervalSince1970: 20)
    try dependencies.routineRepository.saveRoutine(routine)
    let run = RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 20),
      completedAt: Date(timeIntervalSince1970: 30),
      results: [
        RoutineStepResult(
          stepID: step.id,
          stepTitle: step.title,
          stepType: step.type,
          completedAt: Date(timeIntervalSince1970: 30)
        )
      ]
    )
    try dependencies.routineRunRepository.saveRun(run)

    let sync = try XCTUnwrap(dependencies.routineSyncRepository)
    let stagedBeforeDelete = try sync.mutations(memberID: 7)
    XCTAssertFalse(stagedBeforeDelete.isEmpty)
    XCTAssertTrue(stagedBeforeDelete.allSatisfy { $0.state == .waitingForServerContract })

    try dependencies.routineRepository.deleteRoutine(id: routine.id)

    let requestCount = await apiClient.requestCount()
    XCTAssertEqual(requestCount, 0)
    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testRepositoryWakeHappensOnlyAfterSuccessfulSwiftDataCommit() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let member = RoutineSyncCRUDMemberProvider(memberID: nil)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let relay = RoutineSyncWakeupRelay()
    let probe = RoutineSyncWakeProbe()
    relay.setHandler {
      probe.count += 1
      let verificationContext = ModelContext(container)
      probe.persistedRoutineCount = (try? verificationContext.fetch(
        FetchDescriptor<PersistedRoutine>()
      ).count) ?? -1
    }
    let repository = SwiftDataRoutineRepository(
      modelContext: container.mainContext,
      routineSyncRepository: sync,
      signedInMemberProvider: member,
      routineSyncWakeupRelay: relay
    )
    var routine = makeRoutine(
      name: "commit-before-wake",
      steps: [makeStep()],
      isActive: false
    )

    try repository.saveRoutine(routine)
    XCTAssertEqual(probe.count, 1)
    XCTAssertEqual(probe.persistedRoutineCount, 1)

    member.signedInMemberID = 7
    _ = try sync.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: routine.id
    )
    let conflictingStep = makeStep(title: "conflict", order: 1)
    _ = try sync.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: conflictingStep.id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: UUID()
        )
      ],
      memberID: 7
    )
    routine.steps.append(conflictingStep)

    XCTAssertThrowsError(try repository.saveRoutine(routine))
    XCTAssertEqual(probe.count, 1)
    XCTAssertEqual(try repository.routine(id: routine.id)?.steps.count, 1)
  }

  @MainActor
  private func makeFixture(memberID: Int64?) throws -> RoutineSyncCRUDFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let member = RoutineSyncCRUDMemberProvider(memberID: memberID)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    return RoutineSyncCRUDFixture(
      container: container,
      member: member,
      sync: sync,
      routines: SwiftDataRoutineRepository(
        modelContext: container.mainContext,
        routineSyncRepository: sync,
        signedInMemberProvider: member
      ),
      runs: SwiftDataRoutineRunRepository(
        modelContext: container.mainContext,
        routineSyncRepository: sync,
        signedInMemberProvider: member
      ),
      onboarding: SwiftDataOnboardingRepository(
        modelContext: container.mainContext,
        routineSyncRepository: sync,
        signedInMemberProvider: member
      )
    )
  }

  @MainActor
  private func persistGuestRoutine(to storeURL: URL) throws -> UUID {
    let container = try ModelContainer.moruContainer(storeURL: storeURL)
    let session = RoutineSyncCRUDSessionProvider(identity: nil)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let routines = SwiftDataRoutineRepository(
      modelContext: container.mainContext,
      routineSyncRepository: sync,
      signedInMemberProvider: session
    )
    let routine = makeRoutine(
      name: "재실행 뒤에도 로컬",
      steps: [makeStep()],
      isActive: false
    )

    try routines.saveRoutine(routine)
    XCTAssertTrue(
      try container.mainContext.fetch(
        FetchDescriptor<PersistedRoutineSyncMutation>()
      ).isEmpty
    )
    return routine.id
  }

  @MainActor
  private func makeRoutine(
    name: String,
    steps: [RoutineStep],
    isActive: Bool
  ) -> Routine {
    Routine(
      name: name,
      steps: steps,
      isActive: isActive,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1)
    )
  }

  @MainActor
  private func makeStep(title: String = "단계", order: Int = 0) -> RoutineStep {
    RoutineStep(type: .confirm, title: title, order: order)
  }

  private func decodedCommand(_ mutation: RoutineSyncMutation) throws -> RoutineSyncCommand {
    try JSONDecoder().decode(RoutineSyncCommand.self, from: mutation.payload)
  }

  @MainActor
  private func waitUntilStopped(
    _ coordinator: RoutineSyncRuntimeCoordinator,
    iterations: Int = 100
  ) async {
    for _ in 0..<iterations {
      if !coordinator.isDraining { return }
      await Task.yield()
    }
    XCTFail("Routine sync runtime did not stop.")
  }

  private var verifiedServerContract: RoutineSyncServerContract {
    RoutineSyncServerContract(capabilities: .allRequired, isE2EVerified: true)
  }
}

@MainActor
private final class RoutineSyncCRUDMemberProvider: SignedInMemberProviding {
  var signedInMemberID: Int64?

  init(memberID: Int64?) {
    signedInMemberID = memberID
  }
}

@MainActor
private final class RoutineSyncRuntimeIdentityProvider:
  SignedInMemberProviding,
  CurrentAccountSessionIdentityProviding {
  var identity: AccountSessionIdentity?

  init(identity: AccountSessionIdentity?) {
    self.identity = identity
  }

  var signedInMemberID: Int64? { identity?.memberID }
  var currentAccountSessionIdentity: AccountSessionIdentity? { identity }
}

private typealias RoutineSyncCRUDSessionProvider = RoutineSyncRuntimeIdentityProvider

@MainActor
private final class RoutineSyncWakeProbe {
  var count = 0
  var persistedRoutineCount = -1
}

private struct RoutineSyncCRUDFixture {
  let container: ModelContainer
  let member: RoutineSyncCRUDMemberProvider
  let sync: SwiftDataRoutineSyncRepository
  let routines: SwiftDataRoutineRepository
  let runs: SwiftDataRoutineRunRepository
  let onboarding: SwiftDataOnboardingRepository
}

private struct RoutineSyncBackfillRequestCapture: Equatable, Sendable {
  let identity: AccountSessionIdentity
  let path: String
  let body: Data
  let idempotencyKey: String
}

private actor RoutineSyncBackfillAPIClient: AccountBoundAPIClient {
  private let response: Data
  private var capture: RoutineSyncBackfillRequestCapture?

  init(response: Data) {
    self.response = response
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type
  ) async throws -> Payload {
    throw unexpectedRequest()
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type,
    authorizedForMemberID _: Int64
  ) async throws -> Payload {
    throw unexpectedRequest()
  }

  func requestVoid<Target: MoruTargetType>(_: Target) async throws {
    throw unexpectedRequest()
  }

  func requestData<Target: MoruTargetType>(_: Target) async throws -> Data {
    throw unexpectedRequest()
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Data {
    guard let target = target as? RoutineSyncWireTarget else {
      throw unexpectedRequest()
    }
    capture = RoutineSyncBackfillRequestCapture(
      identity: identity,
      path: target.path,
      body: target.wireRequest.body,
      idempotencyKey: target.idempotencyKey.uuidString
    )
    return response
  }

  func capturedRequest() -> RoutineSyncBackfillRequestCapture? {
    capture
  }

  private func unexpectedRequest() -> APIError {
    APIError.transport(code: -1, message: "Unexpected routine API request")
  }
}

private actor RoutineSyncCRUDTransportProbe: RoutineSyncTransport {
  private var count = 0

  func execute(
    _ request: RoutineSyncTransportRequest
  ) async -> RoutineSyncTransportOutcome {
    count += 1
    return .ambiguous
  }

  func requestCount() -> Int { count }
}

private actor RoutineSyncCountingAPIClient: AccountBoundRawResponseClient {
  private var count = 0

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    count += 1
    throw APIError.transport(code: -1, message: "Unexpected routine API request")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    count += 1
    throw APIError.transport(code: -1, message: "Unexpected routine API request")
  }

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    count += 1
    throw APIError.transport(code: -1, message: "Unexpected routine API request")
  }

  func requestData<Target: MoruTargetType>(_ target: Target) async throws -> Data {
    count += 1
    throw APIError.transport(code: -1, message: "Unexpected routine API request")
  }

  func requestResponse<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> AccountBoundHTTPResponse {
    count += 1
    throw APIError.transport(code: -1, message: "Unexpected routine API request")
  }

  func requestCount() -> Int {
    count
  }
}
