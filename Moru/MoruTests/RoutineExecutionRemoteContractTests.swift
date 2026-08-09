//
//  RoutineExecutionRemoteContractTests.swift
//  MoruTests
//

import Foundation
import Moya
import XCTest

@testable import Moru

@MainActor
final class RoutineExecutionRemoteContractTests: XCTestCase {
  func testTargetsMatchSwaggerAndSamplesDecode() throws {
    let create = RoutineExecutionTarget.create(
      RoutineExecutionResultRequestDTO(
        executedDate: "2026-07-13",
        routineId: 31,
        durationSecond: 20,
        isCompleted: true,
        memberInput: "완료했어요",
        aiResponse: "좋아요",
        actualWakeTime: "07:23"
      )
    )
    let aiStep = RoutineExecutionTarget.aiStep(
      RoutineExecutionAIRequestDTO(
        routineId: 31,
        executedDate: "2026-07-13",
        durationSecond: 20,
        memberInput: "응, 다음",
        actualWakeTime: nil
      )
    )

    XCTAssertEqual(create.path, "/routine-executions")
    XCTAssertEqual(aiStep.path, "/routine-executions/ai-step")
    XCTAssertEqual(create.method, .post)
    XCTAssertEqual(aiStep.method, .post)
    XCTAssertEqual(create.authenticationRequirement, .bearer)
    XCTAssertEqual(aiStep.authenticationRequirement, .bearer)

    for target in [create, aiStep] {
      guard case .requestJSONEncodable = target.task else {
        return XCTFail("Expected a JSON-encoded POST request.")
      }
    }

    let decoder = JSONDecoder()
    let createEnvelope = try decoder.decode(
      APIResponse<RoutineExecutionResultResponseDTO>.self,
      from: create.sampleData
    )
    let aiEnvelope = try decoder.decode(
      APIResponse<RoutineExecutionAIResponseDTO>.self,
      from: aiStep.sampleData
    )

    XCTAssertEqual(createEnvelope.result?.executionId, 51)
    XCTAssertEqual(createEnvelope.result?.routineId, 31)
    XCTAssertEqual(aiEnvelope.result?.aiResponse, "다음으로 넘어갈게요!")
    XCTAssertEqual(aiEnvelope.result?.shouldProceed, true)
  }

  func testSavesExecutionAndJudgesCheckStepWithExactBodies()
    async throws
  {
    let capture = RoutineExecutionRequestCapturePlugin()
    let service = makeStubbedService(additionalPlugins: [capture])

    let execution = try await service.saveExecution(
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        durationSeconds: 20,
        isCompleted: true,
        memberInput: "완료했어요",
        aiResponse: "좋아요",
        actualWakeTime: "07:23"
      ),
      memberID: 98
    )
    let judgment = try await service.judgeCheckStep(
      ServerAIExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        durationSeconds: 21,
        memberInput: "응, 다음",
        actualWakeTime: nil
      ),
      memberID: 98
    )

    XCTAssertEqual(
      execution,
      ServerRoutineExecutionResult(
        executionID: 51,
        routineID: 31,
        executedDate: "2026-07-13",
        durationSeconds: 20,
        isCompleted: true
      )
    )
    XCTAssertEqual(
      judgment,
      ServerAIExecutionJudgment(
        aiResponse: "다음으로 넘어갈게요!",
        shouldProceed: true
      )
    )

    let requests = capture.requests
    XCTAssertEqual(requests.count, 2)
    XCTAssertTrue(
      requests.allSatisfy {
        $0.httpMethod == "POST"
          && $0.value(forHTTPHeaderField: "Authorization")
            == "Bearer access-token"
      }
    )

    let createBody = try jsonBody(
      forPath: "/routine-executions",
      in: requests
    )
    XCTAssertEqual(createBody.count, 7)
    XCTAssertEqual(createBody["executedDate"] as? String, "2026-07-13")
    XCTAssertEqual(createBody["routineId"] as? Int, 31)
    XCTAssertEqual(createBody["durationSecond"] as? Int, 20)
    XCTAssertEqual(createBody["isCompleted"] as? Bool, true)
    XCTAssertEqual(createBody["memberInput"] as? String, "완료했어요")
    XCTAssertEqual(createBody["aiResponse"] as? String, "좋아요")
    XCTAssertEqual(createBody["actualWakeTime"] as? String, "07:23")

    let aiBody = try jsonBody(
      forPath: "/routine-executions/ai-step",
      in: requests
    )
    XCTAssertEqual(aiBody.count, 4)
    XCTAssertEqual(aiBody["routineId"] as? Int, 31)
    XCTAssertEqual(aiBody["executedDate"] as? String, "2026-07-13")
    XCTAssertEqual(aiBody["durationSecond"] as? Int, 21)
    XCTAssertEqual(aiBody["memberInput"] as? String, "응, 다음")
    XCTAssertNil(aiBody["actualWakeTime"])
    XCTAssertNil(aiBody["isCompleted"])
    XCTAssertNil(aiBody["aiResponse"])
  }

  func testOptionalNilRequestFieldsAreOmitted() async throws {
    let capture = RoutineExecutionRequestCapturePlugin()
    let service = makeStubbedService(additionalPlugins: [capture])

    _ = try await service.saveExecution(
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        isCompleted: false
      ),
      memberID: 98
    )
    _ = try await service.judgeCheckStep(
      ServerAIExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        memberInput: ""
      ),
      memberID: 98
    )

    let createBody = try jsonBody(
      forPath: "/routine-executions",
      in: capture.requests
    )
    XCTAssertEqual(
      Set(createBody.keys),
      [
        "executedDate",
        "routineId",
        "isCompleted",
      ])

    let aiBody = try jsonBody(
      forPath: "/routine-executions/ai-step",
      in: capture.requests
    )
    XCTAssertEqual(
      Set(aiBody.keys),
      [
        "routineId",
        "executedDate",
        "memberInput",
      ])
    XCTAssertEqual(aiBody["memberInput"] as? String, "")
  }

  func testResponseDTOsDecodeMissingSwaggerFieldsThenMappingRejectsThem()
    async throws
  {
    let decoder = JSONDecoder()
    let execution = try decoder.decode(
      RoutineExecutionResultResponseDTO.self,
      from: Data("{}".utf8)
    )
    let ai = try decoder.decode(
      RoutineExecutionAIResponseDTO.self,
      from: Data("{}".utf8)
    )

    XCTAssertNil(execution.executionId)
    XCTAssertNil(execution.routineId)
    XCTAssertNil(execution.executedDate)
    XCTAssertNil(execution.durationSecond)
    XCTAssertNil(execution.isCompleted)
    XCTAssertNil(ai.aiResponse)
    XCTAssertNil(ai.shouldProceed)

    let service = DefaultAccountRoutineExecutionRemoteService(
      apiClient: RoutineExecutionPayloadAPIClient(
        execution: execution,
        ai: ai
      )
    )
    await assertRemoteError(.invalidResponse) {
      _ = try await service.saveExecution(
        validExecutionSubmission(),
        memberID: 98
      )
    }
    await assertRemoteError(.invalidResponse) {
      _ = try await service.judgeCheckStep(
        validAISubmission(),
        memberID: 98
      )
    }
  }

  func testExecutionResponseRequiresIdentityAndRequestCorrelation()
    async throws
  {
    let invalidResponses = [
      executionResponse(executionId: nil),
      executionResponse(executionId: 0),
      executionResponse(routineId: nil),
      executionResponse(routineId: 32),
      executionResponse(executedDate: nil),
      executionResponse(executedDate: "2026-07-14"),
      executionResponse(isCompleted: nil),
      executionResponse(isCompleted: false),
      executionResponse(durationSecond: -1),
      executionResponse(durationSecond: Int(Int32.max) + 1),
    ]

    for response in invalidResponses {
      let service = DefaultAccountRoutineExecutionRemoteService(
        apiClient: RoutineExecutionPayloadAPIClient(execution: response)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.saveExecution(
          validExecutionSubmission(),
          memberID: 98
        )
      }
    }

    let service = DefaultAccountRoutineExecutionRemoteService(
      apiClient: RoutineExecutionPayloadAPIClient(
        execution: executionResponse(durationSecond: nil)
      )
    )
    let result = try await service.saveExecution(
      validExecutionSubmission(),
      memberID: 98
    )
    XCTAssertNil(result.durationSeconds)
  }

  func testAIResponseRequiresBothFields() async {
    for response in [
      RoutineExecutionAIResponseDTO(
        aiResponse: nil,
        shouldProceed: true
      ),
      RoutineExecutionAIResponseDTO(
        aiResponse: "다시 말해 주세요.",
        shouldProceed: nil
      ),
    ] {
      let service = DefaultAccountRoutineExecutionRemoteService(
        apiClient: RoutineExecutionPayloadAPIClient(ai: response)
      )
      await assertRemoteError(.invalidResponse) {
        _ = try await service.judgeCheckStep(
          validAISubmission(),
          memberID: 98
        )
      }
    }
  }

  func testRejectsInvalidRequestsBeforeTransport() async {
    let client = RoutineExecutionCallCountingAPIClient()
    let service = DefaultAccountRoutineExecutionRemoteService(
      apiClient: client
    )
    let invalidExecutionSubmissions = [
      ServerRoutineExecutionSubmission(
        routineID: 0,
        executedDate: "2026-07-13",
        isCompleted: true
      ),
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-02-29",
        isCompleted: true
      ),
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        durationSeconds: -1,
        isCompleted: true
      ),
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        durationSeconds: Int(Int32.max) + 1,
        isCompleted: true
      ),
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        isCompleted: true,
        memberInput: String(repeating: "가", count: 501)
      ),
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        isCompleted: true,
        aiResponse: String(repeating: "가", count: 501)
      ),
      ServerRoutineExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        isCompleted: true,
        actualWakeTime: "24:00"
      ),
    ]

    for submission in invalidExecutionSubmissions {
      await assertRemoteError(.invalidRequest) {
        _ = try await service.saveExecution(submission, memberID: 98)
      }
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.saveExecution(
        validExecutionSubmission(),
        memberID: 0
      )
    }

    let invalidAISubmissions = [
      ServerAIExecutionSubmission(
        routineID: -1,
        executedDate: "2026-07-13",
        memberInput: "응"
      ),
      ServerAIExecutionSubmission(
        routineID: 31,
        executedDate: "2026-13-01",
        memberInput: "응"
      ),
      ServerAIExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        durationSeconds: -1,
        memberInput: "응"
      ),
      ServerAIExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        memberInput: String(repeating: "가", count: 501)
      ),
      ServerAIExecutionSubmission(
        routineID: 31,
        executedDate: "2026-07-13",
        memberInput: "응",
        actualWakeTime: "7:23"
      ),
    ]

    for submission in invalidAISubmissions {
      await assertRemoteError(.invalidRequest) {
        _ = try await service.judgeCheckStep(submission, memberID: 98)
      }
    }
    await assertRemoteError(.invalidRequest) {
      _ = try await service.judgeCheckStep(
        validAISubmission(),
        memberID: -1
      )
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testCancellationAccountChangeAndServerErrorRemainDistinct()
    async
  {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let service = DefaultAccountRoutineExecutionRemoteService(
        apiClient: RoutineExecutionThrowingAPIClient(error: error)
      )

      do {
        _ = try await service.saveExecution(
          validExecutionSubmission(),
          memberID: 98
        )
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        continue
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }

    let changedAccountService = DefaultAccountRoutineExecutionRemoteService(
      apiClient: RoutineExecutionThrowingAPIClient(
        error: AccountAuthorizationContextError.memberMismatch
      )
    )
    await assertRemoteError(.accountAuthorizationChanged) {
      _ = try await changedAccountService.judgeCheckStep(
        validAISubmission(),
        memberID: 98
      )
    }

    let serverError = APIError.server(
      statusCode: 503,
      code: "COMMON503",
      message: "잠시 후 다시 시도해 주세요."
    )
    let failingService = DefaultAccountRoutineExecutionRemoteService(
      apiClient: RoutineExecutionThrowingAPIClient(error: serverError)
    )
    do {
      _ = try await failingService.saveExecution(
        validExecutionSubmission(),
        memberID: 98
      )
      XCTFail("Expected server error.")
    } catch let error as APIError {
      XCTAssertEqual(error, serverError)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  private func jsonBody(
    forPath path: String,
    in requests: [URLRequest]
  ) throws -> [String: Any] {
    let request = try XCTUnwrap(
      requests.first { $0.url?.path == path }
    )
    let body = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
  }

  private func assertRemoteError(
    _ expected: AccountRoutineExecutionRemoteError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as AccountRoutineExecutionRemoteError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AccountRoutineExecutionRemoteError, got \(error)")
    }
  }

  nonisolated private func makeStubbedService(
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAccountRoutineExecutionRemoteService {
    let client = DefaultAPIClient(
      tokenProvider: RoutineExecutionAccessTokenProvider(),
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
    return DefaultAccountRoutineExecutionRemoteService(apiClient: client)
  }
}

nonisolated private func validExecutionSubmission()
  -> ServerRoutineExecutionSubmission
{
  ServerRoutineExecutionSubmission(
    routineID: 31,
    executedDate: "2026-07-13",
    durationSeconds: 20,
    isCompleted: true,
    memberInput: "완료했어요",
    aiResponse: nil,
    actualWakeTime: "07:23"
  )
}

nonisolated private func validAISubmission()
  -> ServerAIExecutionSubmission
{
  ServerAIExecutionSubmission(
    routineID: 31,
    executedDate: "2026-07-13",
    durationSeconds: 20,
    memberInput: "응, 다음",
    actualWakeTime: nil
  )
}

nonisolated private func executionResponse(
  executedDate: String? = "2026-07-13",
  executionId: Int64? = 51,
  routineId: Int64? = 31,
  durationSecond: Int? = 20,
  isCompleted: Bool? = true
) -> RoutineExecutionResultResponseDTO {
  RoutineExecutionResultResponseDTO(
    executedDate: executedDate,
    executionId: executionId,
    routineId: routineId,
    durationSecond: durationSecond,
    isCompleted: isCompleted
  )
}

nonisolated private final class RoutineExecutionAccessTokenProvider:
  AccountBoundAccessTokenProviding
{
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

nonisolated private final class RoutineExecutionRequestCapturePlugin:
  PluginType,
  @unchecked Sendable
{
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

nonisolated private final class RoutineExecutionPayloadAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable
{
  private let execution: RoutineExecutionResultResponseDTO
  private let ai: RoutineExecutionAIResponseDTO

  init(
    execution: RoutineExecutionResultResponseDTO = executionResponse(),
    ai: RoutineExecutionAIResponseDTO = RoutineExecutionAIResponseDTO(
      aiResponse: "다음으로 넘어갈게요!",
      shouldProceed: true
    )
  ) {
    self.execution = execution
    self.ai = ai
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
      let target = target as? RoutineExecutionTarget
    else {
      throw AccountAuthorizationContextError.memberMismatch
    }

    let response: Any
    switch target {
    case .create:
      response = execution
    case .aiStep:
      response = ai
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected routine execution payload type.")
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

nonisolated private final class RoutineExecutionCallCountingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable
{
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

nonisolated private final class RoutineExecutionThrowingAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable
{
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
