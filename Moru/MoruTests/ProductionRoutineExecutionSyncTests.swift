//
//  ProductionRoutineExecutionSyncTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class ProductionRoutineExecutionSyncTests: XCTestCase {
  @MainActor
  func testExecutionLiveRequestAndResponseSettleDurableReceipt() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let routine = makeRoutine()
    try bindRoutine(routine, in: sync)
    let result = makeResult(step: routine.steps[0])
    let execution = RoutineSyncExecutionSnapshot(
      runLocalID: UUID(),
      groupLocalID: routine.id,
      routineLocalID: routine.steps[0].id,
      runStartedAt: Date(timeIntervalSince1970: 0),
      runCompletedAt: Date(timeIntervalSince1970: 30),
      timeZoneIdentifier: "Asia/Seoul",
      result: RoutineSyncExecutionResultSnapshot(
        localID: result.id,
        completedAt: result.completedAt,
        skipped: false,
        durationSeconds: 12,
        inputText: nil,
        transcript: nil
      )
    )
    let command = RoutineSyncCommand.saveRoutineExecution(execution)
    let mutation = try sync.enqueue(
      command: command,
      memberID: 7,
      at: Date(timeIntervalSince1970: 40)
    )
    let wire = try ProductionRoutineSyncRequestPreparer(
      repository: sync
    ).makeWireRequest(for: command, mutation: mutation)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: wire.body) as? [String: Any]
    )

    XCTAssertEqual(wire.method, .post)
    XCTAssertEqual(wire.path, "/routine-executions")
    XCTAssertEqual(object["executedDate"] as? String, "1970-01-01")
    XCTAssertEqual(object["routineId"] as? Int, 51)
    XCTAssertEqual(object["durationSecond"] as? Int, 12)
    XCTAssertEqual(object["isCompleted"] as? Bool, true)
    XCTAssertNil(object["memberInput"])
    XCTAssertNil(object["aiResponse"])
    XCTAssertNil(object["actualWakeTime"])

    let request = RoutineSyncTransportRequest(
      serverNamespace: .production,
      memberID: 7,
      operation: .saveRoutineExecution,
      command: command,
      idempotencyKey: mutation.generationID,
      generation: mutation.generation,
      payloadVersion: mutation.payloadVersion,
      wireRequest: wire,
      sessionIdentity: nil
    )
    let response = Data(
      """
      {"isSuccess":true,"code":"COMMON201","message":"ok","result":{"executedDate":"1970-01-01","executionId":61,"routineId":51,"durationSecond":12,"isCompleted":true}}
      """.utf8
    )
    let commit = try ProductionRoutineSyncResponseDecoder().decodeCommit(
      for: request,
      from: response
    )
    guard case .mutation(let assignments) = commit else {
      return XCTFail("Expected one execution receipt assignment.")
    }
    try sync.completeMutation(
      id: mutation.id,
      expectedGenerationID: mutation.generationID,
      assignments: assignments,
      at: Date(timeIntervalSince1970: 41)
    )

    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(
      try sync.binding(
        memberID: 7,
        entityKind: .routineExecution,
        localEntityID: result.id
      )?.remoteID,
      61
    )
  }

  @MainActor
  func testExecutionResponseIdentityMismatchNeverProducesReceipt() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let routine = makeRoutine()
    try bindRoutine(routine, in: sync)
    let result = makeResult(step: routine.steps[0])
    let execution = RoutineSyncExecutionSnapshot(
      runLocalID: UUID(),
      groupLocalID: routine.id,
      routineLocalID: routine.steps[0].id,
      runStartedAt: Date(timeIntervalSince1970: 0),
      runCompletedAt: Date(timeIntervalSince1970: 30),
      timeZoneIdentifier: "UTC",
      result: RoutineSyncExecutionResultSnapshot(
        localID: result.id,
        completedAt: result.completedAt,
        skipped: false,
        durationSeconds: 12,
        inputText: nil,
        transcript: nil
      )
    )
    let command = RoutineSyncCommand.saveRoutineExecution(execution)
    let mutation = try sync.enqueue(command: command, memberID: 7)
    let wire = try ProductionRoutineSyncRequestPreparer(
      repository: sync
    ).makeWireRequest(for: command, mutation: mutation)
    let request = RoutineSyncTransportRequest(
      serverNamespace: .production,
      memberID: 7,
      operation: .saveRoutineExecution,
      command: command,
      idempotencyKey: mutation.generationID,
      generation: mutation.generation,
      payloadVersion: mutation.payloadVersion,
      wireRequest: wire,
      sessionIdentity: nil
    )
    let invalidResults = [
      #"{"executedDate":"1970-01-01","executionId":61,"routineId":52,"durationSecond":12,"isCompleted":true}"#,
      #"{"executedDate":"1970-01-02","executionId":61,"routineId":51,"durationSecond":12,"isCompleted":true}"#,
      #"{"executedDate":"1970-01-01","executionId":0,"routineId":51,"durationSecond":12,"isCompleted":true}"#,
      #"{"executedDate":"1970-01-01","executionId":61,"routineId":51,"durationSecond":12,"isCompleted":false}"#,
    ]

    for resultJSON in invalidResults {
      let response = Data(
        """
        {"isSuccess":true,"code":"COMMON201","message":"ok","result":\(resultJSON)}
        """.utf8
      )
      XCTAssertThrowsError(
        try ProductionRoutineSyncResponseDecoder().decodeCommit(
          for: request,
          from: response
        )
      ) { error in
        XCTAssertEqual(
          error as? RoutineSyncResponseDecodingError,
          .invalidResponse
        )
      }
    }
    XCTAssertNil(
      try sync.binding(
        memberID: 7,
        entityKind: .routineExecution,
        localEntityID: result.id
      )
    )
    XCTAssertEqual(try sync.mutations(memberID: 7).map(\.id), [mutation.id])
  }

  @MainActor
  func testSettledExecutionBindingPreventsSameResultFromBeingEnqueuedAgain() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let member = ExecutionSyncMemberProvider(memberID: 7)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let runs = SwiftDataRoutineRunRepository(
      modelContext: container.mainContext,
      routineSyncRepository: sync,
      signedInMemberProvider: member
    )
    let routine = makeRoutine()
    let firstResult = makeResult(step: routine.steps[0])
    var run = makeRun(routine: routine, results: [firstResult])
    try bindRoutine(routine, in: sync)

    try runs.saveRun(run)
    let firstMutation = try XCTUnwrap(
      try sync.mutation(
        memberID: 7,
        operation: .saveRoutineExecution,
        entityKind: .routineExecution,
        localEntityID: firstResult.id
      )
    )

    // An unchanged pre-settlement save reuses the one existing generation.
    try runs.saveRun(run)
    let repeatedMutation = try XCTUnwrap(
      try sync.mutation(
        memberID: 7,
        operation: .saveRoutineExecution,
        entityKind: .routineExecution,
        localEntityID: firstResult.id
      )
    )
    XCTAssertEqual(repeatedMutation.id, firstMutation.id)
    XCTAssertEqual(repeatedMutation.generationID, firstMutation.generationID)
    XCTAssertEqual(repeatedMutation.generation, firstMutation.generation)

    // Successful settlement persists the execution binding and removes its
    // Outbox row in the same repository transaction.
    try sync.completeMutation(
      id: firstMutation.id,
      expectedGenerationID: firstMutation.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineExecution,
          localEntityID: firstResult.id,
          remoteID: 61,
          parentEntityKind: .routine,
          parentLocalEntityID: routine.steps[0].id
        )
      ],
      at: Date(timeIntervalSince1970: 40)
    )
    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)

    // Force the run repository's projection scan again. The durable receipt,
    // not an in-memory flag, suppresses the already-settled result.
    run.completedAt = Date(timeIntervalSince1970: 31)
    try runs.saveRun(run)
    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)

    // A genuinely new result UUID remains a new server mutation identity.
    let secondResult = makeResult(
      id: UUID(),
      step: routine.steps[0],
      completedAt: Date(timeIntervalSince1970: 31)
    )
    run.results.append(secondResult)
    try runs.saveRun(run)
    let secondMutation = try XCTUnwrap(
      try sync.mutation(
        memberID: 7,
        operation: .saveRoutineExecution,
        entityKind: .routineExecution,
        localEntityID: secondResult.id
      )
    )
    XCTAssertNotEqual(secondMutation.id, firstMutation.id)
    XCTAssertNotEqual(secondMutation.generationID, firstMutation.generationID)
    XCTAssertEqual(secondMutation.generation, 1)
    XCTAssertEqual(
      try sync.binding(
        memberID: 7,
        entityKind: .routineExecution,
        localEntityID: firstResult.id
      )?.remoteID,
      61
    )
  }

  @MainActor
  func testExecutionEditedWhileAttemptingSettlesOnceWithoutSuccessorPOST()
    throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let routine = makeRoutine()
    try bindRoutine(routine, in: sync)
    let result = makeResult(step: routine.steps[0])
    let first = RoutineSyncExecutionSnapshot(
      runLocalID: UUID(),
      groupLocalID: routine.id,
      routineLocalID: routine.steps[0].id,
      runStartedAt: Date(timeIntervalSince1970: 10),
      runCompletedAt: Date(timeIntervalSince1970: 30),
      timeZoneIdentifier: "UTC",
      result: RoutineSyncExecutionResultSnapshot(
        localID: result.id,
        completedAt: result.completedAt,
        skipped: false,
        durationSeconds: 12,
        inputText: nil,
        transcript: nil
      )
    )
    let mutation = try sync.enqueue(
      command: .saveRoutineExecution(first),
      memberID: 7,
      at: Date(timeIntervalSince1970: 31)
    )
    _ = try sync.admitEligibleMutations(
      memberID: 7,
      contract: .productionP0,
      at: Date(timeIntervalSince1970: 32)
    )
    let wire = try ProductionRoutineSyncRequestPreparer(
      repository: sync
    ).makeWireRequest(
      for: .saveRoutineExecution(first),
      mutation: mutation
    )
    let attempt = try XCTUnwrap(
      sync.claimForDelivery(
        id: mutation.id,
        wireRequest: wire,
        at: Date(timeIntervalSince1970: 33)
      )
    )

    let edited = RoutineSyncExecutionSnapshot(
      runLocalID: first.runLocalID,
      groupLocalID: first.groupLocalID,
      routineLocalID: first.routineLocalID,
      runStartedAt: first.runStartedAt,
      runCompletedAt: first.runCompletedAt,
      timeZoneIdentifier: first.timeZoneIdentifier,
      result: RoutineSyncExecutionResultSnapshot(
        localID: first.result.localID,
        completedAt: first.result.completedAt,
        skipped: first.result.skipped,
        durationSeconds: first.result.durationSeconds,
        inputText: first.result.inputText,
        transcript: "local-only edit"
      )
    )
    let successor = try sync.enqueue(
      command: .saveRoutineExecution(edited),
      memberID: 7,
      at: Date(timeIntervalSince1970: 34)
    )
    XCTAssertNotEqual(successor.generationID, attempt.generationID)
    XCTAssertEqual(successor.state, .attempting)

    try sync.completeMutation(
      id: mutation.id,
      expectedGenerationID: attempt.generationID,
      assignments: [
        RoutineServerBindingAssignment(
          entityKind: .routineExecution,
          localEntityID: result.id,
          remoteID: 61,
          parentEntityKind: .routine,
          parentLocalEntityID: routine.steps[0].id
        )
      ],
      at: Date(timeIntervalSince1970: 35)
    )

    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)
    XCTAssertEqual(
      try sync.binding(
        memberID: 7,
        entityKind: .routineExecution,
        localEntityID: result.id
      )?.remoteID,
      61
    )
  }

  @MainActor
  func testExecutionReceiptIsAccountScopedAndDoesNotChangeOfflineOrUnboundFlow() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let member = ExecutionSyncMemberProvider(memberID: nil)
    let sync = SwiftDataRoutineSyncRepository(modelContext: container.mainContext)
    let runs = SwiftDataRoutineRunRepository(
      modelContext: container.mainContext,
      routineSyncRepository: sync,
      signedInMemberProvider: member
    )
    let routine = makeRoutine()
    let result = makeResult(step: routine.steps[0])
    var run = makeRun(routine: routine, results: [result])

    try runs.saveRun(run)
    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)

    member.signedInMemberID = 7
    run.completedAt = Date(timeIntervalSince1970: 31)
    try runs.saveRun(run)
    XCTAssertTrue(try sync.mutations(memberID: 7).isEmpty)

    try bindRoutine(routine, in: sync)
    run.completedAt = Date(timeIntervalSince1970: 32)
    try runs.saveRun(run)
    XCTAssertEqual(
      try sync.mutations(memberID: 7).map(\.localEntityID),
      [result.id]
    )
  }

  @MainActor
  private func bindRoutine(
    _ routine: Routine,
    in repository: SwiftDataRoutineSyncRepository
  ) throws {
    _ = try repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: routine.id,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: routine.steps[0].id,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: routine.id
        ),
      ],
      memberID: 7,
      at: Date(timeIntervalSince1970: 5)
    )
  }

  @MainActor
  private func makeRoutine() -> Routine {
    Routine(
      name: "실행 동기화",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 마시기",
          order: 0
        )
      ],
      isActive: false,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1)
    )
  }

  @MainActor
  private func makeResult(
    id: UUID = UUID(),
    step: RoutineStep,
    completedAt: Date = Date(timeIntervalSince1970: 30)
  ) -> RoutineStepResult {
    RoutineStepResult(
      id: id,
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: completedAt,
      durationSeconds: 12
    )
  }

  @MainActor
  private func makeRun(
    routine: Routine,
    results: [RoutineStepResult]
  ) -> RoutineRun {
    RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 20),
      completedAt: Date(timeIntervalSince1970: 30),
      results: results
    )
  }
}

@MainActor
private final class ExecutionSyncMemberProvider: SignedInMemberProviding {
  var signedInMemberID: Int64?

  init(memberID: Int64?) {
    signedInMemberID = memberID
  }
}
