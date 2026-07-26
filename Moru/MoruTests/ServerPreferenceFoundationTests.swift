//
//  ServerPreferenceFoundationTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest

@testable import Moru

@MainActor
final class ServerPreferenceFoundationTests: XCTestCase {
  func testV3DiskStoreMigratesToV4AndPreservesEveryExistingModelAcrossRelaunch() throws {
    let storeURL = temporaryStoreURL()
    defer { removeStore(at: storeURL) }
    let fixture = makeV3Fixture()

    do {
      let schema = Schema(versionedSchema: MoruSchemaV3.self)
      let configuration = ModelConfiguration(
        "Moru",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(for: schema, configurations: [configuration])
      fixture.insert(into: container.mainContext)
      try container.mainContext.save()
    }

    do {
      let migrated = try ModelContainer.moruContainer(storeURL: storeURL)
      try assertV3Fixture(fixture, in: migrated.mainContext)
      XCTAssertTrue(
        try migrated.mainContext.fetch(
          FetchDescriptor<PersistedServerMutation>()
        ).isEmpty
      )
      XCTAssertTrue(
        try migrated.mainContext.fetch(
          FetchDescriptor<PersistedVoiceCatalogEntry>()
        ).isEmpty
      )

      migrated.mainContext.insert(
        makePersistedMutation(memberID: 94, operationKey: "voice")
      )
      migrated.mainContext.insert(
        makePersistedVoice(memberID: 94, voiceCode: "AOEDE")
      )
      try migrated.mainContext.save()
    }

    do {
      let relaunched = try ModelContainer.moruContainer(storeURL: storeURL)
      try assertV3Fixture(fixture, in: relaunched.mainContext)
      XCTAssertEqual(
        try relaunched.mainContext.fetch(
          FetchDescriptor<PersistedServerMutation>()
        ).count,
        1
      )
      XCTAssertEqual(
        try relaunched.mainContext.fetch(
          FetchDescriptor<PersistedVoiceCatalogEntry>()
        ).count,
        1
      )
    }
  }

  func testOutboxAcceptsOnlyValidatedIdempotentRequestsAndCoalescesPerAccountKey() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataServerPreferenceRepository(
      modelContext: container.mainContext
    )
    let first = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "selectedVoice", payload: "AOEDE")
    )
    let replacement = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "selectedVoice", payload: "KORE")
    )
    _ = try repository.enqueue(
      makeEnqueuedMutation(memberID: 95, operationKey: "selectedVoice", payload: "PUCK")
    )

    XCTAssertEqual(first.id, replacement.id)
    XCTAssertEqual(first.createdAt, replacement.createdAt)
    XCTAssertNotEqual(first.idempotencyKey, replacement.idempotencyKey)
    XCTAssertEqual(replacement.payload, Data("KORE".utf8))
    XCTAssertEqual(
      try repository.mutations(
        memberID: 94,
        dueAt: .distantFuture,
        includeBlocked: false
      ),
      [replacement]
    )
    XCTAssertEqual(
      try repository.mutations(
        memberID: 95,
        dueAt: .distantFuture,
        includeBlocked: false
      ).count,
      1
    )

    XCTAssertThrowsError(
      try repository.enqueue(
        makeEnqueuedMutation(memberID: 0, operationKey: "voice", payload: "AOEDE")
      )
    ) {
      XCTAssertEqual($0 as? ServerPreferenceRepositoryError, .invalidMemberID)
    }
    XCTAssertThrowsError(
      try repository.enqueue(
        makeEnqueuedMutation(memberID: 94, operationKey: " ", payload: "AOEDE")
      )
    ) {
      XCTAssertEqual($0 as? ServerPreferenceRepositoryError, .invalidOperationKey)
    }
    XCTAssertThrowsError(
      try repository.enqueue(
        EnqueuedServerMutation(
          memberID: 94,
          operation: .replaceVoiceSelection,
          operationKey: "voice",
          payload: Data()
        )
      )
    ) {
      XCTAssertEqual($0 as? ServerPreferenceRepositoryError, .invalidPayload)
    }
  }

  func testDuplicateCorruptAndUnknownOutboxRowsDoNotCrashOrDispatchTwice() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataServerPreferenceRepository(modelContext: context)
    let older = makePersistedMutation(
      memberID: 94,
      operationKey: "selectedVoice",
      payload: "OLD",
      updatedAt: Date(timeIntervalSince1970: 1)
    )
    let newer = makePersistedMutation(
      memberID: 94,
      operationKey: "selectedVoice",
      payload: "NEW",
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    let unknown = makePersistedMutation(
      memberID: 94,
      operationRawValue: "futureOperation",
      operationKey: "future",
      payload: "unknown"
    )
    let corrupt = makePersistedMutation(
      memberID: 94,
      operationKey: "corrupt",
      payloadData: Data()
    )
    [older, newer, unknown, corrupt].forEach(context.insert)
    try context.save()

    let pending = try repository.mutations(
      memberID: 94,
      dueAt: .distantFuture,
      includeBlocked: true
    )

    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending.first?.id, newer.id)
    XCTAssertEqual(pending.first?.payload, Data("NEW".utf8))
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedServerMutation>()).count,
      4,
      "Unknown and malformed rows are retained for explicit repair."
    )

    try repository.removeSucceeded(try XCTUnwrap(pending.first))
    let remaining = try context.fetch(FetchDescriptor<PersistedServerMutation>())
    XCTAssertEqual(Set(remaining.map(\.id)), Set([unknown.id, corrupt.id]))
  }

  func testRetryClassifierAndBackoffUseTheFrozenPolicy() {
    XCTAssertEqual(
      ServerMutationRetryClassifier.classify(
        APIError.transport(code: -1009, message: "offline")
      ),
      .transport
    )
    XCTAssertEqual(classification(statusCode: 408), .requestTimeout)
    XCTAssertEqual(classification(statusCode: 429), .rateLimited)
    XCTAssertEqual(classification(statusCode: 500), .serverUnavailable)
    XCTAssertEqual(classification(statusCode: 599), .serverUnavailable)
    XCTAssertEqual(classification(statusCode: 400), .nonRetryable)
    XCTAssertEqual(classification(statusCode: 401), .nonRetryable)
    XCTAssertEqual(classification(statusCode: 600), .nonRetryable)
    XCTAssertEqual(
      ServerMutationRetryClassifier.classify(APIError.decoding("malformed")),
      .nonRetryable
    )
    XCTAssertEqual(
      ServerMutationRetryClassifier.classify(ServerPreferenceTestError.failure),
      .nonRetryable
    )

    XCTAssertEqual(ServerMutationBackoff.delay(afterAttempt: 0), 30)
    XCTAssertEqual(ServerMutationBackoff.delay(afterAttempt: 1), 30)
    XCTAssertEqual(ServerMutationBackoff.delay(afterAttempt: 2), 60)
    XCTAssertEqual(ServerMutationBackoff.delay(afterAttempt: 3), 120)
    XCTAssertEqual(ServerMutationBackoff.delay(afterAttempt: 11), 21_600)
    XCTAssertEqual(ServerMutationBackoff.delay(afterAttempt: 100), 21_600)
  }

  func testRetryableMutationSurvivesRelaunchAndIsRemovedOnlyAfterSuccess() async throws {
    let storeURL = temporaryStoreURL()
    defer { removeStore(at: storeURL) }
    let failedAt = Date(timeIntervalSince1970: 10_000)
    let mutationID: UUID

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let repository = SwiftDataServerPreferenceRepository(
        modelContext: container.mainContext
      )
      mutationID = try repository.enqueue(
        makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
      ).id
      let executor = ServerPreferenceExecutor(
        outcomes: [.failure(classificationError(statusCode: 503))]
      )
      let coordinator = SyncCoordinator(
        mutationRepository: repository,
        executor: executor,
        now: { failedAt }
      )

      await coordinator.synchronize(memberID: 94, trigger: .appActive)
      let stored = try XCTUnwrap(
        container.mainContext.fetch(
          FetchDescriptor<PersistedServerMutation>()
        ).first
      )
      XCTAssertEqual(stored.id, mutationID)
      XCTAssertEqual(stored.attemptCount, 1)
      XCTAssertEqual(stored.lastFailureRawValue, ServerMutationFailure.serverUnavailable.rawValue)
      XCTAssertEqual(stored.nextAttemptAt, failedAt.addingTimeInterval(30))
    }

    do {
      let relaunched = try ModelContainer.moruContainer(storeURL: storeURL)
      let repository = SwiftDataServerPreferenceRepository(
        modelContext: relaunched.mainContext
      )
      let executor = ServerPreferenceExecutor(outcomes: [.sent])
      let earlyCoordinator = SyncCoordinator(
        mutationRepository: repository,
        executor: executor,
        now: { failedAt.addingTimeInterval(29) }
      )
      await earlyCoordinator.synchronize(memberID: 94, trigger: .appActive)
      let earlyCallCount = await executor.recordedCallCount()
      XCTAssertEqual(earlyCallCount, 0)
      XCTAssertEqual(
        try relaunched.mainContext.fetch(
          FetchDescriptor<PersistedServerMutation>()
        ).count,
        1
      )

      let dueCoordinator = SyncCoordinator(
        mutationRepository: repository,
        executor: executor,
        now: { failedAt.addingTimeInterval(30) }
      )
      await dueCoordinator.synchronize(memberID: 94, trigger: .appActive)
      let dueCallCount = await executor.recordedCallCount()
      XCTAssertEqual(dueCallCount, 1)
      XCTAssertTrue(
        try relaunched.mainContext.fetch(
          FetchDescriptor<PersistedServerMutation>()
        ).isEmpty
      )
    }
  }

  func testNonRetryableFailureIsRetainedUntilManualRetry() async throws {
    let now = Date(timeIntervalSince1970: 20_000)
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataServerPreferenceRepository(
      modelContext: container.mainContext
    )
    _ = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
    )
    let failingExecutor = ServerPreferenceExecutor(
      outcomes: [.failure(classificationError(statusCode: 422))]
    )
    let firstCoordinator = SyncCoordinator(
      mutationRepository: repository,
      executor: failingExecutor,
      now: { now }
    )
    await firstCoordinator.synchronize(memberID: 94, trigger: .loginSucceeded)

    let stored = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<PersistedServerMutation>()).first
    )
    XCTAssertEqual(stored.lastFailureRawValue, ServerMutationFailure.nonRetryable.rawValue)
    XCTAssertNil(stored.nextAttemptAt)

    let succeedingExecutor = ServerPreferenceExecutor(outcomes: [.sent])
    let coordinator = SyncCoordinator(
      mutationRepository: repository,
      executor: succeedingExecutor,
      now: { now.addingTimeInterval(86_400) }
    )
    await coordinator.synchronize(memberID: 94, trigger: .appActive)
    let automaticCallCount = await succeedingExecutor.recordedCallCount()
    XCTAssertEqual(automaticCallCount, 0)
    XCTAssertEqual(
      try container.mainContext.fetch(FetchDescriptor<PersistedServerMutation>()).count,
      1
    )

    await coordinator.synchronize(memberID: 94, trigger: .manual)
    let manualCallCount = await succeedingExecutor.recordedCallCount()
    XCTAssertEqual(manualCallCount, 1)
    XCTAssertTrue(
      try container.mainContext.fetch(FetchDescriptor<PersistedServerMutation>()).isEmpty
    )
  }

  func testDeferredP6ExecutorLeavesOutboxUntouched() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataServerPreferenceRepository(
      modelContext: container.mainContext
    )
    let queued = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
    )
    let coordinator = SyncCoordinator(
      mutationRepository: repository,
      executor: DeferredServerMutationExecutor()
    )

    await coordinator.synchronize(memberID: 94, trigger: .manual)

    let persisted = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<PersistedServerMutation>()).first
    )
    XCTAssertEqual(persisted.id, queued.id)
    XCTAssertEqual(persisted.attemptCount, 0)
    XCTAssertNil(persisted.lastFailureRawValue)
  }

  func testInFlightSuccessCannotDeleteANewerCoalescedMutation() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataServerPreferenceRepository(
      modelContext: container.mainContext
    )
    let original = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
    )
    let executor = SuspendedServerPreferenceExecutor()
    let coordinator = SyncCoordinator(
      mutationRepository: repository,
      executor: executor
    )
    let synchronization = Task { @MainActor in
      await coordinator.synchronize(memberID: 94, trigger: .manual)
    }
    await executor.waitUntilStarted()

    let replacement = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "KORE")
    )
    XCTAssertEqual(original.id, replacement.id)
    XCTAssertNotEqual(original.idempotencyKey, replacement.idempotencyKey)

    await executor.finish(with: .sent)
    await synchronization.value

    let pending = try repository.mutations(
      memberID: 94,
      dueAt: .distantFuture,
      includeBlocked: true
    )
    XCTAssertEqual(pending, [replacement])
  }

  func testStaleFailureCannotBackoffANewerCoalescedMutation() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataServerPreferenceRepository(
      modelContext: container.mainContext
    )
    let original = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
    )
    let replacement = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "KORE")
    )

    try repository.recordFailure(
      .transport,
      for: original,
      at: Date(timeIntervalSince1970: 1)
    )

    let pending = try repository.mutations(
      memberID: 94,
      dueAt: .distantFuture,
      includeBlocked: true
    )
    XCTAssertEqual(pending, [replacement])
    XCTAssertEqual(pending.first?.attemptCount, 0)
    XCTAssertNil(pending.first?.lastFailure)
    XCTAssertNil(pending.first?.nextAttemptAt)
  }

  func testVoiceCatalogPreservesUnknownTierAndSkipsCorruptionAndDuplicates() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataServerPreferenceRepository(modelContext: context)
    let older = makePersistedVoice(
      memberID: 94,
      voiceCode: "AOEDE",
      displayName: "이전 이름",
      fetchedAt: Date(timeIntervalSince1970: 1)
    )
    let newer = makePersistedVoice(
      memberID: 94,
      voiceCode: "AOEDE",
      displayName: "새 이름",
      tierRawValue: "future-tier",
      fetchedAt: Date(timeIntervalSince1970: 2)
    )
    let corrupt = makePersistedVoice(
      memberID: 94,
      voiceCode: " ",
      displayName: "손상",
      fetchedAt: Date(timeIntervalSince1970: 3)
    )
    let otherAccount = makePersistedVoice(
      memberID: 95,
      voiceCode: "PUCK",
      fetchedAt: Date(timeIntervalSince1970: 4)
    )
    [older, newer, corrupt, otherAccount].forEach(context.insert)
    try context.save()

    let catalog = try repository.catalog(memberID: 94)

    XCTAssertEqual(catalog.count, 1)
    XCTAssertEqual(catalog.first?.id, newer.id)
    XCTAssertEqual(catalog.first?.tierRawValue, "future-tier")
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedVoiceCatalogEntry>()).count,
      4,
      "Read recovery must not silently discard server cache rows."
    )
    XCTAssertEqual(try repository.catalog(memberID: 95).map(\.voiceCode), ["PUCK"])
  }

  func testAccountCleanupRemovesOnlyTargetOutboxAndVoiceCache() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataServerPreferenceRepository(modelContext: context)
    _ = try repository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
    )
    _ = try repository.enqueue(
      makeEnqueuedMutation(memberID: 95, operationKey: "voice", payload: "PUCK")
    )
    try repository.upsertCatalog(
      [makeVoiceEntry(memberID: 94, voiceCode: "AOEDE")],
      memberID: 94
    )
    try repository.upsertCatalog(
      [makeVoiceEntry(memberID: 95, voiceCode: "PUCK")],
      memberID: 95
    )
    let localFixture = makeV3Fixture()
    localFixture.insert(into: context)
    try context.save()

    let cleaner = SwiftDataAccountScopedDataCleaner(repository: repository)
    try await cleaner.removeAccountScopedData(memberID: 94)

    XCTAssertTrue(
      try repository.mutations(
        memberID: 94,
        dueAt: .distantFuture,
        includeBlocked: true
      ).isEmpty
    )
    XCTAssertTrue(try repository.catalog(memberID: 94).isEmpty)
    XCTAssertEqual(
      try repository.mutations(
        memberID: 95,
        dueAt: .distantFuture,
        includeBlocked: true
      ).count,
      1
    )
    XCTAssertEqual(try repository.catalog(memberID: 95).map(\.voiceCode), ["PUCK"])
    try assertV3Fixture(localFixture, in: context)
  }

  func testLocalDependencyContainerConnectsP5CleanupBoundary() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(
      modelContext: container.mainContext
    )
    let mutationRepository = try XCTUnwrap(
      dependencies.serverMutationRepository
    )
    let voiceRepository = try XCTUnwrap(
      dependencies.serverVoiceCatalogRepository
    )
    _ = try mutationRepository.enqueue(
      makeEnqueuedMutation(memberID: 94, operationKey: "voice", payload: "AOEDE")
    )
    try voiceRepository.upsertCatalog(
      [makeVoiceEntry(memberID: 94, voiceCode: "AOEDE")],
      memberID: 94
    )

    try await dependencies.accountScopedDataCleaner.removeAccountScopedData(
      memberID: 94
    )

    XCTAssertTrue(
      try mutationRepository.mutations(
        memberID: 94,
        dueAt: .distantFuture,
        includeBlocked: true
      ).isEmpty
    )
    XCTAssertTrue(try voiceRepository.catalog(memberID: 94).isEmpty)
    XCTAssertNotNil(dependencies.syncCoordinator)
  }

  func testSuccessfulLoginInvokesOnlyTheLoginSuccessHook() throws {
    let store = ServerPreferenceCredentialStore()
    let sessionStore = AccountSessionStore(
      credentialStore: store,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    var memberIDs: [Int64] = []
    sessionStore.setLoginSucceededHandler { memberID in
      memberIDs.append(memberID)
    }

    sessionStore.restore()
    XCTAssertTrue(memberIDs.isEmpty)

    try sessionStore.establishSession(
      credentials: AccountCredentials(
        memberID: 94,
        accessToken: "access",
        refreshToken: "refresh",
        onboardingCompleted: true
      )
    )
    XCTAssertEqual(memberIDs, [94])
  }

  private func classification(statusCode: Int) -> ServerMutationFailure {
    ServerMutationRetryClassifier.classify(
      classificationError(statusCode: statusCode)
    )
  }

  private func classificationError(statusCode: Int) -> APIError {
    APIError.server(statusCode: statusCode, code: nil, message: "failure")
  }

  private func makeEnqueuedMutation(
    memberID: Int64,
    operationKey: String,
    payload: String
  ) -> EnqueuedServerMutation {
    EnqueuedServerMutation(
      memberID: memberID,
      operation: .replaceVoiceSelection,
      operationKey: operationKey,
      payload: Data(payload.utf8)
    )
  }

  private func makePersistedMutation(
    memberID: Int64,
    operationRawValue: String = IdempotentServerOperation
      .replaceVoiceSelection.rawValue,
    operationKey: String,
    payload: String = "AOEDE",
    payloadData: Data? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1)
  ) -> PersistedServerMutation {
    PersistedServerMutation(
      id: UUID(),
      memberID: memberID,
      operationRawValue: operationRawValue,
      operationKey: operationKey,
      payload: payloadData ?? Data(payload.utf8),
      idempotencyKey: UUID(),
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: updatedAt,
      attemptCount: 0,
      nextAttemptAt: nil,
      lastFailureRawValue: nil
    )
  }

  private func makeVoiceEntry(
    memberID: Int64,
    voiceCode: String
  ) -> ServerVoiceCatalogEntry {
    ServerVoiceCatalogEntry(
      memberID: memberID,
      voiceCode: voiceCode,
      displayName: voiceCode,
      tierRawValue: "FREE",
      isLocallyPlayable: true,
      fetchedAt: Date(timeIntervalSince1970: 1)
    )
  }

  private func makePersistedVoice(
    memberID: Int64,
    voiceCode: String,
    displayName: String = "음성",
    tierRawValue: String = "FREE",
    fetchedAt: Date = Date(timeIntervalSince1970: 1)
  ) -> PersistedVoiceCatalogEntry {
    PersistedVoiceCatalogEntry(
      id: UUID(),
      memberID: memberID,
      voiceCode: voiceCode,
      displayName: displayName,
      tierRawValue: tierRawValue,
      isLocallyPlayable: true,
      fetchedAt: fetchedAt
    )
  }

  private func makeV3Fixture() -> ServerPreferenceV3Fixture {
    ServerPreferenceV3Fixture()
  }

  private func assertV3Fixture(
    _ fixture: ServerPreferenceV3Fixture,
    in context: ModelContext
  ) throws {
    let routines = try context.fetch(FetchDescriptor<PersistedRoutine>())
    XCTAssertEqual(routines.map(\.id), [fixture.routineID])
    XCTAssertEqual(routines.first?.alarmSchedule?.id, fixture.alarmID)
    XCTAssertEqual(routines.first?.steps.map(\.id), [fixture.stepID])
    XCTAssertEqual(routines.first?.syncStatusRawValue, SyncStatus.localOnly.rawValue)
    XCTAssertNil(routines.first?.remoteID)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedLocalProfile>()).map(\.id),
      [fixture.profileID]
    )
    let runs = try context.fetch(FetchDescriptor<PersistedRoutineRun>())
    XCTAssertEqual(runs.map(\.id), [fixture.runID])
    XCTAssertEqual(runs.first?.plannedSteps.map(\.id), [fixture.snapshotID])
    XCTAssertEqual(runs.first?.results.map(\.id), [fixture.resultID])
    XCTAssertEqual(runs.first?.syncStatusRawValue, SyncStatus.localOnly.rawValue)
    XCTAssertNil(runs.first?.remoteID)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).map(\.id),
      [fixture.weatherID]
    )
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedAlarmPlatformState>())
        .map(\.scheduleID),
      [fixture.alarmID]
    )
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<PersistedSnoozedAlarm>()).map(\.id),
      [fixture.snoozeID]
    )
  }

  private func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("MoruP6-\(UUID().uuidString)")
      .appendingPathExtension("sqlite")
  }

  private func removeStore(at storeURL: URL) {
    let fileManager = FileManager.default
    for suffix in ["", "-shm", "-wal"] {
      try? fileManager.removeItem(atPath: storeURL.path + suffix)
    }
  }
}

@MainActor
private struct ServerPreferenceV3Fixture {
  let profileID: UUID
  let stepID: UUID
  let alarmID: UUID
  let routineID: UUID
  let snapshotID: UUID
  let resultID: UUID
  let runID: UUID
  let weatherID: UUID
  let snoozeID: UUID
  let profile: PersistedLocalProfile
  let step: PersistedRoutineStep
  let alarm: PersistedAlarmSchedule
  let routine: PersistedRoutine
  let snapshot: PersistedRoutineStepSnapshot
  let result: PersistedRoutineStepResult
  let run: PersistedRoutineRun
  let weather: PersistedHomeWeatherSnapshot
  let platformState: PersistedAlarmPlatformState
  let snooze: PersistedSnoozedAlarm

  init() {
    let now = Date(timeIntervalSince1970: 1_000)
    profileID = UUID()
    stepID = UUID()
    alarmID = UUID()
    routineID = UUID()
    snapshotID = UUID()
    resultID = UUID()
    runID = UUID()
    weatherID = UUID()
    snoozeID = UUID()
    profile = PersistedLocalProfile(
      id: profileID,
      displayName: "V3 사용자",
      selectedVoiceID: VoiceProfile.aoede.id,
      createdAt: now,
      updatedAt: now
    )
    step = PersistedRoutineStep(
      id: stepID,
      presetItemID: "water",
      typeRawValue: RoutineStepType.confirm.rawValue,
      title: "물 마시기",
      instruction: "한 잔 마시기",
      order: 0,
      estimatedSeconds: 60,
      isRequired: true
    )
    alarm = PersistedAlarmSchedule(
      id: alarmID,
      hour: 7,
      minute: 10,
      weekdaysRawValue: "[2,4]",
      soundName: "moru-default",
      isEnabled: true,
      includeWeather: true,
      includeFortune: false
    )
    routine = PersistedRoutine(
      id: routineID,
      name: "V3 루틴",
      summary: "보존",
      goalTagsRawValue: "[]",
      steps: [step],
      alarmSchedule: alarm,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
    snapshot = PersistedRoutineStepSnapshot(
      id: snapshotID,
      stepID: stepID,
      stepTitle: "물 마시기",
      stepTypeRawValue: RoutineStepType.confirm.rawValue,
      stepOrder: 0,
      estimatedSeconds: 60,
      isRequired: true
    )
    result = PersistedRoutineStepResult(
      id: resultID,
      stepID: stepID,
      stepTitle: "물 마시기",
      stepTypeRawValue: RoutineStepType.confirm.rawValue,
      completedAt: now,
      skipped: false,
      inputText: nil,
      transcript: "완료",
      durationSeconds: 30
    )
    run = PersistedRoutineRun(
      id: runID,
      routineID: routineID,
      routineName: "V3 루틴",
      startedAt: now,
      completedAt: now.addingTimeInterval(30),
      results: [result],
      plannedSteps: [snapshot],
      endedEarly: false,
      remoteID: nil,
      syncStatusRawValue: SyncStatus.localOnly.rawValue,
      lastSyncedAt: nil,
      remoteRevision: nil
    )
    weather = PersistedHomeWeatherSnapshot(
      id: weatherID,
      conditionRawValue: HomeWeatherCondition.clear.rawValue,
      temperatureCelsius: 22,
      latitudeE4: 375_666,
      longitudeE4: 1_269_781,
      fetchedAt: now,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
    platformState = PersistedAlarmPlatformState(
      scheduleID: alarmID,
      routineID: routineID,
      routineName: "V3 루틴",
      hour: 7,
      minute: 10,
      weekdaysRawValue: "[2,4]",
      soundName: "moru-default",
      fingerprint: "fingerprint",
      backendRawValue: AlarmDeliveryBackend.alarmKit.rawValue,
      deliveryStateRawValue: AlarmDeliveryState.scheduled.rawValue,
      platformIdentifiersRawValue: "[\"alarm-id\"]",
      lastErrorMessage: nil,
      updatedAt: now
    )
    snooze = PersistedSnoozedAlarm(
      id: snoozeID,
      scheduleID: alarmID,
      routineID: routineID,
      fireDate: now.addingTimeInterval(300),
      backendRawValue: AlarmDeliveryBackend.localNotification.rawValue,
      platformIdentifiersRawValue: "[\"snooze-id\"]",
      createdAt: now
    )
  }

  func insert(into context: ModelContext) {
    context.insert(profile)
    context.insert(routine)
    context.insert(run)
    context.insert(weather)
    context.insert(platformState)
    context.insert(snooze)
  }
}

private enum ServerPreferenceExecutionOutcome: Sendable {
  case sent
  case deferred
  case failure(APIError)
}

private actor ServerPreferenceExecutor: ServerMutationExecuting {
  private var outcomes: [ServerPreferenceExecutionOutcome]
  private(set) var callCount = 0

  init(outcomes: [ServerPreferenceExecutionOutcome]) {
    self.outcomes = outcomes
  }

  func execute(_ mutation: ServerMutation) async throws -> ServerMutationExecutionResult {
    callCount += 1
    guard !outcomes.isEmpty else {
      return .sent
    }

    switch outcomes.removeFirst() {
    case .sent:
      return .sent
    case .deferred:
      return .deferred
    case .failure(let error):
      throw error
    }
  }

  func recordedCallCount() -> Int {
    callCount
  }
}

private actor SuspendedServerPreferenceExecutor: ServerMutationExecuting {
  private var continuation:
    CheckedContinuation<ServerMutationExecutionResult, Never>?
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var didStart = false

  func execute(_ mutation: ServerMutation) async throws -> ServerMutationExecutionResult {
    didStart = true
    startedContinuation?.resume()
    startedContinuation = nil

    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    guard !didStart else {
      return
    }

    await withCheckedContinuation { continuation in
      startedContinuation = continuation
    }
  }

  func finish(with result: ServerMutationExecutionResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

nonisolated private final class ServerPreferenceCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private var credentials: AccountCredentials?

  func load() throws -> AccountCredentials? {
    lock.withLock { credentials }
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.withLock { self.credentials = credentials }
  }

  func remove() throws {
    lock.withLock { credentials = nil }
  }
}

private enum ServerPreferenceTestError: Error {
  case failure
}
