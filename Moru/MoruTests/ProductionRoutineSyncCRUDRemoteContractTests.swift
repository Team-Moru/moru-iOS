//
//  ProductionRoutineSyncCRUDRemoteContractTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
import Moya
@testable import Moru

@MainActor
final class ProductionRoutineSyncCRUDRemoteContractTests: XCTestCase {
  func testWireTargetUsesPersistedBytesAndGenerationKeyVerbatim() throws {
    let body = Data(#"{"clientEntityId":"private"}"#.utf8)
    let key = id("00000000-0000-0000-0000-000000000099")
    let target = RoutineSyncWireTarget(
      wireRequest: RoutineSyncWireRequest(
        method: .post,
        path: "/routine-groups",
        body: body
      ),
      idempotencyKey: key
    )

    XCTAssertEqual(target.method, .post)
    XCTAssertEqual(target.path, "/routine-groups")
    XCTAssertEqual(target.headers?["Idempotency-Key"], key.uuidString)
    XCTAssertEqual(target.headers?["Content-Type"], "application/json")
    XCTAssertNil(target.headers?["Authorization"])
    guard case .requestData(let requestBody) = target.task else {
      return XCTFail("Expected an exact byte request.")
    }
    XCTAssertEqual(requestBody, body)
  }

  func testCreatePersistsCanonicalProductionBodyWithEveryClientID()
    throws {
    let fixture = try makeFixture()
    let groupID = id("00000000-0000-0000-0000-000000000010")
    let checkID = id("00000000-0000-0000-0000-000000000011")
    let timerID = id("00000000-0000-0000-0000-000000000012")
    let inputID = id("00000000-0000-0000-0000-000000000013")
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: " 아침 ",
        summary: " 준비 ",
        isActive: true,
        alarm: RoutineSyncAlarmSnapshot(
          hour: 7,
          minute: 5,
          weekdays: [1, 7, 2, 3, 2],
          isEnabled: true,
          includeWeather: true
        ),
        routines: [
          snapshot(checkID, type: "confirm", duration: nil),
          snapshot(timerID, type: "timer", duration: 30),
          snapshot(inputID, type: "input", duration: nil),
        ]
      )
    )

    let wire = try prepare(
      command,
      fixture: fixture
    )
    let expected = Data(
      """
      {"alarmDays":"MON,TUE,SAT,SUN","alarmTime":"07:05","clientEntityId":"00000000-0000-0000-0000-000000000010","description":"준비","routines":[{"clientEntityId":"00000000-0000-0000-0000-000000000011","durationSecond":0,"title":"항목","type":"CHECK"},{"clientEntityId":"00000000-0000-0000-0000-000000000012","durationSecond":30,"title":"항목","type":"TIMER"},{"clientEntityId":"00000000-0000-0000-0000-000000000013","durationSecond":0,"title":"항목","type":"INPUT"}],"title":"아침","weatherNotificationEnabled":true}
      """.utf8
    )

    XCTAssertEqual(wire.method, .post)
    XCTAssertEqual(wire.path, "/routine-groups")
    XCTAssertTrue(wire.body == expected, "Canonical request body differs.")
  }

  func testInactiveAlarmOmitsScheduleAndForcesWeatherFalse() throws {
    let fixture = try makeFixture()
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: UUID(),
        name: "그룹",
        summary: " \n ",
        isActive: false,
        alarm: RoutineSyncAlarmSnapshot(
          hour: 99,
          minute: 99,
          weekdays: [99],
          isEnabled: true,
          includeWeather: true
        ),
        routines: [snapshot(UUID(), type: "confirm", duration: nil)]
      )
    )

    let wire = try prepare(command, fixture: fixture)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: wire.body) as? [String: Any]
    )

    XCTAssertNil(object["alarmDays"])
    XCTAssertNil(object["alarmTime"])
    XCTAssertNil(object["description"])
    XCTAssertEqual(object["weatherNotificationEnabled"] as? Bool, false)
  }

  func testAddUsesBoundParentAndCanonicalClientBody() throws {
    let fixture = try makeFixture()
    let groupID = UUID()
    let routineID = UUID()
    _ = try fixture.repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: .distantPast
    )
    let command = RoutineSyncCommand.addRoutine(
      groupLocalID: groupID,
      routine: snapshot(routineID, type: "timer", duration: 45)
    )

    let wire = try prepare(command, fixture: fixture)
    let expected = Data(
      """
      {"clientEntityId":"\(routineID.uuidString.lowercased())","durationSecond":45,"title":"항목","type":"TIMER"}
      """.utf8
    )

    XCTAssertEqual(wire.method, .post)
    XCTAssertEqual(wire.path, "/routine-groups/41/routines")
    XCTAssertTrue(wire.body == expected, "Canonical request body differs.")
  }

  func testRequestPreparationFailsClosedForMissingParentAndInvalidDuration()
    throws {
    let missingFixture = try makeFixture()
    let missingParent = RoutineSyncCommand.addRoutine(
      groupLocalID: UUID(),
      routine: snapshot(UUID(), type: "confirm", duration: nil)
    )
    assertPrepareError(.missingServerBinding) {
      try self.prepare(missingParent, fixture: missingFixture)
    }

    let timerFixture = try makeFixture()
    let timer = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: UUID(),
        name: "그룹",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: [snapshot(UUID(), type: "timer", duration: nil)]
      )
    )
    assertPrepareError(.invalidLocalSnapshot) {
      try self.prepare(timer, fixture: timerFixture)
    }

    let overflowFixture = try makeFixture()
    let overflow = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: UUID(),
        name: "그룹",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: [
          snapshot(
            UUID(),
            type: "input",
            duration: Int(Int32.max) + 1
          ),
        ]
      )
    )
    assertPrepareError(.invalidLocalSnapshot) {
      try self.prepare(overflow, fixture: overflowFixture)
    }
  }

  func testDeleteRequestsRequireBindingsAndHaveNoBody() throws {
    let fixture = try makeFixture()
    let groupID = UUID()
    let routineID = UUID()
    _ = try fixture.repository.recordRemoteIDs(
      [
        RoutineServerBindingAssignment(
          entityKind: .routineGroup,
          localEntityID: groupID,
          remoteID: 41
        ),
        RoutineServerBindingAssignment(
          entityKind: .routine,
          localEntityID: routineID,
          remoteID: 51,
          parentEntityKind: .routineGroup,
          parentLocalEntityID: groupID
        ),
      ],
      memberID: 7,
      at: .distantPast
    )

    let deleteGroup = try prepare(
      .deleteRoutineGroup(groupLocalID: groupID),
      fixture: fixture
    )
    let deleteRoutine = try prepare(
      .deleteRoutine(
        groupLocalID: groupID,
        routineLocalID: routineID
      ),
      fixture: fixture
    )

    XCTAssertEqual(deleteGroup.method, .delete)
    XCTAssertEqual(deleteGroup.path, "/routine-groups/41")
    XCTAssertTrue(deleteGroup.body.isEmpty)
    XCTAssertEqual(deleteRoutine.method, .delete)
    XCTAssertEqual(deleteRoutine.path, "/routines/51")
    XCTAssertTrue(deleteRoutine.body.isEmpty)
  }

  func testCreateResponseProducesCompleteUniqueParentedAssignments()
    throws {
    let fixture = try makeFixture()
    let groupID = UUID()
    let checkID = UUID()
    let inputID = UUID()
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: "그룹",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: [
          snapshot(checkID, type: "confirm", duration: nil),
          snapshot(inputID, type: "input", duration: 10),
        ]
      )
    )
    let request = try transportRequest(command, fixture: fixture)
    let response = successEnvelope(
      code: "COMMON201",
      result: """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":51,"clientEntityId":"\(checkID)","type":"CHECK"},{"routineId":52,"clientEntityId":"\(inputID)","type":"INPUT"}]}
      """
    )

    let commit = try ProductionRoutineSyncResponseDecoder().decodeCommit(
      for: request,
      from: response
    )
    guard case .createRoutineGroup(let assignments) = commit else {
      return XCTFail("Expected a complete group mapping.")
    }

    XCTAssertEqual(assignments.count, 3)
    XCTAssertEqual(assignments[0].localEntityID, groupID)
    XCTAssertEqual(assignments[0].remoteID, 41)
    XCTAssertEqual(assignments[1].parentLocalEntityID, groupID)
    XCTAssertEqual(assignments[2].parentLocalEntityID, groupID)
  }

  func testCreateResponseRejectsIncompleteUnexpectedDuplicateAndWrongTypeMappings()
    throws {
    let fixture = try makeFixture()
    let groupID = UUID()
    let firstID = UUID()
    let secondID = UUID()
    let unexpectedID = UUID()
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: "그룹",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: [
          snapshot(firstID, type: "confirm", duration: nil),
          snapshot(secondID, type: "timer", duration: 10),
        ]
      )
    )
    let request = try transportRequest(command, fixture: fixture)
    let invalidResults = [
      // Missing mapping.
      """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":51,"clientEntityId":"\(firstID)","type":"CHECK"}]}
      """,
      // Unexpected client ID.
      """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":51,"clientEntityId":"\(firstID)","type":"CHECK"},{"routineId":52,"clientEntityId":"\(unexpectedID)","type":"TIMER"}]}
      """,
      // Duplicate client ID.
      """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":51,"clientEntityId":"\(firstID)","type":"CHECK"},{"routineId":52,"clientEntityId":"\(firstID)","type":"CHECK"}]}
      """,
      // Duplicate child server ID.
      """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":51,"clientEntityId":"\(firstID)","type":"CHECK"},{"routineId":51,"clientEntityId":"\(secondID)","type":"TIMER"}]}
      """,
      // Cross-kind duplicate server ID.
      """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":41,"clientEntityId":"\(firstID)","type":"CHECK"},{"routineId":52,"clientEntityId":"\(secondID)","type":"TIMER"}]}
      """,
      // Type mismatch.
      """
      {"routineGroupId":41,"clientEntityId":"\(groupID)","routines":[{"routineId":51,"clientEntityId":"\(firstID)","type":"INPUT"},{"routineId":52,"clientEntityId":"\(secondID)","type":"TIMER"}]}
      """,
    ]

    for result in invalidResults {
      assertDecodeError(.invalidResponse) {
        try ProductionRoutineSyncResponseDecoder().decodeCommit(
          for: request,
          from: self.successEnvelope(code: "COMMON201", result: result)
        )
      }
    }
  }

  func testAddResponseValidatesClientTypeIDAndParentRemoteID() throws {
    let fixture = try makeFixture()
    let groupID = UUID()
    let routineID = UUID()
    _ = try fixture.repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: .distantPast
    )
    let command = RoutineSyncCommand.addRoutine(
      groupLocalID: groupID,
      routine: snapshot(routineID, type: "timer", duration: 10)
    )
    let request = try transportRequest(command, fixture: fixture)
    let validResponse = successEnvelope(
      code: "COMMON201",
      result: """
      {"routineId":51,"clientEntityId":"\(routineID)","type":"TIMER"}
      """
    )

    let commit = try ProductionRoutineSyncResponseDecoder().decodeCommit(
      for: request,
      from: validResponse
    )
    guard case .mutation(let assignments) = commit else {
      return XCTFail("Expected one child mapping.")
    }
    XCTAssertEqual(assignments.first?.parentLocalEntityID, groupID)
    XCTAssertEqual(assignments.first?.remoteID, 51)

    let invalidResults = [
      """
      {"routineId":51,"clientEntityId":"\(UUID())","type":"TIMER"}
      """,
      """
      {"routineId":51,"clientEntityId":"\(routineID)","type":"CHECK"}
      """,
      """
      {"routineId":0,"clientEntityId":"\(routineID)","type":"TIMER"}
      """,
      """
      {"routineId":41,"clientEntityId":"\(routineID)","type":"TIMER"}
      """,
    ]
    for result in invalidResults {
      assertDecodeError(.invalidResponse) {
        try ProductionRoutineSyncResponseDecoder().decodeCommit(
          for: request,
          from: self.successEnvelope(code: "COMMON201", result: result)
        )
      }
    }
  }

  func testDeleteResponsesRequireOperationSpecificExactID() throws {
    let fixture = try makeFixture()
    let groupID = UUID()
    _ = try fixture.repository.recordRemoteID(
      41,
      revision: nil,
      memberID: 7,
      entityKind: .routineGroup,
      localEntityID: groupID,
      at: .distantPast
    )
    let request = try transportRequest(
      .deleteRoutineGroup(groupLocalID: groupID),
      fixture: fixture
    )

    let commit = try ProductionRoutineSyncResponseDecoder().decodeCommit(
      for: request,
      from: successEnvelope(
        code: "COMMON200",
        result: #"{"routineGroupId":41}"#
      )
    )
    XCTAssertEqual(commit, .deleted)

    for result in [
      #"{"routineGroupId":42}"#,
      #"{"routineId":41}"#,
      #"{"routineGroupId":41,"routineId":41}"#,
      #"{}"#,
    ] {
      assertDecodeError(.invalidResponse) {
        try ProductionRoutineSyncResponseDecoder().decodeCommit(
          for: request,
          from: self.successEnvelope(code: "COMMON200", result: result)
        )
      }
    }
  }

  func testFailureEnvelopeClassificationIgnoresArbitraryResultShape()
    throws {
    let fixture = try makeFixture()
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: UUID(),
        name: "그룹",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: [snapshot(UUID(), type: "confirm", duration: nil)]
      )
    )
    let request = try transportRequest(command, fixture: fixture)
    let cases: [(String, RoutineSyncResponseDecodingError)] = [
      ("COMMON409", .processingConflict),
      ("COMMON410", .idempotencyPayloadConflict),
      ("ROUTINE4001", .definitiveServerRejection),
    ]

    for (code, expectedError) in cases {
      let response = Data(
        """
        {"isSuccess":false,"code":"\(code)","message":"ignored","result":[{"unknown":true}]}
        """.utf8
      )
      assertDecodeError(expectedError) {
        try ProductionRoutineSyncResponseDecoder().decodeCommit(
          for: request,
          from: response
        )
      }
    }
  }

  private func makeFixture() throws -> CRUDRemoteFixture {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineSyncRepository(
      modelContext: container.mainContext
    )
    return CRUDRemoteFixture(
      container: container,
      repository: repository,
      preparer: ProductionRoutineSyncRequestPreparer(
        repository: repository
      )
    )
  }

  private func prepare(
    _ command: RoutineSyncCommand,
    fixture: CRUDRemoteFixture
  ) throws -> RoutineSyncWireRequest {
    let mutation = try fixture.repository.enqueue(
      command: command,
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    return try fixture.preparer.makeWireRequest(
      for: command,
      mutation: mutation
    )
  }

  private func transportRequest(
    _ command: RoutineSyncCommand,
    fixture: CRUDRemoteFixture
  ) throws -> RoutineSyncTransportRequest {
    let mutation = try fixture.repository.enqueue(
      command: command,
      memberID: 7,
      at: Date(timeIntervalSince1970: 1)
    )
    let wire = try fixture.preparer.makeWireRequest(
      for: command,
      mutation: mutation
    )
    return RoutineSyncTransportRequest(
      serverNamespace: .production,
      memberID: 7,
      operation: command.operation,
      command: command,
      idempotencyKey: mutation.generationID,
      generation: mutation.generation,
      payloadVersion: mutation.payloadVersion,
      wireRequest: wire,
      sessionIdentity: nil
    )
  }

  private func snapshot(
    _ localID: UUID,
    type: String,
    duration: Int?
  ) -> RoutineSyncRoutineSnapshot {
    RoutineSyncRoutineSnapshot(
      localID: localID,
      title: "항목",
      type: type,
      durationSeconds: duration,
      order: 0
    )
  }

  private func successEnvelope(code: String, result: String) -> Data {
    Data(
      """
      {"isSuccess":true,"code":"\(code)","message":"ok","result":\(result)}
      """.utf8
    )
  }

  private func id(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }

  private func assertPrepareError(
    _ expected: RoutineSyncRequestPreparingError,
    action: () throws -> RoutineSyncWireRequest
  ) {
    XCTAssertThrowsError(try action()) { error in
      XCTAssertEqual(error as? RoutineSyncRequestPreparingError, expected)
    }
  }

  private func assertDecodeError(
    _ expected: RoutineSyncResponseDecodingError,
    action: () throws -> RoutineSyncTransportCommit
  ) {
    XCTAssertThrowsError(try action()) { error in
      XCTAssertEqual(error as? RoutineSyncResponseDecodingError, expected)
    }
  }
}

@MainActor
private struct CRUDRemoteFixture {
  let container: ModelContainer
  let repository: SwiftDataRoutineSyncRepository
  let preparer: ProductionRoutineSyncRequestPreparer
}
