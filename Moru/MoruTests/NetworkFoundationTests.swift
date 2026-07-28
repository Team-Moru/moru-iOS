//
//  NetworkFoundationTests.swift
//  MoruTests
//

import XCTest

import Alamofire
import Moya

@testable import Moru

@MainActor
final class NetworkFoundationTests: XCTestCase {
  func testProductionBaseURLAndHealthTargetContract() {
    XCTAssertEqual(
      NetworkConfiguration.production.baseURL.absoluteString,
      "https://moru-api.duckdns.org"
    )
    XCTAssertEqual(NetworkConfiguration.production.requestTimeout, 15)
    XCTAssertEqual(NetworkConfiguration.production.resourceTimeout, 30)
    XCTAssertEqual(HealthTarget.status.path, "/health")
    XCTAssertEqual(HealthTarget.status.method, .get)
    XCTAssertEqual(HealthTarget.status.authenticationRequirement, .none)
    XCTAssertEqual(String(data: HealthTarget.status.sampleData, encoding: .utf8), "OK")

    let adapter = MoyaTargetAdapter(
      target: HealthTarget.status,
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: nil
    )
    XCTAssertNil(adapter.authorizationType)
    XCTAssertEqual(adapter.validationType, .none)
  }

  func testAdapterCarriesBearerTokenSnapshot() {
    let bearerTarget = MoyaTargetAdapter(
      target: StubTarget(authenticationRequirement: .bearer),
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: "access-token"
    )

    XCTAssertEqual(bearerTarget.authorizationType, .bearer)
    XCTAssertEqual(bearerTarget.requestAccessToken, "access-token")

    let publicTarget = MoyaTargetAdapter(
      target: HealthTarget.status,
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: nil
    )
    XCTAssertNil(publicTarget.authorizationType)
    XCTAssertNil(publicTarget.requestAccessToken)
  }

  func testAdapterRejectsTargetManagedAuthorizationHeader() {
    let target = MoyaTargetAdapter(
      target: SensitiveStubTarget(),
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: "access-token"
    )

    XCTAssertFalse(
      target.headers?.keys.contains {
        $0.caseInsensitiveCompare("Authorization") == .orderedSame
      } ?? false
    )
  }

  func testAuthenticatedRequestWithoutTokenFailsBeforeTransport() async {
    let client = makeClient(statusCode: 200, data: successData())

    await assertAPIError(.authenticationRequired) {
      let _: StubResult = try await client.request(
        StubTarget(authenticationRequirement: .bearer),
        as: StubResult.self
      )
    }
  }

  func testDisabledServerCapabilityBlocksPublicAndBearerRequestsBeforeTransport() async {
    let requestCapture = RequestCapturePlugin()
    let tokenProvider = StubAccessTokenProvider(accessToken: "access-token")
    let client = DefaultAPIClient(
      tokenProvider: tokenProvider,
      serverRequestsEnabled: false,
      providerFactory: MoyaProviderFactory(
        stubBuilder: { _ in .immediate },
        additionalPlugins: [requestCapture]
      )
    )

    await assertAPIError(.capabilityDisabled) {
      _ = try await client.requestData(HealthTarget.status)
    }
    await assertAPIError(.capabilityDisabled) {
      _ = try await client.requestData(
        StubTarget(authenticationRequirement: .bearer)
      )
    }

    XCTAssertNil(requestCapture.request)
  }

  func testSuccessfulEnvelopeReturnsResult() async throws {
    let client: any APIClient = makeClient(
      statusCode: 200,
      data: successData()
    )

    let result = try await client.request(
      StubTarget(authenticationRequirement: .none),
      as: StubResult.self
    )

    XCTAssertEqual(result, StubResult(value: "ready"))
  }

  func testLogicalFailureInSuccessfulHTTPResponseMapsServerError() async {
    let data = Data(
      """
      {
        "isSuccess": false,
        "code": "ROUTINE4001",
        "message": "루틴을 찾을 수 없습니다.",
        "result": null
      }
      """.utf8
    )
    let client = makeClient(statusCode: 200, data: data)

    await assertAPIError(
      .server(
        statusCode: 200,
        code: "ROUTINE4001",
        message: "루틴을 찾을 수 없습니다."
      )
    ) {
      let _: StubResult = try await client.request(
        StubTarget(authenticationRequirement: .none),
        as: StubResult.self
      )
    }
  }

  func testHTTPFailurePreservesServerCodeAndMessage() async {
    let data = Data(
      """
      {
        "isSuccess": false,
        "code": "COMMON401",
        "message": "인증이 필요합니다."
      }
      """.utf8
    )
    let client = makeClient(statusCode: 401, data: data)

    await assertAPIError(
      .server(
        statusCode: 401,
        code: "COMMON401",
        message: "인증이 필요합니다."
      )
    ) {
      _ = try await client.requestData(
        StubTarget(authenticationRequirement: .none)
      )
    }
  }

  func testSuccessfulEnvelopeWithoutRequiredResultFails() async {
    let data = Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": null
      }
      """.utf8
    )
    let client = makeClient(statusCode: 200, data: data)

    await assertAPIError(
      .missingResult(code: "COMMON200", message: "성공입니다.")
    ) {
      let _: StubResult = try await client.request(
        StubTarget(authenticationRequirement: .none),
        as: StubResult.self
      )
    }
  }

  func testVoidResponseAllowsMissingResult() async throws {
    let data = Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다."
      }
      """.utf8
    )
    let client = makeClient(statusCode: 200, data: data)

    try await client.requestVoid(
      StubTarget(authenticationRequirement: .none)
    )
  }

  func testVoidResponseAllowsEmpty204Response() async throws {
    let client = makeClient(statusCode: 204, data: Data())

    try await client.requestVoid(
      StubTarget(authenticationRequirement: .none)
    )
  }

  func testVoidResponseAllowsEmpty205Response() async throws {
    let client = makeClient(statusCode: 205, data: Data())

    try await client.requestVoid(
      StubTarget(authenticationRequirement: .none)
    )
  }

  func testMalformedJSONMapsDecodingError() async {
    let client = makeClient(statusCode: 200, data: Data("not-json".utf8))

    do {
      let _: StubResult = try await client.request(
        StubTarget(authenticationRequirement: .none),
        as: StubResult.self
      )
      XCTFail("Expected decoding error")
    } catch let error as APIError {
      guard case .decoding = error else {
        return XCTFail("Expected decoding error, got \(error)")
      }
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  func testRawHealthResponseReturnsData() async throws {
    let client = makeClient(statusCode: 200, data: Data("OK".utf8))

    let data = try await client.requestData(HealthTarget.status)

    XCTAssertEqual(String(data: data, encoding: .utf8), "OK")
  }

  func testTransportFailurePreservesURLError() async {
    let underlying = NSError(
      domain: NSURLErrorDomain,
      code: URLError.notConnectedToInternet.rawValue
    )
    let client = makeErrorClient(underlying)

    await assertAPIError(
      .transport(
        code: underlying.code,
        message: underlying.localizedDescription
      )
    ) {
      _ = try await client.requestData(
        StubTarget(authenticationRequirement: .none)
      )
    }
  }

  func testTaskCancellationCancelsUnderlyingRequest() async {
    let client = makeClient(
      statusCode: 200,
      data: Data("OK".utf8),
      stubBehavior: .delayed(seconds: 0.1)
    )
    let task = _Concurrency.Task {
      try await client.requestData(
        StubTarget(authenticationRequirement: .none)
      )
    }

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as APIError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  func testExplicitAlamofireCancellationMapsCancelled() {
    let error = MoyaError.underlying(
      AFError.explicitlyCancelled,
      nil
    )

    XCTAssertEqual(
      DefaultAPIClient.mapMoyaError(error),
      .cancelled
    )
  }

  func testFactoryAppliesRequestAndResourceTimeouts() {
    let configuration = NetworkConfiguration(
      baseURL: URL(string: "https://staging.example.com")!,
      requestTimeout: 7,
      resourceTimeout: 20
    )
    let sessionConfiguration = MoyaProviderFactory()
      .makeSessionConfiguration(configuration: configuration)

    XCTAssertEqual(sessionConfiguration.timeoutIntervalForRequest, 7)
    XCTAssertEqual(sessionConfiguration.timeoutIntervalForResource, 20)
  }

  func testClientAppliesConfigurationAndAuthenticationPlugins() async throws {
    let tokenProvider = StubAccessTokenProvider(accessToken: "access-token")
    let requestCapture = RequestCapturePlugin()
    let configuration = NetworkConfiguration(
      baseURL: URL(string: "https://staging.example.com/api")!,
      requestTimeout: 7,
      resourceTimeout: 20
    )
    let client = makeClient(
      statusCode: 200,
      data: Data("OK".utf8),
      configuration: configuration,
      tokenProvider: tokenProvider,
      additionalPlugins: [requestCapture]
    )

    _ = try await client.requestData(
      StubTarget(authenticationRequirement: .bearer)
    )

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertEqual(request.url?.absoluteString, "https://staging.example.com/api/stub")
    XCTAssertEqual(request.timeoutInterval, 7)
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
  }

  func testClientDoesNotAuthenticatePublicTarget() async throws {
    let tokenProvider = ChangingAccessTokenProvider()
    let requestCapture = RequestCapturePlugin()
    let client = makeClient(
      statusCode: 200,
      data: Data("OK".utf8),
      tokenProvider: tokenProvider,
      additionalPlugins: [requestCapture]
    )

    _ = try await client.requestData(HealthTarget.status)

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(tokenProvider.readCount, 0)
  }

  func testAuthenticatedRequestReadsOneTokenSnapshot() async throws {
    let tokenProvider = ChangingAccessTokenProvider()
    let requestCapture = RequestCapturePlugin()
    let client = makeClient(
      statusCode: 200,
      data: Data("OK".utf8),
      tokenProvider: tokenProvider,
      additionalPlugins: [requestCapture]
    )

    _ = try await client.requestData(
      StubTarget(authenticationRequirement: .bearer)
    )

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer first-token"
    )
    XCTAssertEqual(tokenProvider.readCount, 1)
  }

  func testAccountBoundRequestRejectsSuccessAfterAccountSessionChanges() async throws {
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.establishAccountSession(
      with: "first-session-token",
      memberID: 96
    )
    let requestCapture = RequestCapturePlugin()
    let client = makeClient(
      statusCode: 200,
      data: successData(),
      stubBehavior: .delayed(seconds: 0.1),
      tokenProvider: tokenProvider,
      additionalPlugins: [requestCapture]
    )
    let request = _Concurrency.Task<StubResult, Error> {
      try await client.request(
        StubTarget(authenticationRequirement: .bearer),
        as: StubResult.self,
        authorizedForMemberID: 96
      )
    }
    try await waitUntil {
      requestCapture.request != nil
    }

    tokenProvider.establishAccountSession(
      with: "second-session-token",
      memberID: 96
    )

    do {
      _ = try await request.value
      XCTFail("Expected the stale account response to be rejected.")
    } catch let error as AccountAuthorizationContextError {
      XCTAssertEqual(error, .memberMismatch)
    } catch {
      XCTFail("Expected AccountAuthorizationContextError, got \(error)")
    }
  }

  func testAccountBoundRequestPrioritizesSessionChangeOverTransportFailure() async throws {
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.establishAccountSession(
      with: "first-session-token",
      memberID: 96
    )
    let requestCapture = RequestCapturePlugin()
    let underlying = NSError(
      domain: NSURLErrorDomain,
      code: URLError.notConnectedToInternet.rawValue
    )
    let client = makeErrorClient(
      underlying,
      stubBehavior: .delayed(seconds: 0.1),
      tokenProvider: tokenProvider,
      additionalPlugins: [requestCapture]
    )
    let request = _Concurrency.Task<StubResult, Error> {
      try await client.request(
        StubTarget(authenticationRequirement: .bearer),
        as: StubResult.self,
        authorizedForMemberID: 96
      )
    }
    try await waitUntil {
      requestCapture.request != nil
    }

    tokenProvider.establishAccountSession(
      with: "second-session-token",
      memberID: 96
    )

    do {
      _ = try await request.value
      XCTFail("Expected the stale account failure to be rejected.")
    } catch let error as AccountAuthorizationContextError {
      XCTAssertEqual(error, .memberMismatch)
    } catch {
      XCTFail("Expected AccountAuthorizationContextError, got \(error)")
    }
  }

  func testRetryabilityClassification() {
    XCTAssertTrue(
      APIError.transport(
        code: URLError.timedOut.rawValue,
        message: "timed out"
      ).isRetryable
    )
    XCTAssertTrue(
      APIError.server(
        statusCode: 503,
        code: "COMMON503",
        message: "잠시 후 다시 시도해 주세요."
      ).isRetryable
    )
    XCTAssertFalse(APIError.authenticationRequired.isRetryable)
    XCTAssertFalse(APIError.capabilityDisabled.isRetryable)
    XCTAssertFalse(APIError.cancelled.isRetryable)
  }

  func testNetworkLogMessageExcludesHeadersAndBody() {
    let target = MoyaTargetAdapter(
      target: SensitiveStubTarget(),
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: "secret-token"
    )
    let message = NetworkLogPlugin.requestMessage(for: target)

    XCTAssertEqual(message, "➡️ POST /stub")
    XCTAssertFalse(message.contains("secret-token"))
    XCTAssertFalse(message.contains("private routine text"))
  }

  private func assertAPIError(
    _ expected: APIError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected)")
    } catch let error as APIError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
  }

  nonisolated private func makeClient(
    statusCode: Int,
    data: Data,
    stubBehavior: TestStubBehavior = .immediate,
    configuration: NetworkConfiguration = .production,
    tokenProvider: any AccessTokenProviding = EmptyAccessTokenProvider(),
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAPIClient {
    return DefaultAPIClient(
      configuration: configuration,
      tokenProvider: tokenProvider,
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
        stubBuilder: { _ in stubBehavior.moyaValue },
        additionalPlugins: additionalPlugins
      )
    )
  }

  nonisolated private func makeErrorClient(
    _ error: NSError,
    stubBehavior: TestStubBehavior = .immediate,
    tokenProvider: any AccessTokenProviding = EmptyAccessTokenProvider(),
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAPIClient {
    return DefaultAPIClient(
      tokenProvider: tokenProvider,
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          let endpoint = MoyaProvider<MultiTarget>.defaultEndpointMapping(
            for: target
          )

          return Endpoint(
            url: endpoint.url,
            sampleResponseClosure: {
              .networkError(error)
            },
            method: endpoint.method,
            task: endpoint.task,
            httpHeaderFields: endpoint.httpHeaderFields
          )
        },
        stubBuilder: { _ in stubBehavior.moyaValue },
        additionalPlugins: additionalPlugins
      )
    )
  }

  private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping @Sendable () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while !condition() {
      guard Date() < deadline else {
        XCTFail("Timed out waiting for the request to start.")
        return
      }

      try await _Concurrency.Task.sleep(for: .milliseconds(5))
    }
  }

  nonisolated private func successData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "value": "ready"
        }
      }
      """.utf8
    )
  }
}

nonisolated private struct StubResult: Decodable, Equatable, Sendable {
  let value: String
}

nonisolated private struct StubTarget: MoruTargetType {
  let authenticationRequirement: AuthenticationRequirement

  var path: String {
    "/stub"
  }

  var method: Moya.Method {
    .get
  }

  var task: Task {
    .requestPlain
  }
}

nonisolated private struct SensitiveStubTarget: MoruTargetType {
  var path: String {
    "/stub"
  }

  var method: Moya.Method {
    .post
  }

  var task: Task {
    .requestParameters(
      parameters: ["text": "private routine text"],
      encoding: JSONEncoding.default
    )
  }

  var headers: [String: String]? {
    ["aUtHoRiZaTiOn": "Bearer secret-token"]
  }

  var authenticationRequirement: AuthenticationRequirement {
    .bearer
  }
}

nonisolated private enum TestStubBehavior: Sendable {
  case immediate
  case delayed(seconds: TimeInterval)

  var moyaValue: StubBehavior {
    switch self {
    case .immediate:
      .immediate
    case .delayed(let seconds):
      .delayed(seconds: seconds)
    }
  }
}

nonisolated private final class StubAccessTokenProvider:
  AccessTokenProviding
{
  let accessToken: String?

  init(accessToken: String?) {
    self.accessToken = accessToken
  }
}

nonisolated private final class ChangingAccessTokenProvider:
  AccessTokenProviding,
  @unchecked Sendable {
  private let lock = NSLock()
  private var accessCount = 0

  var accessToken: String? {
    lock.lock()
    defer { lock.unlock() }

    accessCount += 1
    return accessCount == 1 ? "first-token" : "changed-token"
  }

  var readCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return accessCount
  }
}

nonisolated private final class RequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var capturedRequest: URLRequest?

  var request: URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequest
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    lock.lock()
    capturedRequest = request
    lock.unlock()
    return request
  }
}
