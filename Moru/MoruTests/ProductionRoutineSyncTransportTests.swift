//
//  ProductionRoutineSyncTransportTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

final class ProductionRoutineSyncTransportTests: XCTestCase {
  func testConflictAndHTTPStatusClassificationUsesMachineFieldsOnly()
    async throws {
    let cases: [(APIError, RoutineSyncTransportOutcome)] = [
      (
        .server(statusCode: 409, code: "COMMON409", message: "ignored"),
        .processingConflict
      ),
      (
        .server(statusCode: 409, code: "COMMON410", message: "ignored"),
        .blocked(.idempotencyPayloadConflict)
      ),
      (
        .server(statusCode: 409, code: "OTHER", message: "COMMON409"),
        .blocked(.unknownConflict)
      ),
      (
        .server(statusCode: 503, code: "COMMON503", message: "ignored"),
        .ambiguous
      ),
      (
        .server(statusCode: 400, code: "COMMON400", message: "ignored"),
        .blocked(.definitiveServerRejection)
      ),
    ]

    for (error, expected) in cases {
      let client = FailingRoutineSyncAPIClient(error: error)
      let transport = ProductionRoutineSyncTransport(
        apiClient: client,
        responseDecoder: UnusedRoutineSyncResponseDecoder()
      )
      let outcome = await transport.execute(makeRequest())
      XCTAssertEqual(outcome, expected)
    }
  }

  private func makeRequest() -> RoutineSyncTransportRequest {
    let groupID = UUID()
    let command = RoutineSyncCommand.createRoutineGroup(
      RoutineSyncGroupSnapshot(
        localID: groupID,
        name: "fixture",
        summary: "",
        isActive: false,
        alarm: nil,
        routines: []
      )
    )
    return RoutineSyncTransportRequest(
      serverNamespace: .production,
      memberID: 7,
      operation: .createRoutineGroup,
      command: command,
      idempotencyKey: UUID(),
      generation: 1,
      payloadVersion: 1,
      wireRequest: RoutineSyncWireRequest(
        method: .post,
        path: "/routine-groups",
        body: Data(#"{"fixture":true}"#.utf8)
      ),
      sessionIdentity: AccountSessionIdentity(
        memberID: 7,
        sessionID: UUID()
      )
    )
  }
}

private actor FailingRoutineSyncAPIClient: AccountBoundAPIClient {
  private let error: APIError

  init(error: APIError) {
    self.error = error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type
  ) async throws -> Payload {
    throw error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _: Target,
    as _: Payload.Type,
    authorizedForMemberID _: Int64
  ) async throws -> Payload {
    throw error
  }

  func requestVoid<Target: MoruTargetType>(_: Target) async throws {
    throw error
  }

  func requestData<Target: MoruTargetType>(_: Target) async throws -> Data {
    throw error
  }

  func requestData<Target: MoruTargetType>(
    _: Target,
    authorizedFor _: AccountSessionIdentity
  ) async throws -> Data {
    throw error
  }
}

private struct UnusedRoutineSyncResponseDecoder:
  RoutineSyncTransportResponseDecoding {
  func decodeCommit(
    for _: RoutineSyncTransportRequest,
    from _: Data
  ) throws -> RoutineSyncTransportCommit {
    throw RoutineSyncResponseDecodingError.invalidResponse
  }
}
