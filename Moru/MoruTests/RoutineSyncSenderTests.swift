//
//  RoutineSyncSenderTests.swift
//  MoruTests
//

import SwiftData
import XCTest
@testable import Moru

final class RoutineSyncSenderTests: XCTestCase {
  @MainActor
  func testInvalidFirstWireRequestBlocksBeforeTransport() async throws {
    let fixture = try makeFixture(actions: [])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID()),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = RoutineSyncSender(
      repository: fixture.repository,
      requestPreparer: RejectingRoutineSyncWireRequestPreparer(),
      transport: fixture.transport,
      contract: .productionP0,
      geminiDataConsent: GeminiDataConsentStub()
    )

    let result = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let requests = await fixture.transport.requests()
    let stored = try XCTUnwrap(
      try fixture.repository.mutations(memberID: 7).first
    )

    XCTAssertEqual(
      result,
      .blocked(mutationID: mutation.id, reason: .invalidStoredRequest)
    )
    XCTAssertTrue(requests.isEmpty)
    XCTAssertEqual(stored.state, .blocked)
    XCTAssertNil(stored.attempt)
  }

  @MainActor
  func testUnavailableContractNeverClaimsOrCallsTransport() async throws {
    let fixture = try makeFixture(actions: [])
    _ = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID()),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeSender(fixture, contract: .unavailable)

    let result = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let requests = await fixture.transport.requests()
    XCTAssertEqual(result, .idle)
    XCTAssertEqual(requests, [])
    XCTAssertEqual(fixture.preparer.callCount, 0)
    XCTAssertEqual(
      try fixture.repository.mutations(memberID: 7).first?.state,
      .waitingForServerContract
    )
  }

  @MainActor
  func testGeminiConsentHoldsCreateBeforeClaimAndExactReplayAfterRevocation()
    async throws {
    let fixture = try makeFixture(actions: [.ambiguous])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID()),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let consent = GeminiDataConsentStub(hasExplicitGeminiDataConsent: false)
    let sender = RoutineSyncSender(
      repository: fixture.repository,
      requestPreparer: fixture.preparer,
      transport: fixture.transport,
      contract: .productionP0,
      geminiDataConsent: consent
    )

    let held = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )

    XCTAssertEqual(held, .consentRequired(mutationID: mutation.id))
    XCTAssertEqual(consent.requestCount, 1)
    XCTAssertEqual(fixture.preparer.callCount, 0)
    let heldRequests = await fixture.transport.requests()
    XCTAssertTrue(heldRequests.isEmpty)
    let beforeConsent = try XCTUnwrap(
      try fixture.repository.mutations(memberID: 7).first
    )
    XCTAssertEqual(beforeConsent.state, .queued)
    XCTAssertNil(beforeConsent.attempt)

    consent.hasExplicitGeminiDataConsent = true
    let firstSend = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    XCTAssertEqual(
      firstSend,
      .retryScheduled(mutationID: mutation.id, nextAttemptAt: nil)
    )
    let attempted = try XCTUnwrap(
      try fixture.repository.mutations(memberID: 7).first
    )
    XCTAssertEqual(attempted.state, .needsReconciliation)
    XCTAssertNotNil(attempted.attempt)
    let attemptedRequests = await fixture.transport.requests()
    XCTAssertEqual(attemptedRequests.count, 1)

    consent.hasExplicitGeminiDataConsent = false
    let replayHeld = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 4)
    )

    XCTAssertEqual(replayHeld, .consentRequired(mutationID: mutation.id))
    XCTAssertEqual(consent.requestCount, 2)
    XCTAssertEqual(fixture.preparer.callCount, 1)
    let replayRequests = await fixture.transport.requests()
    XCTAssertEqual(replayRequests.count, 1)
    let heldReplay = try XCTUnwrap(
      try fixture.repository.mutations(memberID: 7).first
    )
    XCTAssertEqual(heldReplay.state, .needsReconciliation)
    XCTAssertEqual(
      heldReplay.attempt?.generationID,
      attempted.attempt?.generationID
    )
  }

  @MainActor
  func testGeminiConsentHoldsAddRoutineBeforeWirePreparation() async throws {
    let fixture = try makeFixture(actions: [])
    let groupID = UUID()
    let routineID = UUID()
    _ = try fixture.repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        ),
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let mutation = try fixture.repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: routineID,
          title: "동의 전 단계",
          type: "confirm",
          durationSeconds: nil,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let consent = GeminiDataConsentStub(hasExplicitGeminiDataConsent: false)
    let sender = RoutineSyncSender(
      repository: fixture.repository,
      requestPreparer: fixture.preparer,
      transport: fixture.transport,
      contract: .productionP0,
      geminiDataConsent: consent
    )

    let result = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    XCTAssertEqual(result, .consentRequired(mutationID: mutation.id))
    XCTAssertEqual(consent.requestCount, 1)
    XCTAssertEqual(fixture.preparer.callCount, 0)
    let capturedRequests = await fixture.transport.requests()
    XCTAssertTrue(capturedRequests.isEmpty)
    let held = try XCTUnwrap(try fixture.repository.mutations(memberID: 7).first)
    XCTAssertEqual(held.state, .queued)
    XCTAssertNil(held.attempt)
  }

  @MainActor
  func testAttemptPersistsExactWireBytesBeforeTransportAndUsesGenerationKey()
    async throws {
    let groupID = UUID()
    let body = Data(#"{"clientEntityId":"group","title":"그룹"}"#.utf8)
    let fixture = try makeFixture(
      body: body,
      actions: [
        .committed(
          .createRoutineGroup(
            assignments: [
              RoutineServerBindingAssignment(
                entityKind: .routineGroup,
                localEntityID: groupID,
                remoteID: 41
              )
            ]
          )
        )
      ]
    )
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    await fixture.transport.setOnExecute { [repository = fixture.repository] request in
      let stored = try repository.mutations(memberID: request.memberID).first
      XCTAssertEqual(stored?.state, .attempting)
      XCTAssertEqual(stored?.attempt?.wireRequest?.body, body)
    }

    let result = try await makeSender(fixture).sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )

    XCTAssertEqual(result, .completed(mutationID: mutation.id))
    let capturedRequests = await fixture.transport.requests()
    let request = try XCTUnwrap(capturedRequests.first)
    XCTAssertEqual(request.idempotencyKey, mutation.generationID)
    XCTAssertEqual(request.wireRequest.body, body)
    XCTAssertEqual(request.wireRequest.path, "/routine-groups")
    XCTAssertFalse(request.description.contains("그룹"))
    XCTAssertEqual(
      try fixture.repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: groupID
      )?.remoteID,
      41
    )
  }

  @MainActor
  func testRetryUsesPersistedKeyPathAndBodyAfterCurrentPayloadChanges()
    async throws {
    let groupID = UUID()
    let body = Data(#"{"clientEntityId":"stable","title":"처음"}"#.utf8)
    let fixture = try makeFixture(
      body: body,
      actions: [
        .ambiguous,
        .committed(
          .createRoutineGroup(
            assignments: [
              RoutineServerBindingAssignment(
                entityKind: .routineGroup,
                localEntityID: groupID,
                remoteID: 41
              )
            ]
          )
        ),
      ]
    )
    let original = try fixture.repository.enqueue(
      command: createCommand(groupID: groupID, name: "처음"),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeSender(fixture)

    let firstResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(
      firstResult,
      .retryScheduled(mutationID: original.id, nextAttemptAt: nil)
    )
    let changed = try fixture.repository.enqueue(
      command: createCommand(groupID: groupID, name: "현재 SwiftData 값"),
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    XCTAssertNotEqual(changed.generationID, original.generationID)

    _ = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 4)
    )

    let requests = await fixture.transport.requests()
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests.map(\.idempotencyKey), [
      original.generationID,
      original.generationID,
    ])
    XCTAssertEqual(requests.map(\.wireRequest), [
      requests[0].wireRequest,
      requests[0].wireRequest,
    ])
    XCTAssertEqual(requests[0].wireRequest.body, body)
    XCTAssertEqual(fixture.preparer.callCount, 1)
  }

  @MainActor
  func testAppReopenReplaysPersistedArtifactWithoutPreparingAgain()
    async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("moru.store")
    let groupID = UUID()
    let body = Data(#"{"clientEntityId":"reopen"}"#.utf8)
    var generationID: UUID!

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let repository = SwiftDataRoutineSyncRepository(
        modelContext: container.mainContext
      )
      let preparer = RoutineSyncWireRequestPreparerStub(body: body)
      let transport = RoutineSyncTransportStub(actions: [.ambiguous])
      generationID = try repository.enqueue(
        command: createCommand(groupID: groupID),
        memberID: 7,
        at: Date(timeIntervalSince1970: 1)
      ).generationID
      let sender = RoutineSyncSender(
        repository: repository,
        requestPreparer: preparer,
        transport: transport,
        contract: .productionP0,
        geminiDataConsent: GeminiDataConsentStub()
      )
      _ = try await sender.sendNext(
        memberID: 7,
        at: Date(timeIntervalSince1970: 2)
      )
      XCTAssertEqual(preparer.callCount, 1)
    }

    let reopened = try ModelContainer.moruContainer(storeURL: storeURL)
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: reopened.mainContext
    )
    let trapPreparer = RoutineSyncWireRequestPreparerStub(
      body: Data(#"{"wrong":true}"#.utf8)
    )
    let transport = RoutineSyncTransportStub(actions: [
      .committed(
        .createRoutineGroup(
          assignments: [
            RoutineServerBindingAssignment(
              entityKind: .routineGroup,
              localEntityID: groupID,
              remoteID: 41
            )
          ]
        )
      )
    ])
    let sender = RoutineSyncSender(
      repository: repository,
      requestPreparer: trapPreparer,
      transport: transport,
      contract: .productionP0,
      geminiDataConsent: GeminiDataConsentStub()
    )

    _ = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )

    let replayRequests = await transport.requests()
    let replay = try XCTUnwrap(replayRequests.first)
    XCTAssertEqual(replay.idempotencyKey, generationID)
    XCTAssertEqual(replay.wireRequest.body, body)
    XCTAssertEqual(trapPreparer.callCount, 0)
  }

  @MainActor
  func testAttemptAt24HourBoundaryBlocksWithoutReplay() async throws {
    let fixture = try makeFixture(actions: [.ambiguous])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID()),
      memberID: 7,
      at: Date(timeIntervalSince1970: 0)
    )
    let sender = makeSender(fixture)
    _ = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )

    let result = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 1 + 24 * 60 * 60)
    )

    XCTAssertEqual(
      result,
      .blocked(mutationID: mutation.id, reason: .resultTTLExpired)
    )
    let requestCount = await fixture.transport.requests().count
    XCTAssertEqual(requestCount, 1)
    let stored = try XCTUnwrap(try fixture.repository.mutations(memberID: 7).first)
    XCTAssertEqual(stored.state, .blocked)
    XCTAssertEqual(stored.blockReason, .resultTTLExpired)
  }

  @MainActor
  func testProcessingConflictUsesBoundedPersistedExactReplay() async throws {
    let fixture = try makeFixture(actions: [
      .processingConflict,
      .processingConflict,
      .processingConflict,
    ])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID()),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeSender(fixture)

    let firstResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(
      firstResult,
      .retryScheduled(
        mutationID: mutation.id,
        nextAttemptAt: Date(timeIntervalSince1970: 3)
      )
    )
    let secondResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    XCTAssertEqual(
      secondResult,
      .retryScheduled(
        mutationID: mutation.id,
        nextAttemptAt: Date(timeIntervalSince1970: 5)
      )
    )
    let thirdResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 5)
    )
    XCTAssertEqual(
      thirdResult,
      .blocked(mutationID: mutation.id, reason: .processingRetryExhausted)
    )

    let requests = await fixture.transport.requests()
    XCTAssertEqual(requests.count, 3)
    XCTAssertEqual(Set(requests.map(\.idempotencyKey)), [mutation.generationID])
    XCTAssertEqual(Set(requests.map(\.wireRequest.body)), [fixture.preparer.body])
    XCTAssertEqual(
      try fixture.repository.mutations(memberID: 7).first?.processingConflictCount,
      3
    )
  }

  @MainActor
  func testSameMemberNewSessionResponseDoesNotSettleOutboxOrBindings()
    async throws {
    let groupID = UUID()
    let oldIdentity = AccountSessionIdentity(memberID: 7, sessionID: UUID())
    let provider = MutableSessionIdentityProvider(identity: oldIdentity)
    let fixture = try makeFixture(actions: [])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let transport = SessionChangingRoutineSyncTransport(
      provider: provider,
      outcome: .committed(
        .createRoutineGroup(
          assignments: [
            RoutineServerBindingAssignment(
              entityKind: .routineGroup,
              localEntityID: groupID,
              remoteID: 41
            )
          ]
        )
      )
    )
    let sender = RoutineSyncSender(
      repository: fixture.repository,
      requestPreparer: fixture.preparer,
      transport: transport,
      contract: .productionP0,
      sessionIdentityProvider: provider,
      geminiDataConsent: GeminiDataConsentStub()
    )

    let result = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )

    XCTAssertEqual(result, .staleSession(mutationID: mutation.id))
    XCTAssertNil(
      try fixture.repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: groupID
      )
    )
    let stored = try XCTUnwrap(try fixture.repository.mutations(memberID: 7).first)
    XCTAssertEqual(stored.state, .attempting)
    XCTAssertEqual(stored.attempt?.generationID, mutation.generationID)
    XCTAssertNotEqual(provider.identity, oldIdentity)
  }

  @MainActor
  func testOnboardingCompletionSettlesAndUpdatesOnlyCapturedSession() async throws {
    let fixture = try makeFixture(actions: [.committed(.onboardingCompleted)])
    let groupID = UUID()
    _ = try fixture.repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: .distantPast
    )
    let mutation = try fixture.repository.enqueue(
      command: .completeOnboarding(groupLocalID: groupID),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let identity = AccountSessionIdentity(memberID: 7, sessionID: UUID())
    let provider = MutableSessionIdentityProvider(identity: identity)
    var committedIdentities: [AccountSessionIdentity] = []
    let sender = RoutineSyncSender(
      repository: fixture.repository,
      requestPreparer: fixture.preparer,
      transport: fixture.transport,
      contract: .productionP0,
      sessionIdentityProvider: provider,
      geminiDataConsent: GeminiDataConsentStub(),
      onOnboardingCompletionCommitted: { committedIdentities.append($0) }
    )

    let result = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )

    XCTAssertEqual(result, .completed(mutationID: mutation.id))
    XCTAssertEqual(committedIdentities, [identity])
    XCTAssertTrue(try fixture.repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  private func makeFixture(
    body: Data = Data(#"{"clientEntityId":"fixture"}"#.utf8),
    actions: [RoutineSyncTransportOutcome]
  ) throws -> RoutineSyncSenderFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    return RoutineSyncSenderFixture(
      container: container,
      repository: SwiftDataRoutineSyncRepository(
        modelContext: container.mainContext
      ),
      preparer: RoutineSyncWireRequestPreparerStub(body: body),
      transport: RoutineSyncTransportStub(actions: actions)
    )
  }

  @MainActor
  private func makeSender(
    _ fixture: RoutineSyncSenderFixture,
    contract: RoutineSyncServerContract = .productionP0
  ) -> RoutineSyncSender {
    RoutineSyncSender(
      repository: fixture.repository,
      requestPreparer: fixture.preparer,
      transport: fixture.transport,
      contract: contract,
      geminiDataConsent: GeminiDataConsentStub()
    )
  }

  private func createCommand(
    groupID: UUID,
    name: String = "그룹"
  ) -> RoutineSyncCommand {
    .createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: name,
        summary: "",
        isActive: false,
        alarm: nil,
        routines: []
      )
    )
  }
}

@MainActor
private struct RoutineSyncSenderFixture {
  let container: ModelContainer
  let repository: SwiftDataRoutineSyncRepository
  let preparer: RoutineSyncWireRequestPreparerStub
  let transport: RoutineSyncTransportStub
}

@MainActor
private final class RoutineSyncWireRequestPreparerStub:
  RoutineSyncWireRequestPreparing {
  let body: Data
  private(set) var callCount = 0

  init(body: Data) {
    self.body = body
  }

  func makeWireRequest(
    for _: RoutineSyncCommand,
    mutation _: RoutineSyncMutation
  ) throws -> RoutineSyncWireRequest {
    callCount += 1
    return RoutineSyncWireRequest(
      method: .post,
      path: "/routine-groups",
      body: body
    )
  }
}

@MainActor
private final class RejectingRoutineSyncWireRequestPreparer:
  RoutineSyncWireRequestPreparing {
  func makeWireRequest(
    for _: RoutineSyncCommand,
    mutation _: RoutineSyncMutation
  ) throws -> RoutineSyncWireRequest {
    throw RoutineSyncRequestPreparingError.invalidLocalSnapshot
  }
}

private actor RoutineSyncTransportStub: RoutineSyncTransport {
  typealias ExecuteHook = @MainActor @Sendable (
    RoutineSyncTransportRequest
  ) throws -> Void

  private var onExecute: ExecuteHook?

  private var actions: [RoutineSyncTransportOutcome]
  private var capturedRequests: [RoutineSyncTransportRequest] = []

  init(actions: [RoutineSyncTransportOutcome]) {
    self.actions = actions
  }

  func setOnExecute(_ hook: @escaping ExecuteHook) {
    onExecute = hook
  }

  func execute(
    _ request: RoutineSyncTransportRequest
  ) async -> RoutineSyncTransportOutcome {
    capturedRequests.append(request)
    if let onExecute {
      do {
        try await onExecute(request)
      } catch {
        return .ambiguous
      }
    }
    guard !actions.isEmpty else { return .ambiguous }
    return actions.removeFirst()
  }

  func requests() -> [RoutineSyncTransportRequest] { capturedRequests }
}

@MainActor
private final class MutableSessionIdentityProvider:
  CurrentAccountSessionIdentityProviding {
  var identity: AccountSessionIdentity?

  init(identity: AccountSessionIdentity?) {
    self.identity = identity
  }

  var currentAccountSessionIdentity: AccountSessionIdentity? { identity }
}

private final class SessionChangingRoutineSyncTransport:
  RoutineSyncTransport,
  @unchecked Sendable {
  private weak var provider: MutableSessionIdentityProvider?
  private let outcome: RoutineSyncTransportOutcome

  @MainActor
  init(
    provider: MutableSessionIdentityProvider,
    outcome: RoutineSyncTransportOutcome
  ) {
    self.provider = provider
    self.outcome = outcome
  }

  func execute(
    _: RoutineSyncTransportRequest
  ) async -> RoutineSyncTransportOutcome {
    await MainActor.run {
      guard let provider, let current = provider.identity else { return }
      provider.identity = AccountSessionIdentity(
        memberID: current.memberID,
        sessionID: UUID()
      )
    }
    return outcome
  }
}
