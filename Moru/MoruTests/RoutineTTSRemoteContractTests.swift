//
//  RoutineTTSRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Moya

@testable import Moru

@MainActor
final class RoutineTTSRemoteContractTests: XCTestCase {
  private let identity = AccountSessionIdentity(
    memberID: 98,
    sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
  )

  func testTargetMatchesOpenAPIAndSampleDecodes() throws {
    let target = RoutineTTSTarget.list(routineGroupID: 42)

    XCTAssertEqual(target.path, "/routine-tts/42/tts")
    XCTAssertEqual(
      target.networkLogPath,
      "/routine-tts/{routineGroupId}/tts"
    )
    XCTAssertEqual(target.method, .get)
    XCTAssertEqual(target.authenticationRequirement, .bearer)
    guard case .requestPlain = target.task else {
      return XCTFail("Expected a body-free GET request.")
    }

    let envelope = try JSONDecoder().decode(
      APIResponse<[RoutineTTSResponseDTO]>.self,
      from: target.sampleData
    )
    XCTAssertTrue(envelope.isSuccess)
    XCTAssertEqual(envelope.result?.first?.routineId, 14)
    XCTAssertEqual(envelope.result?.first?.steps?.first?.stepId, 101)
  }

  func testFetchUsesExactIdentityAndMapsAllContractValues()
    async throws {
    let data = successEnvelope(
      resultJSON:
        """
        [
          {
            "routineId": 11,
            "title": "  첫 루틴  ",
            "type": "CHECK",
            "steps": [
              {
                "stepId": 101,
                "content": "  첫 안내  ",
                "ttsIntro": "  시작해 볼까요?  ",
                "ttsStatus": "COMPLETED",
                "s3Url": "  https://audio.example.com/a.mp3?signature=secret  "
              },
              {
                "stepId": 102,
                "content": "미래 상태",
                "ttsIntro": "문장은 있어요",
                "ttsStatus": "QUEUED_V2",
                "s3Url": "https://audio.example.com/future.mp3"
              }
            ]
          },
          {
            "routineId": 12,
            "title": "타이머",
            "type": "TIMER",
            "steps": [
              {
                "stepId": 103,
                "content": "준비 중",
                "ttsIntro": null,
                "ttsStatus": "PENDING",
                "s3Url": "https://audio.example.com/must-not-play.mp3"
              }
            ]
          },
          {
            "routineId": 13,
            "title": "입력",
            "type": "INPUT",
            "steps": [
              {
                "stepId": 104,
                "content": "실패",
                "ttsIntro": "재생하면 안 돼요",
                "ttsStatus": "FAILED",
                "s3Url": "https://audio.example.com/must-not-play-either.mp3"
              }
            ]
          }
        ]
        """
    )
    let client = RoutineTTSStubAPIClient(
      data: data,
      expectedIdentity: identity
    )
    let service = DefaultRoutineTTSRemoteService(apiClient: client)

    let routines = try await service.fetchRoutineTTS(
      routineGroupID: 42,
      identity: identity
    )

    XCTAssertEqual(client.capturedIdentity, identity)
    XCTAssertEqual(client.capturedPath, "/routine-tts/42/tts")
    XCTAssertEqual(routines.map(\.routineID), [11, 12, 13])
    XCTAssertEqual(routines.map(\.type), [.check, .timer, .input])
    XCTAssertEqual(routines[0].title, "첫 루틴")
    XCTAssertEqual(routines[0].steps[0].content, "첫 안내")
    XCTAssertEqual(routines[0].steps[0].introText, "시작해 볼까요?")
    XCTAssertEqual(routines[0].steps[0].status, .completed)
    XCTAssertEqual(
      routines[0].steps[0].audioURL?.absoluteString,
      "https://audio.example.com/a.mp3?signature=secret"
    )
    XCTAssertTrue(routines[0].steps[0].isPlayable)
    XCTAssertEqual(routines[0].steps[1].status, .unknown("QUEUED_V2"))
    XCTAssertNil(routines[0].steps[1].audioURL)
    XCTAssertEqual(routines[1].steps[0].status, .pending)
    XCTAssertNil(routines[1].steps[0].audioURL)
    XCTAssertEqual(routines[2].steps[0].status, .failed)
    XCTAssertNil(routines[2].steps[0].audioURL)
  }

  func testDTOsDecodeMissingFieldsBeforeDomainMappingRejectsThem()
    async throws {
    let decoder = JSONDecoder()
    let routine = try decoder.decode(
      RoutineTTSResponseDTO.self,
      from: Data("{}".utf8)
    )
    let step = try decoder.decode(
      RoutineTTSStepResponseDTO.self,
      from: Data("{}".utf8)
    )

    XCTAssertNil(routine.routineId)
    XCTAssertNil(routine.steps)
    XCTAssertNil(step.stepId)
    XCTAssertNil(step.ttsStatus)

    let service = makeService(resultJSON: "[{}]")
    await assertRemoteError(.invalidResponse) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 42,
        identity: self.identity
      )
    }
  }

  func testRejectsInvalidRequestBeforeTransport() async {
    let client = RoutineTTSStubAPIClient(
      data: successEnvelope(resultJSON: "[]")
    )
    let service = DefaultRoutineTTSRemoteService(apiClient: client)

    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 0,
        identity: self.identity
      )
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 42,
        identity: AccountSessionIdentity(
          memberID: 0,
          sessionID: UUID()
        )
      )
    }
    XCTAssertEqual(client.callCount, 0)
  }

  func testStrictlyRejectsInvalidRoutineFields() async {
    let invalidResults = [
      """
      [{"routineId":0,"title":"A","type":"CHECK","steps":[]}]
      """,
      """
      [
        {"routineId":1,"title":"A","type":"CHECK","steps":[]},
        {"routineId":1,"title":"B","type":"TIMER","steps":[]}
      ]
      """,
      """
      [{"routineId":1,"title":"  ","type":"CHECK","steps":[]}]
      """,
      """
      [{"routineId":1,"title":"A","type":"FUTURE","steps":[]}]
      """,
      """
      [{"routineId":1,"title":"A","type":"CHECK"}]
      """,
    ]

    for result in invalidResults {
      let service = makeService(resultJSON: result)
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 42,
          identity: self.identity
        )
      }
    }
  }

  func testStrictlyRejectsInvalidOrDuplicateStepFields() async {
    let invalidResults = [
      routineResult(
        stepsJSON:
          """
          [{"stepId":0,"content":"A","ttsStatus":"PENDING"}]
          """
      ),
      routineResult(
        stepsJSON:
          """
          [
            {"stepId":1,"content":"A","ttsStatus":"PENDING"},
            {"stepId":1,"content":"B","ttsStatus":"FAILED"}
          ]
          """
      ),
      routineResult(
        stepsJSON:
          """
          [{"stepId":1,"content":" \n ","ttsStatus":"PENDING"}]
          """
      ),
      routineResult(
        stepsJSON:
          """
          [{"stepId":1,"content":"A","ttsStatus":"  "}]
          """
      ),
      """
      [
        {
          "routineId":1,"title":"A","type":"CHECK",
          "steps":[{"stepId":9,"content":"A","ttsStatus":"PENDING"}]
        },
        {
          "routineId":2,"title":"B","type":"TIMER",
          "steps":[{"stepId":9,"content":"B","ttsStatus":"FAILED"}]
        }
      ]
      """,
    ]

    for result in invalidResults {
      let service = makeService(resultJSON: result)
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 42,
          identity: self.identity
        )
      }
    }
  }

  func testCompletedStepIsUnavailableUnlessIntroAndSafeHTTPSURLExist()
    async throws {
    let result = routineResult(
      stepsJSON:
        """
        [
          {
            "stepId":1,"content":"A","ttsIntro":null,
            "ttsStatus":"COMPLETED","s3Url":"https://audio.example.com/a.mp3"
          },
          {
            "stepId":2,"content":"B","ttsIntro":"  ",
            "ttsStatus":"COMPLETED","s3Url":"https://audio.example.com/b.mp3"
          },
          {
            "stepId":3,"content":"C","ttsIntro":"intro",
            "ttsStatus":"COMPLETED","s3Url":"http://audio.example.com/c.mp3"
          },
          {
            "stepId":4,"content":"D","ttsIntro":"intro",
            "ttsStatus":"COMPLETED","s3Url":"https://user:pass@audio.example.com/d.mp3"
          },
          {
            "stepId":5,"content":"E","ttsIntro":"intro",
            "ttsStatus":"COMPLETED","s3Url":"not a url"
          },
          {
            "stepId":6,"content":"F","ttsIntro":"intro",
            "ttsStatus":"COMPLETED","s3Url":"https://audio.example.com/f.mp3"
          }
        ]
        """
    )
    let service = makeService(resultJSON: result)

    let routines = try await service.fetchRoutineTTS(
      routineGroupID: 42,
      identity: identity
    )

    XCTAssertEqual(
      routines[0].steps.map(\.isPlayable),
      [false, false, false, false, false, true]
    )
  }

  func testRejectsMalformedOrUnsuccessfulEnvelope() async {
    for data in [
      Data("not-json".utf8),
      Data(
        """
        {"isSuccess":true,"code":"COMMON200","message":"ok","result":null}
        """.utf8
      ),
      Data(
        """
        {"isSuccess":false,"code":"FAIL","message":"no","result":[]}
        """.utf8
      ),
    ] {
      let service = DefaultRoutineTTSRemoteService(
        apiClient: RoutineTTSStubAPIClient(data: data)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 42,
          identity: self.identity
        )
      }
    }
  }

  func testMapsCancellationAndExactSessionAuthorizationChanges() async {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let service = DefaultRoutineTTSRemoteService(
        apiClient: RoutineTTSStubAPIClient(error: error)
      )
      do {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 42,
          identity: identity
        )
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        // Expected.
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let newerIdentity = AccountSessionIdentity(
      memberID: identity.memberID,
      sessionID: UUID()
    )
    let service = DefaultRoutineTTSRemoteService(
      apiClient: RoutineTTSStubAPIClient(
        data: successEnvelope(resultJSON: "[]"),
        expectedIdentity: newerIdentity
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 42,
        identity: self.identity
      )
    }
  }

  func testPreservesUnmappedTransportError() async {
    let expected = APIError.transport(code: -1009, message: "offline")
    let service = DefaultRoutineTTSRemoteService(
      apiClient: RoutineTTSStubAPIClient(error: expected)
    )

    do {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 42,
        identity: identity
      )
      XCTFail("Expected transport error.")
    } catch let error as APIError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  private func makeService(
    resultJSON: String
  ) -> DefaultRoutineTTSRemoteService {
    DefaultRoutineTTSRemoteService(
      apiClient: RoutineTTSStubAPIClient(
        data: successEnvelope(resultJSON: resultJSON)
      )
    )
  }

  private func successEnvelope(resultJSON: String) -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": \(resultJSON)
      }
      """.utf8
    )
  }

  private func routineResult(stepsJSON: String) -> String {
    """
    [
      {
        "routineId": 1,
        "title": "A",
        "type": "CHECK",
        "steps": \(stepsJSON)
      }
    ]
    """
  }

  private func assertRemoteError(
    _ expected: RoutineTTSRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as RoutineTTSRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected RoutineTTSRemoteError, got \(error)")
    }
  }
}

nonisolated private final class RoutineTTSStubAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let lock = NSLock()
  private let data: Data
  private let error: (any Error)?
  private let expectedIdentity: AccountSessionIdentity?
  private var requestCount = 0
  private var requestedIdentity: AccountSessionIdentity?
  private var requestedPath: String?

  init(
    data: Data = Data(),
    error: (any Error)? = nil,
    expectedIdentity: AccountSessionIdentity? = nil
  ) {
    self.data = data
    self.error = error
    self.expectedIdentity = expectedIdentity
  }

  convenience init(error: any Error) {
    self.init(data: Data(), error: error)
  }

  var callCount: Int {
    lock.withLock { requestCount }
  }

  var capturedIdentity: AccountSessionIdentity? {
    lock.withLock { requestedIdentity }
  }

  var capturedPath: String? {
    lock.withLock { requestedPath }
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected exact-identity data request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected exact-identity data request.")
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Expected exact-identity data request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Data {
    lock.withLock {
      requestCount += 1
      requestedIdentity = identity
      requestedPath = target.path
    }

    if let expectedIdentity, expectedIdentity != identity {
      throw AccountAuthorizationContextError.memberMismatch
    }
    if let error {
      throw error
    }
    return data
  }
}
