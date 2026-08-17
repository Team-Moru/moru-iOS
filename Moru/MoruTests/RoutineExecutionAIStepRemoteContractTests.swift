//
//  RoutineExecutionAIStepRemoteContractTests.swift
//  MoruTests
//

import Foundation
import XCTest

import Alamofire
import Moya

@testable import Moru

@MainActor
final class RoutineExecutionAIStepRemoteContractTests: XCTestCase {
  private let identity = AccountSessionIdentity(
    memberID: 98,
    sessionID: UUID()
  )

  func testTargetMatchesLiveSwaggerAndSampleDecodes() throws {
    let target = RoutineExecutionAIStepTarget.evaluate(
      RoutineExecutionAIStepRequestDTO(
        routineId: 31,
        executedDate: "2026-08-13",
        durationSecond: 20,
        memberInput: "응, 다음",
        actualWakeTime: "07:23"
      )
    )

    XCTAssertEqual(target.path, "/routine-executions/ai-step")
    XCTAssertEqual(target.method, .post)
    XCTAssertEqual(target.authenticationRequirement, .bearer)
    guard case .requestJSONEncodable = target.task else {
      return XCTFail("Expected one JSON POST body.")
    }

    let envelope = try JSONDecoder().decode(
      APIResponse<RoutineExecutionAIStepResponseDTO>.self,
      from: target.sampleData
    )
    XCTAssertEqual(envelope.result?.shouldProceed, true)
  }

  func testProceedAndStopResponsesMapWithoutAutomaticFollowup() async throws {
    for shouldProceed in [true, false] {
      let client = RoutineExecutionAIStepPayloadClient(
        result: .success(
          RoutineExecutionAIStepResponseDTO(
            aiResponse: shouldProceed ? "다음으로 갈게요" : "다시 말해 주세요",
            shouldProceed: shouldProceed
          )
        )
      )
      let service = DefaultRoutineExecutionAIStepRemoteService(
        apiClient: client
      )

      let decision = try await service.evaluate(
        validRequest(),
        authorizedFor: identity
      )

      XCTAssertEqual(decision.shouldProceed, shouldProceed)
      XCTAssertEqual(client.callCount, 1)
      XCTAssertEqual(client.identities, [identity])
    }
  }

  func testRequestSendsExactSwaggerFieldsAndNoIdempotencyKey() async throws {
    let tokenProvider = RoutineExecutionAIStepTokenProvider(
      context: AccountAuthorizationContext(
        memberID: identity.memberID,
        accessToken: "private-access-token",
        sessionID: identity.sessionID
      )
    )
    let capture = RoutineExecutionAIStepRequestCapturePlugin()
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        data: successData(shouldProceed: true),
        tokenProvider: tokenProvider,
        additionalPlugins: [capture]
      )
    )

    _ = try await service.evaluate(
      validRequest(),
      authorizedFor: identity
    )

    let request = try XCTUnwrap(capture.request)
    let body = try jsonBody(request)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.path, "/routine-executions/ai-step")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer private-access-token"
    )
    XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
    XCTAssertEqual(body["routineId"] as? Int, 31)
    XCTAssertEqual(body["executedDate"] as? String, "2026-08-13")
    XCTAssertEqual(body["durationSecond"] as? Int, 20)
    XCTAssertEqual(body["memberInput"] as? String, "응, 다음")
    XCTAssertEqual(body["actualWakeTime"] as? String, "07:23")
    XCTAssertEqual(Set(body.keys), [
      "routineId",
      "executedDate",
      "durationSecond",
      "memberInput",
      "actualWakeTime",
    ])
  }

  func testOptionalFieldsAreOmittedAndEmptyInputIsAccepted() async throws {
    let capture = RoutineExecutionAIStepRequestCapturePlugin()
    let tokenProvider = RoutineExecutionAIStepTokenProvider(
      context: AccountAuthorizationContext(
        memberID: identity.memberID,
        accessToken: "access-token",
        sessionID: identity.sessionID
      )
    )
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        data: successData(shouldProceed: false),
        tokenProvider: tokenProvider,
        additionalPlugins: [capture]
      )
    )
    let request = RoutineExecutionAIStepRequest(
      routineID: 31,
      executedDate: "2024-02-29",
      durationSeconds: nil,
      memberInput: "",
      actualWakeTime: nil
    )

    let decision = try await service.evaluate(
      request,
      authorizedFor: identity
    )

    XCTAssertFalse(decision.shouldProceed)
    let body = try jsonBody(try XCTUnwrap(capture.request))
    XCTAssertEqual(body["memberInput"] as? String, "")
    XCTAssertNil(body["durationSecond"])
    XCTAssertNil(body["actualWakeTime"])
  }

  func testFiveHundredUTF16UnitBoundary() async throws {
    let client = RoutineExecutionAIStepPayloadClient(
      result: .success(validResponseDTO())
    )
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: client
    )
    let boundary = String(repeating: "가", count: 500)

    _ = try await service.evaluate(
      validRequest(memberInput: boundary),
      authorizedFor: identity
    )
    XCTAssertEqual(client.callCount, 1)

    await assertAIStepError(.invalidRequest(.memberInput)) {
      _ = try await service.evaluate(
        self.validRequest(memberInput: boundary + "나"),
        authorizedFor: self.identity
      )
    }
    XCTAssertEqual(client.callCount, 1)

    let emojiBoundary = String(repeating: "😀", count: 250)
    _ = try await service.evaluate(
      validRequest(memberInput: emojiBoundary),
      authorizedFor: identity
    )
    XCTAssertEqual(client.callCount, 2)
    await assertAIStepError(.invalidRequest(.memberInput)) {
      _ = try await service.evaluate(
        self.validRequest(memberInput: emojiBoundary + "a"),
        authorizedFor: self.identity
      )
    }
    XCTAssertEqual(client.callCount, 2)
  }

  func testDateTimeAndDurationBoundariesAreAccepted() async throws {
    let client = RoutineExecutionAIStepPayloadClient(
      result: .success(validResponseDTO())
    )
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: client
    )
    let boundaryRequests = [
      validRequest(
        executedDate: "2000-02-29",
        durationSeconds: 0,
        actualWakeTime: "00:00"
      ),
      validRequest(
        executedDate: "9999-12-31",
        durationSeconds: Int(Int32.max),
        actualWakeTime: "23:59"
      ),
    ]

    for request in boundaryRequests {
      _ = try await service.evaluate(
        request,
        authorizedFor: identity
      )
    }

    XCTAssertEqual(client.callCount, boundaryRequests.count)
  }

  func testInvalidRequestNeverStartsTransport() async {
    let client = RoutineExecutionAIStepPayloadClient(
      result: .success(validResponseDTO())
    )
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: client
    )
    let invalid: [
      (
        AccountSessionIdentity,
        RoutineExecutionAIStepRequest,
        RoutineExecutionAIStepInvalidRequest
      )
    ] = [
      (
        .init(memberID: 0, sessionID: UUID()),
        validRequest(),
        .memberID
      ),
      (identity, validRequest(routineID: 0), .routineID),
      (identity, validRequest(routineID: -1), .routineID),
      (
        identity,
        validRequest(executedDate: "2026-02-29"),
        .executedDate
      ),
      (
        identity,
        validRequest(executedDate: "2026-8-13"),
        .executedDate
      ),
      (
        identity,
        validRequest(executedDate: "0000-01-01"),
        .executedDate
      ),
      (
        identity,
        validRequest(executedDate: "2026-08-13T00:00:00"),
        .executedDate
      ),
      (
        identity,
        validRequest(durationSeconds: -1),
        .durationSeconds
      ),
      (
        identity,
        validRequest(durationSeconds: Int(Int32.max) + 1),
        .durationSeconds
      ),
      (
        identity,
        validRequest(actualWakeTime: "24:00"),
        .actualWakeTime
      ),
      (
        identity,
        validRequest(actualWakeTime: "7:23"),
        .actualWakeTime
      ),
      (
        identity,
        validRequest(actualWakeTime: "07:23:00"),
        .actualWakeTime
      ),
    ]

    for (identity, request, reason) in invalid {
      await assertAIStepError(.invalidRequest(reason)) {
        _ = try await service.evaluate(
          request,
          authorizedFor: identity
        )
      }
    }
    XCTAssertEqual(client.callCount, 0)
  }

  func testMalformedMissingAndBlankResponseAreInvalid() async {
    let malformedService = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        data: Data(#"{"isSuccess":true,"result":"broken"}"#.utf8),
        tokenProvider: tokenProvider()
      )
    )
    await assertAIStepError(.invalidResponse) {
      _ = try await malformedService.evaluate(
        self.validRequest(),
        authorizedFor: self.identity
      )
    }

    let missingResultService = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        data: Data(
          #"{"isSuccess":true,"code":"COMMON200","message":"ok","result":null}"#.utf8
        ),
        tokenProvider: tokenProvider()
      )
    )
    await assertAIStepError(.invalidResponse) {
      _ = try await missingResultService.evaluate(
        self.validRequest(),
        authorizedFor: self.identity
      )
    }

    for response in [
      RoutineExecutionAIStepResponseDTO(
        aiResponse: nil,
        shouldProceed: true
      ),
      RoutineExecutionAIStepResponseDTO(
        aiResponse: " \n ",
        shouldProceed: false
      ),
      RoutineExecutionAIStepResponseDTO(
        aiResponse: "응답",
        shouldProceed: nil
      ),
    ] {
      let service = DefaultRoutineExecutionAIStepRemoteService(
        apiClient: RoutineExecutionAIStepPayloadClient(
          result: .success(response)
        )
      )
      await assertAIStepError(.invalidResponse) {
        _ = try await service.evaluate(
          self.validRequest(),
          authorizedFor: self.identity
        )
      }
    }
  }

  func testTimeoutIsClassifiedAndNeverRetried() async {
    let client = RoutineExecutionAIStepPayloadClient(
      result: .failure(
        APIError.transport(
          code: URLError.timedOut.rawValue,
          message: "timed out"
        )
      )
    )
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: client
    )

    await assertAIStepError(.timeout) {
      _ = try await service.evaluate(
        self.validRequest(),
        authorizedFor: self.identity
      )
    }
    try? await _Concurrency.Task<Never, Never>.sleep(
      for: .milliseconds(100)
    )
    XCTAssertEqual(client.callCount, 1)
  }

  func testUnauthorizedResponseDoesNotRefreshOrReplayRequest() async {
    let capture = RoutineExecutionAIStepRequestCapturePlugin()
    let refresher = RoutineExecutionAIStepRefreshSpy()
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        statusCode: 401,
        data: Data(
          #"{"isSuccess":false,"code":"COMMON401","message":"인증이 필요합니다."}"#.utf8
        ),
        tokenProvider: tokenProvider(),
        accessTokenRefresher: refresher,
        additionalPlugins: [capture]
      )
    )

    await assertAIStepError(
      .serverRejected(statusCode: 401, code: "COMMON401")
    ) {
      _ = try await service.evaluate(
        self.validRequest(),
        authorizedFor: self.identity
      )
    }

    XCTAssertEqual(capture.requestCount, 1)
    let refreshCallCount = await refresher.callCount
    XCTAssertEqual(refreshCallCount, 0)
  }

  func testTransportAndServerFailuresHaveStableClassifications() async {
    let cases: [(APIError, RoutineExecutionAIStepError)] = [
      (
        .transport(
          code: URLError.notConnectedToInternet.rawValue,
          message: "offline"
        ),
        .offline
      ),
      (
        .server(statusCode: 408, code: "COMMON408", message: "timeout"),
        .timeout
      ),
      (
        .server(statusCode: 429, code: "COMMON429", message: "busy"),
        .serverUnavailable(statusCode: 429)
      ),
      (
        .server(statusCode: 503, code: "COMMON503", message: "down"),
        .serverUnavailable(statusCode: 503)
      ),
      (
        .server(statusCode: 404, code: "ROUTINE4004", message: "private"),
        .serverRejected(statusCode: 404, code: "ROUTINE4004")
      ),
    ]

    for (apiError, expected) in cases {
      let service = DefaultRoutineExecutionAIStepRemoteService(
        apiClient: RoutineExecutionAIStepPayloadClient(
          result: .failure(apiError)
        )
      )
      await assertAIStepError(expected) {
        _ = try await service.evaluate(
          self.validRequest(),
          authorizedFor: self.identity
        )
      }
    }
  }

  func testWrappedAlamofireTimeoutPreservesURLCode() {
    let timeout = URLError(.timedOut)
    let error = MoyaError.underlying(
      AFError.sessionTaskFailed(error: timeout),
      nil
    )

    guard case .transport(let code, _) = DefaultAPIClient.mapMoyaError(
      error
    ) else {
      return XCTFail("Expected a transport error.")
    }
    XCTAssertEqual(code, URLError.timedOut.rawValue)
  }

  func testCancellationIsNativeAndNeverRetried() async {
    for error in [CancellationError(), APIError.cancelled] as [any Error] {
      let client = RoutineExecutionAIStepPayloadClient(
        result: .failure(error)
      )
      let service = DefaultRoutineExecutionAIStepRemoteService(
        apiClient: client
      )

      do {
        _ = try await service.evaluate(
          validRequest(),
          authorizedFor: identity
        )
        XCTFail("Expected cancellation.")
      } catch is CancellationError {
        XCTAssertEqual(client.callCount, 1)
      } catch {
        XCTFail("Expected CancellationError, got \(error)")
      }
    }
  }

  func testAlreadyCancelledTaskNeverStartsTransport() async {
    let client = RoutineExecutionAIStepPayloadClient(
      result: .success(validResponseDTO())
    )
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: client
    )
    let task = _Concurrency.Task {
      try await _Concurrency.Task<Never, Never>.sleep(
        for: .milliseconds(10)
      )
      return try await service.evaluate(
        self.validRequest(),
        authorizedFor: self.identity
      )
    }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      XCTAssertEqual(client.callCount, 0)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testAlreadyCancelledRequestOnceNeverCreatesTransport() async {
    let capture = RoutineExecutionAIStepRequestCapturePlugin()
    let client = makeClient(
      data: successData(shouldProceed: true),
      tokenProvider: tokenProvider(),
      additionalPlugins: [capture]
    )

    let task = _Concurrency.Task {
      withUnsafeCurrentTask { currentTask in
        currentTask?.cancel()
      }
      return try await client.requestOnce(
        RoutineExecutionAIStepTarget.evaluate(
          RoutineExecutionAIStepRequestDTO(
            routineId: 31,
            executedDate: "2026-08-13",
            durationSecond: 20,
            memberInput: "응, 다음",
            actualWakeTime: "07:23"
          )
        ),
        as: RoutineExecutionAIStepResponseDTO.self,
        authorizedFor: identity
      )
    }

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      XCTAssertEqual(capture.requestCount, 0)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testInFlightCancellationCancelsOneUnderlyingRequest() async throws {
    let capture = RoutineExecutionAIStepRequestCapturePlugin()
    let cancellationObserver = RoutineExecutionAIStepCancellationObserver()
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        data: successData(shouldProceed: true),
        delay: 1,
        tokenProvider: tokenProvider(),
        additionalPlugins: [capture],
        requestCancellationFactory: {
          RequestCancellation(onCancel: cancellationObserver.record)
        }
      )
    )
    let task = _Concurrency.Task {
      try await service.evaluate(
        self.validRequest(),
        authorizedFor: self.identity
      )
    }
    try await waitUntil { capture.request != nil }
    task.cancel()
    try await waitUntil { cancellationObserver.callCount == 1 }

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      XCTAssertEqual(capture.requestCount, 1)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testRequestCancellationCancelsBeforeAndAfterStoreExactlyOnce() {
    for cancelBeforeStore in [false, true] {
      let cancellation = RequestCancellation()
      let request = RoutineExecutionAIStepCancellableSpy()

      if cancelBeforeStore {
        cancellation.cancel()
        cancellation.store(request)
      } else {
        cancellation.store(request)
        cancellation.cancel()
      }
      cancellation.cancel()

      XCTAssertTrue(request.isCancelled)
      XCTAssertEqual(request.cancelCallCount, 1)
    }
  }

  func testStaleSessionAtEntryNeverCreatesTransport() async {
    let staleIdentity = identity
    let tokenProvider = RoutineExecutionAIStepTokenProvider(
      context: AccountAuthorizationContext(
        memberID: staleIdentity.memberID,
        accessToken: "replacement-session-token",
        sessionID: UUID()
      )
    )
    let capture = RoutineExecutionAIStepRequestCapturePlugin()
    let service = DefaultRoutineExecutionAIStepRemoteService(
      apiClient: makeClient(
        data: successData(shouldProceed: true),
        tokenProvider: tokenProvider,
        additionalPlugins: [capture]
      )
    )

    await assertAIStepError(.accountAuthorizationChanged) {
      _ = try await service.evaluate(
        self.validRequest(),
        authorizedFor: staleIdentity
      )
    }
    XCTAssertEqual(capture.requestCount, 0)
  }

  func testExactSessionRejectsDifferentAccountAndSameMemberRelogin()
    async throws {
    for newMemberID in [Int64(99), identity.memberID] {
      let tokenProvider = RoutineExecutionAIStepTokenProvider(
        context: AccountAuthorizationContext(
          memberID: identity.memberID,
          accessToken: "first-session-token",
          sessionID: identity.sessionID
        )
      )
      let capture = RoutineExecutionAIStepRequestCapturePlugin()
      let service = DefaultRoutineExecutionAIStepRemoteService(
        apiClient: makeClient(
          data: successData(shouldProceed: true),
          delay: 0.1,
          tokenProvider: tokenProvider,
          additionalPlugins: [capture]
        )
      )
      let task = _Concurrency.Task {
        try await service.evaluate(
          self.validRequest(),
          authorizedFor: self.identity
        )
      }
      try await waitUntil { capture.request != nil }
      tokenProvider.replace(
        with: AccountAuthorizationContext(
          memberID: newMemberID,
          accessToken: "second-session-token",
          sessionID: UUID()
        )
      )

      await assertAIStepError(.accountAuthorizationChanged) {
        _ = try await task.value
      }
      XCTAssertEqual(capture.requestCount, 1)
    }
  }

  func testUseCaseWithoutGeminiConsentDoesNotStartRemoteRequest() async {
    let account = MutableAIStepSessionIdentityProvider(identity: identity)
    let remote = DeferredRoutineExecutionAIStepRemoteService()
    let consent = GeminiDataConsentStub(hasExplicitGeminiDataConsent: false)
    let useCase = EvaluateRoutineExecutionAIStepUseCase(
      remoteService: remote,
      sessionIdentityProvider: account,
      geminiDataConsent: consent
    )

    await assertAIStepError(.geminiConsentRequired) {
      _ = try await useCase.evaluate(self.validRequest())
    }

    XCTAssertEqual(consent.requestCount, 1)
    let callCount = await remote.callCount
    XCTAssertEqual(callCount, 0)
  }

  func testUseCaseRejectsDifferentAccountAndSameMemberRelogin()
    async throws {
    for newMemberID in [Int64(99), identity.memberID] {
      let account = MutableAIStepSessionIdentityProvider(identity: identity)
      let remote = DeferredRoutineExecutionAIStepRemoteService()
      let useCase = EvaluateRoutineExecutionAIStepUseCase(
        remoteService: remote,
        sessionIdentityProvider: account,
        geminiDataConsent: GeminiDataConsentStub()
      )
      let task = _Concurrency.Task {
        try await useCase.evaluate(self.validRequest())
      }
      await remote.waitUntilRequested()
      account.identity = AccountSessionIdentity(
        memberID: newMemberID,
        sessionID: UUID()
      )
      await remote.finish(with: validDecision())

      await assertAIStepError(.accountAuthorizationChanged) {
        _ = try await task.value
      }
      let callCount = await remote.callCount
      XCTAssertEqual(callCount, 1)
    }
  }

  func testUseCaseRejectsStaleFailureAfterSameMemberRelogin()
    async throws {
    let account = MutableAIStepSessionIdentityProvider(identity: identity)
    let remote = DeferredFailingRoutineExecutionAIStepRemoteService()
    let useCase = EvaluateRoutineExecutionAIStepUseCase(
      remoteService: remote,
      sessionIdentityProvider: account,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let task = _Concurrency.Task {
      try await useCase.evaluate(self.validRequest())
    }
    await remote.waitUntilRequested()
    account.identity = AccountSessionIdentity(
      memberID: identity.memberID,
      sessionID: UUID()
    )
    await remote.finish()

    await assertAIStepError(.accountAuthorizationChanged) {
      _ = try await task.value
    }
    let callCount = await remote.callCount
    XCTAssertEqual(callCount, 1)
  }

  func testCancelledUseCaseFailureKeepsNativeCancellationPriority()
    async throws {
    let account = MutableAIStepSessionIdentityProvider(identity: identity)
    let remote = DeferredFailingRoutineExecutionAIStepRemoteService()
    let useCase = EvaluateRoutineExecutionAIStepUseCase(
      remoteService: remote,
      sessionIdentityProvider: account,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let task = _Concurrency.Task {
      try await useCase.evaluate(self.validRequest())
    }
    await remote.waitUntilRequested()
    task.cancel()
    account.identity = AccountSessionIdentity(
      memberID: identity.memberID,
      sessionID: UUID()
    )
    await remote.finish()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      let callCount = await remote.callCount
      XCTAssertEqual(callCount, 1)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testUseCaseCancellationAndSignedOutBoundary() async {
    let signedOut = MutableAIStepSessionIdentityProvider(identity: nil)
    let unused = DeferredRoutineExecutionAIStepRemoteService()
    let signedOutUseCase = EvaluateRoutineExecutionAIStepUseCase(
      remoteService: unused,
      sessionIdentityProvider: signedOut,
      geminiDataConsent: GeminiDataConsentStub()
    )
    await assertAIStepError(.accountSessionUnavailable) {
      _ = try await signedOutUseCase.evaluate(self.validRequest())
    }
    let signedOutCallCount = await unused.callCount
    XCTAssertEqual(signedOutCallCount, 0)

    let account = MutableAIStepSessionIdentityProvider(identity: identity)
    let remote = DeferredRoutineExecutionAIStepRemoteService()
    let useCase = EvaluateRoutineExecutionAIStepUseCase(
      remoteService: remote,
      sessionIdentityProvider: account,
      geminiDataConsent: GeminiDataConsentStub()
    )
    let task = _Concurrency.Task {
      try await useCase.evaluate(self.validRequest())
    }
    await remote.waitUntilRequested()
    task.cancel()
    await remote.finish(with: validDecision())

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      let callCount = await remote.callCount
      XCTAssertEqual(callCount, 1)
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testSensitiveDescriptionsAndNetworkLogsAreRedacted() {
    let memberInput = "private-member-input-sentinel"
    let aiResponse = "private-ai-response-sentinel"
    let accessToken = "private-access-token-sentinel"
    let requestDTO = RoutineExecutionAIStepRequestDTO(
      routineId: 31,
      executedDate: "2026-08-13",
      durationSecond: 20,
      memberInput: memberInput,
      actualWakeTime: "07:23"
    )
    let target = RoutineExecutionAIStepTarget.evaluate(requestDTO)
    let request = validRequest(memberInput: memberInput)
    let decision = RoutineExecutionAIStepDecision(
      aiResponse: aiResponse,
      shouldProceed: true
    )
    let adaptedTarget = MoyaTargetAdapter(
      target: target,
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: accessToken
    )
    let messages = [
      String(describing: requestDTO),
      String(reflecting: requestDTO),
      String(describing: target),
      String(reflecting: target),
      String(describing: request),
      String(reflecting: request),
      String(describing: decision),
      String(reflecting: decision),
      NetworkLogPlugin.requestMessage(for: adaptedTarget),
      NetworkLogPlugin.responseMessage(
        statusCode: 200,
        target: adaptedTarget
      ),
      NetworkLogPlugin.failureMessage(for: adaptedTarget),
    ]

    for message in messages {
      XCTAssertFalse(message.contains(memberInput))
      XCTAssertFalse(message.contains(aiResponse))
      XCTAssertFalse(message.contains(accessToken))
      XCTAssertFalse(message.contains("shouldProceed\":true"))
    }
  }

  private func validRequest(
    routineID: Int64 = 31,
    executedDate: String = "2026-08-13",
    durationSeconds: Int? = 20,
    memberInput: String = "응, 다음",
    actualWakeTime: String? = "07:23"
  ) -> RoutineExecutionAIStepRequest {
    RoutineExecutionAIStepRequest(
      routineID: routineID,
      executedDate: executedDate,
      durationSeconds: durationSeconds,
      memberInput: memberInput,
      actualWakeTime: actualWakeTime
    )
  }

  private func validResponseDTO() -> RoutineExecutionAIStepResponseDTO {
    RoutineExecutionAIStepResponseDTO(
      aiResponse: "다음으로 넘어갈게요!",
      shouldProceed: true
    )
  }

  private func validDecision() -> RoutineExecutionAIStepDecision {
    RoutineExecutionAIStepDecision(
      aiResponse: "다음으로 넘어갈게요!",
      shouldProceed: true
    )
  }

  nonisolated private func successData(shouldProceed: Bool) -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "aiResponse": "판정 응답",
          "shouldProceed": \(shouldProceed)
        }
      }
      """.utf8
    )
  }

  nonisolated private func makeClient(
    statusCode: Int = 200,
    data: Data,
    delay: TimeInterval? = nil,
    tokenProvider: RoutineExecutionAIStepTokenProvider,
    accessTokenRefresher: (any AccessTokenRefreshing)? = nil,
    additionalPlugins: [any PluginType & Sendable] = [],
    requestCancellationFactory: @escaping @Sendable () -> RequestCancellation = {
      RequestCancellation()
    }
  ) -> DefaultAPIClient {
    DefaultAPIClient(
      tokenProvider: tokenProvider,
      accessTokenRefresher: accessTokenRefresher,
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>.defaultEndpointMapping(
            for: target
          )
          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkResponse(statusCode, data)
            },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in
          delay.map(StubBehavior.delayed(seconds:)) ?? .immediate
        },
        additionalPlugins: additionalPlugins
      ),
      requestCancellationFactory: requestCancellationFactory
    )
  }

  private func tokenProvider() -> RoutineExecutionAIStepTokenProvider {
    RoutineExecutionAIStepTokenProvider(
      context: AccountAuthorizationContext(
        memberID: identity.memberID,
        accessToken: "access-token",
        sessionID: identity.sessionID
      )
    )
  }

  private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: try XCTUnwrap(request.httpBody)
      ) as? [String: Any]
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
      guard clock.now < deadline else {
        return XCTFail("Timed out waiting for AI-step transport.")
      }
      try await _Concurrency.Task<Never, Never>.sleep(
        for: .milliseconds(10)
      )
    }
  }

  private func assertAIStepError(
    _ expected: RoutineExecutionAIStepError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as RoutineExecutionAIStepError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected RoutineExecutionAIStepError, got \(error)")
    }
  }
}

nonisolated private final class RoutineExecutionAIStepPayloadClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let lock = NSLock()
  private let result: Result<RoutineExecutionAIStepResponseDTO, any Error>
  private var requestCount = 0
  private var requestedIdentities: [AccountSessionIdentity] = []

  init(result: Result<RoutineExecutionAIStepResponseDTO, any Error>) {
    self.result = result
  }

  var callCount: Int {
    lock.withLock { requestCount }
  }

  var identities: [AccountSessionIdentity] {
    lock.withLock { requestedIdentities }
  }

  func requestOnce<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> Payload {
    lock.withLock {
      requestCount += 1
      requestedIdentities.append(identity)
    }
    let response = try result.get()
    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected AI-step payload type.")
    }
    return payload
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected exact-session request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected exact-session request.")
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

nonisolated private final class RoutineExecutionAIStepTokenProvider:
  AccountBoundAccessTokenProviding,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedContext: AccountAuthorizationContext

  init(context: AccountAuthorizationContext) {
    storedContext = context
  }

  var accessToken: String? {
    lock.withLock { storedContext.accessToken }
  }

  func authorizationContext(
    forMemberID memberID: Int64
  ) -> AccountAuthorizationContext? {
    lock.withLock {
      storedContext.memberID == memberID ? storedContext : nil
    }
  }

  func replace(with context: AccountAuthorizationContext) {
    lock.withLock { storedContext = context }
  }
}

nonisolated private final class RoutineExecutionAIStepRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequests: [URLRequest] = []

  var request: URLRequest? {
    lock.withLock { capturedRequests.last }
  }

  var requestCount: Int {
    lock.withLock { capturedRequests.count }
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.withLock { capturedRequests.append(request) }
    return request
  }
}

nonisolated private final class RoutineExecutionAIStepCancellableSpy:
  Cancellable,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCancelCallCount = 0

  var isCancelled: Bool {
    lock.withLock { storedCancelCallCount > 0 }
  }

  var cancelCallCount: Int {
    lock.withLock { storedCancelCallCount }
  }

  func cancel() {
    lock.withLock { storedCancelCallCount += 1 }
  }
}

nonisolated private final class RoutineExecutionAIStepCancellationObserver:
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCallCount = 0

  var callCount: Int {
    lock.withLock { storedCallCount }
  }

  func record() {
    lock.withLock { storedCallCount += 1 }
  }
}

@MainActor
private final class MutableAIStepSessionIdentityProvider:
  CurrentAccountSessionIdentityProviding {
  var identity: AccountSessionIdentity?

  init(identity: AccountSessionIdentity?) {
    self.identity = identity
  }

  var currentAccountSessionIdentity: AccountSessionIdentity? {
    identity
  }
}

private actor DeferredRoutineExecutionAIStepRemoteService:
  RoutineExecutionAIStepRemoteServing {
  private var requested = false
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var responseWaiter:
    CheckedContinuation<RoutineExecutionAIStepDecision, Never>?
  private var response: RoutineExecutionAIStepDecision?
  private(set) var callCount = 0

  func evaluate(
    _ request: RoutineExecutionAIStepRequest,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> RoutineExecutionAIStepDecision {
    callCount += 1
    requested = true
    requestWaiters.forEach { $0.resume() }
    requestWaiters.removeAll()

    if let response {
      return response
    }
    return await withCheckedContinuation { continuation in
      responseWaiter = continuation
    }
  }

  func waitUntilRequested() async {
    guard !requested else { return }
    await withCheckedContinuation { continuation in
      requestWaiters.append(continuation)
    }
  }

  func finish(with response: RoutineExecutionAIStepDecision) {
    if let responseWaiter {
      self.responseWaiter = nil
      responseWaiter.resume(returning: response)
    } else {
      self.response = response
    }
  }
}

private actor DeferredFailingRoutineExecutionAIStepRemoteService:
  RoutineExecutionAIStepRemoteServing {
  private var requested = false
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var finishWaiter: CheckedContinuation<Void, Never>?
  private var isFinished = false
  private(set) var callCount = 0

  func evaluate(
    _ request: RoutineExecutionAIStepRequest,
    authorizedFor identity: AccountSessionIdentity
  ) async throws -> RoutineExecutionAIStepDecision {
    callCount += 1
    requested = true
    requestWaiters.forEach { $0.resume() }
    requestWaiters.removeAll()

    if !isFinished {
      await withCheckedContinuation { continuation in
        finishWaiter = continuation
      }
    }
    throw RoutineExecutionAIStepError.offline
  }

  func waitUntilRequested() async {
    guard !requested else { return }
    await withCheckedContinuation { continuation in
      requestWaiters.append(continuation)
    }
  }

  func finish() {
    isFinished = true
    finishWaiter?.resume()
    finishWaiter = nil
  }
}

private actor RoutineExecutionAIStepRefreshSpy:
  AccountBoundAccessTokenRefreshing {
  private(set) var callCount = 0

  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String
  ) async throws -> AccessTokenRefreshResult {
    callCount += 1
    return AccessTokenRefreshResult(
      accessToken: "refreshed-access-token",
      refreshToken: "refreshed-refresh-token"
    )
  }

  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String,
    matching authorizationContext: AccountAuthorizationContext
  ) async throws -> AccessTokenRefreshResult {
    callCount += 1
    return AccessTokenRefreshResult(
      accessToken: "refreshed-access-token",
      refreshToken: "refreshed-refresh-token"
    )
  }
}
