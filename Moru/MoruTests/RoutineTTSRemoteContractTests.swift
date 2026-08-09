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
  func testTargetMatchesSwaggerAndSampleDecodes() throws {
    let target = RoutineTTSTarget.list(routineGroupID: 12)

    XCTAssertEqual(target.path, "/routine-tts/12/tts")
    XCTAssertEqual(target.method, .get)
    XCTAssertEqual(target.authenticationRequirement, .bearer)
    guard case .requestPlain = target.task else {
      return XCTFail("Expected a body-free GET request.")
    }

    let envelope = try JSONDecoder().decode(
      APIResponse<[RoutineTTSResponseDTO]>.self,
      from: target.sampleData
    )

    XCTAssertEqual(envelope.result?.first?.routineId, 14)
    XCTAssertEqual(envelope.result?.first?.steps?.first?.stepId, 101)
    XCTAssertEqual(
      envelope.result?.first?.steps?.first?.ttsStatus,
      "COMPLETED"
    )
  }

  func testFetchUsesAccountBindingAndBodyFreeRequest() async throws {
    let capture = RoutineTTSRequestCapturePlugin()
    let service = makeStubbedService(additionalPlugins: [capture])

    let items = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(items.map(\.routineID), [14])
    XCTAssertEqual(items.first?.title, "스트레칭하기")
    XCTAssertEqual(items.first?.type, .timer)
    XCTAssertEqual(items.first?.steps?.map(\.stepID), [101])
    XCTAssertEqual(items.first?.steps?.first?.status, .completed)
    XCTAssertEqual(
      items.first?.steps?.first?.audioURL?.absoluteString,
      "https://example.com/routine-tts/101.mp3"
    )

    XCTAssertEqual(capture.requests.count, 1)
    XCTAssertEqual(capture.requests.first?.url?.path, "/routine-tts/12/tts")
    XCTAssertEqual(capture.requests.first?.httpMethod, "GET")
    XCTAssertNil(capture.requests.first?.httpBody)
    XCTAssertEqual(
      capture.requests.first?.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
  }

  func testDTOsDecodeEverySwaggerFieldAsOptionalAndNullable() throws {
    let decoder = JSONDecoder()
    let item = try decoder.decode(
      RoutineTTSResponseDTO.self,
      from: Data("{}".utf8)
    )
    let step = try decoder.decode(
      RoutineTTSStepResponseDTO.self,
      from: Data(
        """
        {
          "ttsIntro": null,
          "s3Url": null
        }
        """.utf8
      )
    )

    XCTAssertNil(item.routineId)
    XCTAssertNil(item.title)
    XCTAssertNil(item.type)
    XCTAssertNil(item.steps)
    XCTAssertNil(step.stepId)
    XCTAssertNil(step.content)
    XCTAssertNil(step.ttsIntro)
    XCTAssertNil(step.ttsStatus)
    XCTAssertNil(step.s3Url)
  }

  func testKnownStatusesMapAndPendingOrFailedKeepPreviousAudio()
    async throws {
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(
        items: [
          routineTTSItemDTO(
            type: "CHECK",
            steps: [
              routineTTSStepDTO(
                stepId: 1,
                ttsStatus: "PENDING",
                s3Url: "https://cdn.example.com/audio/old-1.mp3?token=a"
              ),
              routineTTSStepDTO(
                stepId: 2,
                ttsStatus: "COMPLETED",
                s3Url: "https://cdn.example.com/audio/new-2.mp3"
              ),
              routineTTSStepDTO(
                stepId: 3,
                ttsStatus: "FAILED",
                s3Url: "https://cdn.example.com/audio/old-3.mp3"
              ),
              routineTTSStepDTO(
                stepId: 4,
                ttsStatus: "QUEUED_V2",
                s3Url: nil
              ),
            ]
          ),
        ]
      )
    )

    let item = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )
    let steps = try XCTUnwrap(item.first?.steps)

    XCTAssertEqual(item.first?.type, .check)
    XCTAssertEqual(
      steps.map(\.status),
      [.pending, .completed, .failed, .unknown("QUEUED_V2")]
    )
    XCTAssertNotNil(steps[0].audioURL)
    XCTAssertNotNil(steps[2].audioURL)
    XCTAssertNil(steps[3].audioURL)
  }

  func testUnknownRoutineTypeAndValuesPreserveTrimmedServerText()
    async throws {
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(
        items: [
          routineTTSItemDTO(
            title: "  미래 루틴  ",
            type: " FUTURE_TYPE ",
            steps: [
              routineTTSStepDTO(
                content: "  원문  ",
                ttsIntro: "  합성 문장  ",
                ttsStatus: " FUTURE_STATUS "
              ),
            ]
          ),
        ]
      )
    )

    let item = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(item.first?.title, "미래 루틴")
    XCTAssertEqual(item.first?.type, .unknown("FUTURE_TYPE"))
    XCTAssertEqual(item.first?.steps?.first?.content, "원문")
    XCTAssertEqual(item.first?.steps?.first?.ttsIntro, "합성 문장")
    XCTAssertEqual(
      item.first?.steps?.first?.status,
      .unknown("FUTURE_STATUS")
    )
  }

  func testMissingNonIdentityFieldsAndOmittedArraysRemainValid()
    async throws {
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(
        items: [
          routineTTSItemDTO(
            routineId: 1,
            title: nil,
            type: nil,
            steps: nil
          ),
          routineTTSItemDTO(
            routineId: 2,
            steps: []
          ),
          routineTTSItemDTO(
            routineId: 3,
            steps: [
              routineTTSStepDTO(
                stepId: 1,
                content: nil,
                ttsIntro: nil,
                ttsStatus: nil,
                s3Url: nil
              ),
            ]
          ),
        ]
      )
    )

    let items = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertNil(items[0].title)
    XCTAssertNil(items[0].type)
    XCTAssertNil(items[0].steps)
    XCTAssertEqual(items[1].steps, [])
    XCTAssertNil(items[2].steps?.first?.content)
    XCTAssertNil(items[2].steps?.first?.ttsIntro)
    XCTAssertNil(items[2].steps?.first?.status)
    XCTAssertNil(items[2].steps?.first?.audioURL)
  }

  func testEmptyResultIsValid() async throws {
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSPayloadAPIClient(items: [])
    )

    let items = try await service.fetchRoutineTTS(
      routineGroupID: 12,
      memberID: 98
    )

    XCTAssertEqual(items, [])
  }

  func testRejectsMissingNonpositiveAndDuplicateIdentities() async {
    let invalidPayloads: [[RoutineTTSResponseDTO]] = [
      [routineTTSItemDTO(routineId: nil)],
      [routineTTSItemDTO(routineId: 0)],
      [routineTTSItemDTO(routineId: -1)],
      [
        routineTTSItemDTO(routineId: 1),
        routineTTSItemDTO(routineId: 1),
      ],
      [routineTTSItemDTO(steps: [routineTTSStepDTO(stepId: nil)])],
      [routineTTSItemDTO(steps: [routineTTSStepDTO(stepId: 0)])],
      [routineTTSItemDTO(steps: [routineTTSStepDTO(stepId: -1)])],
      [
        routineTTSItemDTO(
          steps: [
            routineTTSStepDTO(stepId: 1),
            routineTTSStepDTO(stepId: 1),
          ]
        ),
      ],
    ]

    for items in invalidPayloads {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSPayloadAPIClient(items: items)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 12,
          memberID: 98
        )
      }
    }
  }

  func testRejectsPresentBlankTextAndInvalidAudioURLs() async {
    let invalidPayloads = [
      routineTTSItemDTO(title: " \n "),
      routineTTSItemDTO(type: "\t"),
      routineTTSItemDTO(
        steps: [routineTTSStepDTO(content: " ")]
      ),
      routineTTSItemDTO(
        steps: [routineTTSStepDTO(ttsIntro: "\n")]
      ),
      routineTTSItemDTO(
        steps: [routineTTSStepDTO(ttsStatus: " ")]
      ),
      routineTTSItemDTO(
        steps: [routineTTSStepDTO(s3Url: "relative/audio.mp3")]
      ),
      routineTTSItemDTO(
        steps: [routineTTSStepDTO(s3Url: "http://example.com/audio.mp3")]
      ),
      routineTTSItemDTO(
        steps: [routineTTSStepDTO(s3Url: "https:///audio.mp3")]
      ),
    ]

    for item in invalidPayloads {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSPayloadAPIClient(items: [item])
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 12,
          memberID: 98
        )
      }
    }
  }

  func testRejectsInvalidRequestBeforeTransport() async {
    let client = RoutineTTSCallCountingAPIClient()
    let service = DefaultAccountRoutineTTSRemoteService(apiClient: client)

    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 0,
        memberID: 98
      )
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 12,
        memberID: 0
      )
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testCancellationAndAuthorizationChangeRemainDistinct() async {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let service = DefaultAccountRoutineTTSRemoteService(
        apiClient: RoutineTTSThrowingAPIClient(error: error)
      )

      do {
        _ = try await service.fetchRoutineTTS(
          routineGroupID: 12,
          memberID: 98
        )
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSThrowingAPIClient(
        error: AccountAuthorizationContextError.memberMismatch
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 12,
        memberID: 98
      )
    }
  }

  func testServerErrorsPassThrough() async {
    let serverError = APIError.server(
      statusCode: 404,
      code: "ROUTINE_TTS404",
      message: "루틴 TTS를 찾을 수 없습니다."
    )
    let service = DefaultAccountRoutineTTSRemoteService(
      apiClient: RoutineTTSThrowingAPIClient(error: serverError)
    )

    do {
      _ = try await service.fetchRoutineTTS(
        routineGroupID: 12,
        memberID: 98
      )
      XCTFail("Expected a server error.")
    } catch let error as APIError {
      XCTAssertEqual(error, serverError)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  private func assertRemoteError(
    _ expected: AccountRoutineTTSRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountRoutineTTSRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AccountRoutineTTSRemoteError, got \(error)")
    }
  }

  nonisolated private func makeStubbedService(
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAccountRoutineTTSRemoteService {
    let client = DefaultAPIClient(
      tokenProvider: RoutineTTSAccessTokenProvider(),
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>
            .defaultEndpointMapping(for: target)
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkResponse(200, target.sampleData)
            },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )
    return DefaultAccountRoutineTTSRemoteService(apiClient: client)
  }
}

nonisolated private func routineTTSItemDTO(
  routineId: Int64? = 14,
  title: String? = "스트레칭하기",
  type: String? = "TIMER",
  steps: [RoutineTTSStepResponseDTO]? = []
) -> RoutineTTSResponseDTO {
  RoutineTTSResponseDTO(
    routineId: routineId,
    title: title,
    type: type,
    steps: steps
  )
}

nonisolated private func routineTTSStepDTO(
  stepId: Int64? = 101,
  content: String? = "목 스트레칭",
  ttsIntro: String? = "이제 목을 부드럽게 풀어볼까요?",
  ttsStatus: String? = "COMPLETED",
  s3Url: String? = "https://example.com/routine-tts/101.mp3"
) -> RoutineTTSStepResponseDTO {
  RoutineTTSStepResponseDTO(
    stepId: stepId,
    content: content,
    ttsIntro: ttsIntro,
    ttsStatus: ttsStatus,
    s3Url: s3Url
  )
}

nonisolated private final class RoutineTTSAccessTokenProvider:
  AccountBoundAccessTokenProviding {
  private let context = AccountAuthorizationContext(
    memberID: 98,
    accessToken: "access-token",
    sessionID: UUID()
  )

  var accessToken: String? {
    context.accessToken
  }

  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext? {
    context.memberID == memberID ? context : nil
  }
}

nonisolated private final class RoutineTTSRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequests
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.lock()
    capturedRequests.append(request)
    lock.unlock()
    return request
  }
}

nonisolated private final class RoutineTTSPayloadAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let items: [RoutineTTSResponseDTO]

  init(items: [RoutineTTSResponseDTO]) {
    self.items = items
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    guard memberID == 98,
          target is RoutineTTSTarget,
          let payload = items as? Payload else {
      throw AccountAuthorizationContextError.memberMismatch
    }
    return payload
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

nonisolated private final class RoutineTTSCallCountingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let lock = NSLock()
  private var requestCallCount = 0

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requestCallCount
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    recordCall()
    throw APIError.invalidRequest("Unexpected request.")
  }

  private func recordCall() {
    lock.lock()
    requestCallCount += 1
    lock.unlock()
  }
}

nonisolated private final class RoutineTTSThrowingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let error: any Error

  init(error: any Error) {
    self.error = error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw error
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw error
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw error
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw error
  }
}
