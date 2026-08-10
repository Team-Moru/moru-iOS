//
//  RoutineSyncSenderTests.swift
//  MoruTests
//

import SwiftData
import XCTest
@testable import Moru

final class RoutineSyncSenderTests: XCTestCase {
  @MainActor
  func testUnavailableContractNeverCallsTransport() async throws {
    let fixture = try makeFixture(actions: [])
    _ = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID(), children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = RoutineSyncSender(
      repository: fixture.repository,
      transport: fixture.transport,
      contract: .unavailable
    )

    let sendResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(sendResult, .idle)
    let requests = await fixture.transport.requests()
    XCTAssertEqual(requests, [])
    XCTAssertEqual(
      try fixture.repository.mutations(memberID: 7).first?.state,
      .waitingForServerContract
    )
  }

  @MainActor
  func testCreateUsesGenerationAsIdempotencyKeyAndSettlesBindings() async throws {
    let groupID = UUID()
    let childID = UUID()
    let fixture = try makeFixture(actions: [
      .outcome(
        .committed(
          .createRoutineGroup(
            assignments: [
              RoutineServerBindingAssignment(
                entityKind: .routineGroup,
                localEntityID: groupID,
                remoteID: 41
              ),
              RoutineServerBindingAssignment(
                entityKind: .routine,
                localEntityID: childID,
                remoteID: 51,
                parentEntityKind: .routineGroup,
                parentLocalEntityID: groupID
              ),
            ],
            childMappingsComplete: true
          )
        )
      )
    ])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: groupID, children: [childID]),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeVerifiedSender(fixture)

    let sendResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(sendResult, .completed(mutationID: mutation.id))
    let requests = await fixture.transport.requests()
    let request = try XCTUnwrap(requests.first)
    XCTAssertEqual(request.idempotencyKey, mutation.generationID)
    XCTAssertEqual(request.operation, .createRoutineGroup)
    XCTAssertEqual(
      try fixture.repository.binding(
        memberID: 7,
        entityKind: .routineGroup,
        localEntityID: groupID
      )?.remoteID,
      41
    )
    XCTAssertEqual(
      try fixture.repository.binding(
        memberID: 7,
        entityKind: .routine,
        localEntityID: childID
      )?.remoteID,
      51
    )
    XCTAssertTrue(try fixture.repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  func testAmbiguousTransportResultNeverRetriesAndRequiresReconciliation() async throws {
    let fixture = try makeFixture(actions: [.outcome(.ambiguous)])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID(), children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeVerifiedSender(fixture)

    let firstResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(firstResult, .needsReconciliation(mutationID: mutation.id))
    let stored = try XCTUnwrap(try fixture.repository.mutations(memberID: 7).first)
    XCTAssertEqual(stored.state, .needsReconciliation)
    XCTAssertEqual(stored.attempt?.generationID, mutation.generationID)
    var requests = await fixture.transport.requests()
    XCTAssertEqual(requests.count, 1)
    let secondResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    XCTAssertEqual(secondResult, .idle)
    requests = await fixture.transport.requests()
    XCTAssertEqual(requests.count, 1)
  }

  @MainActor
  func testReconciliationLookupDoesNotResendAndReleasesProvenUncommittedAttempt() async throws {
    let fixture = try makeFixture(actions: [
      .outcome(.ambiguous),
      .outcome(.notCommitted),
    ])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID(), children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeVerifiedSender(fixture)

    let sendResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(sendResult, .needsReconciliation(mutationID: mutation.id))
    let reconcileResult = try await sender.reconcileNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 3)
    )
    XCTAssertEqual(reconcileResult, .notCommitted(mutationID: mutation.id))

    let callKinds = await fixture.transport.callKinds()
    let idempotencyKeys = await fixture.transport.idempotencyKeys()
    XCTAssertEqual(callKinds, [.execute, .reconcile])
    XCTAssertEqual(idempotencyKeys, [
      mutation.generationID,
      mutation.generationID,
    ])
    let stored = try XCTUnwrap(try fixture.repository.mutations(memberID: 7).first)
    XCTAssertEqual(stored.state, .waitingForServerContract)
    XCTAssertNil(stored.attempt)
  }

  @MainActor
  func testReconciliationNotCommittedReleasesSameGenerationForFutureAdmission() async throws {
    let fixture = try makeFixture(actions: [.outcome(.notCommitted)])
    let mutation = try fixture.repository.enqueue(
      command: createCommand(groupID: UUID(), children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let sender = makeVerifiedSender(fixture)

    let sendResult = try await sender.sendNext(
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(sendResult, .notCommitted(mutationID: mutation.id))
    let stored = try XCTUnwrap(try fixture.repository.mutations(memberID: 7).first)
    XCTAssertEqual(stored.state, .waitingForServerContract)
    XCTAssertEqual(stored.generationID, mutation.generationID)
    XCTAssertNil(stored.attempt)
  }

  @MainActor
  func testSenderExecutesCreateBeforeDependentAdd() async throws {
    let groupID = UUID()
    let childID = UUID()
    let fixture = try makeFixture(actions: [
      .outcome(
        .committed(
          .createRoutineGroup(
            assignments: [
              RoutineServerBindingAssignment(
                entityKind: .routineGroup,
                localEntityID: groupID,
                remoteID: 41
              )
            ],
            childMappingsComplete: true
          )
        )
      ),
      .outcome(
        .committed(
          .mutation(
            assignments: [
              RoutineServerBindingAssignment(
                entityKind: .routine,
                localEntityID: childID,
                remoteID: 51,
                parentEntityKind: .routineGroup,
                parentLocalEntityID: groupID
              )
            ]
          )
        )
      ),
    ])
    _ = try fixture.repository.enqueue(
      command: createCommand(groupID: groupID, children: []),
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    _ = try fixture.repository.enqueue(
      command: .addRoutine(
        groupLocalID: groupID,
        routine: RoutineSyncRoutineSnapshot(
          localID: childID,
          title: "추가",
          type: "confirm",
          durationSeconds: nil,
          order: 0
        )
      ),
      memberID: 7,
      at: Date(timeIntervalSince1970: 2)
    )
    let sender = makeVerifiedSender(fixture)

    _ = try await sender.sendNext(memberID: 7, at: Date(timeIntervalSince1970: 3))
    _ = try await sender.sendNext(memberID: 7, at: Date(timeIntervalSince1970: 4))

    let operations = await fixture.transport.requests().map(\.operation)
    XCTAssertEqual(operations, [.createRoutineGroup, .addRoutine])
    XCTAssertTrue(try fixture.repository.mutations(memberID: 7).isEmpty)
  }

  @MainActor
  private func makeFixture(
    actions: [RoutineSyncTransportStub.Action]
  ) throws -> RoutineSyncSenderFixture {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    return RoutineSyncSenderFixture(
      container: container,
      repository: SwiftDataRoutineSyncRepository(modelContext: container.mainContext),
      transport: RoutineSyncTransportStub(actions: actions)
    )
  }

  @MainActor
  private func makeVerifiedSender(_ fixture: RoutineSyncSenderFixture) -> RoutineSyncSender {
    RoutineSyncSender(
      repository: fixture.repository,
      transport: fixture.transport,
      contract: RoutineSyncServerContract(
        capabilities: .allRequired,
        isE2EVerified: true
      )
    )
  }

  private func createCommand(groupID: UUID, children: [UUID]) -> RoutineSyncCommand {
    .createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: "그룹",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: children.enumerated().map { index, childID in
          RoutineSyncRoutineSnapshot(
            localID: childID,
            title: "단계",
            type: "confirm",
            durationSeconds: nil,
            order: index
          )
        }
      )
    )
  }
}

private struct RoutineSyncSenderFixture {
  let container: ModelContainer
  let repository: SwiftDataRoutineSyncRepository
  let transport: RoutineSyncTransportStub
}

private actor RoutineSyncTransportStub: RoutineSyncTransport {
  enum CallKind: Equatable, Sendable {
    case execute
    case reconcile
  }

  enum Action: Sendable {
    case outcome(RoutineSyncTransportOutcome)
    case failure
  }

  private var actions: [Action]
  private var capturedExecuteRequests: [RoutineSyncTransportRequest] = []
  private var capturedReconciliationRequests: [RoutineSyncReconciliationRequest] = []
  private var capturedCallKinds: [CallKind] = []
  private var capturedIdempotencyKeys: [UUID] = []

  init(actions: [Action]) {
    self.actions = actions
  }

  func execute(
    _ request: RoutineSyncTransportRequest
  ) async throws -> RoutineSyncTransportOutcome {
    capturedExecuteRequests.append(request)
    capturedCallKinds.append(.execute)
    capturedIdempotencyKeys.append(request.idempotencyKey)
    return try nextOutcome()
  }

  func reconcile(
    _ request: RoutineSyncReconciliationRequest
  ) async throws -> RoutineSyncTransportOutcome {
    capturedReconciliationRequests.append(request)
    capturedCallKinds.append(.reconcile)
    capturedIdempotencyKeys.append(request.idempotencyKey)
    return try nextOutcome()
  }

  func requests() -> [RoutineSyncTransportRequest] {
    capturedExecuteRequests
  }

  func callKinds() -> [CallKind] {
    capturedCallKinds
  }

  func idempotencyKeys() -> [UUID] {
    capturedIdempotencyKeys
  }

  private func nextOutcome() throws -> RoutineSyncTransportOutcome {
    guard !actions.isEmpty else { throw StubError.noAction }
    switch actions.removeFirst() {
    case .outcome(let outcome):
      return outcome
    case .failure:
      throw StubError.transport
    }
  }

  private enum StubError: Error {
    case noAction
    case transport
  }
}
