//
//  AuthTokenReissueTests.swift
//  MoruTests
//

import XCTest

import Moya

@testable import Moru

@MainActor
final class AuthTokenReissueTests: XCTestCase {
  func testConcurrentBearer401RequestsShareOneRefreshAndRetryOnce() async throws {
    let credentials = makeCredentials()
    let credentialStore = TokenRefreshCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: credentials)

    let gate = TokenRefreshGate()
    let remoteDataSource = TokenRefreshRemoteDataSource(
      result: .success(makeReissueResponse()),
      gate: gate
    )
    let coordinator = TokenRefreshCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: sessionStore
    )
    let responseScript = UnauthorizedThenSuccessScript(
      unauthorizedRequestCount: 2
    )
    let requestCapture = TokenRefreshRequestCapturePlugin()
    let client = makeClient(
      tokenProvider: tokenProvider,
      accessTokenRefresher: coordinator,
      responseScript: responseScript,
      requestCapture: requestCapture
    )

    async let first = client.requestData(TokenRefreshBearerTarget())
    async let second = client.requestData(TokenRefreshBearerTarget())

    try await waitUntil {
      responseScript.requestCount == 2
        && remoteDataSource.reissueCount == 1
    }
    XCTAssertEqual(remoteDataSource.refreshTokens, ["refresh-token"])

    await gate.open()
    let responses = try await [first, second]

    XCTAssertEqual(
      responses.map { String(data: $0, encoding: .utf8) },
      ["OK", "OK"]
    )
    XCTAssertEqual(responseScript.requestCount, 4)
    XCTAssertEqual(remoteDataSource.reissueCount, 1)
    XCTAssertEqual(
      requestCapture.authorizationHeaders.filter {
        $0 == "Bearer access-token"
      }.count,
      2
    )
    XCTAssertEqual(
      requestCapture.authorizationHeaders.filter {
        $0 == "Bearer refreshed-access-token"
      }.count,
      2
    )

    let refreshedCredentials = try XCTUnwrap(credentialStore.credentials)
    XCTAssertEqual(
      refreshedCredentials,
      AccountCredentials(
        memberID: 7,
        accessToken: "refreshed-access-token",
        refreshToken: "refreshed-refresh-token",
        onboardingCompleted: false
      )
    )
    XCTAssertEqual(tokenProvider.accessToken, "refreshed-access-token")
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: 7,
          onboardingCompleted: false
        )
      )
    )
  }

  func testStaleUnauthorizedTokenUsesCurrentSnapshotWithoutRefresh() async throws {
    let credentialStore = TokenRefreshCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: makeCredentials())
    let remoteDataSource = TokenRefreshRemoteDataSource(
      result: .success(makeReissueResponse())
    )
    let coordinator = TokenRefreshCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: sessionStore
    )

    let refreshedToken = try await coordinator.refreshAccessToken(
      afterUnauthorized: "access-token"
    )
    let token = try await coordinator.refreshAccessToken(
      afterUnauthorized: "access-token"
    )

    XCTAssertEqual(refreshedToken, "refreshed-access-token")
    XCTAssertEqual(token, "refreshed-access-token")
    XCTAssertEqual(remoteDataSource.reissueCount, 1)
    XCTAssertEqual(tokenProvider.accessToken, "refreshed-access-token")
  }

  func testOld401DoesNotRetryWithAnUnrelatedReplacementSession() async throws {
    let credentialStore = TokenRefreshCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: makeCredentials())
    let replacementCredentials = AccountCredentials(
      memberID: 9,
      accessToken: "new-account-token",
      refreshToken: "new-account-refresh-token",
      onboardingCompleted: false
    )
    try sessionStore.establishSession(credentials: replacementCredentials)
    let remoteDataSource = TokenRefreshRemoteDataSource(
      result: .success(makeReissueResponse())
    )
    let coordinator = TokenRefreshCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: sessionStore
    )

    do {
      _ = try await coordinator.refreshAccessToken(
        afterUnauthorized: "access-token"
      )
      XCTFail("Expected unrelated session rejection.")
    } catch let error as TokenRefreshCoordinatorError {
      XCTAssertEqual(error, .sessionUnavailable)
    } catch {
      XCTFail("Expected TokenRefreshCoordinatorError, got \(error)")
    }

    XCTAssertEqual(remoteDataSource.reissueCount, 0)
    XCTAssertEqual(credentialStore.credentials, replacementCredentials)
    XCTAssertEqual(tokenProvider.accessToken, "new-account-token")
  }

  func testPublicAndReissue401ResponsesNeverStartRefresh() async {
    let refresher = TokenRefreshCountingRefresher(
      result: .success("unused-token")
    )
    let responseScript = UnauthorizedThenSuccessScript(
      unauthorizedRequestCount: .max
    )
    let client = makeClient(
      tokenProvider: MemoryAccessTokenProvider(),
      accessTokenRefresher: refresher,
      responseScript: responseScript
    )

    await assertUnauthorized {
      _ = try await client.requestData(HealthTarget.status)
    }
    await assertUnauthorized {
      _ = try await client.requestData(
        AuthTarget.reissue(refreshToken: "refresh-token")
      )
    }

    XCTAssertEqual(refresher.callCount, 0)
    XCTAssertEqual(responseScript.requestCount, 2)
  }

  func testRetriedBearer401IsReturnedWithoutASecondRefresh() async {
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.replace(with: "access-token")
    let refresher = TokenRefreshCountingRefresher(
      result: .success("refreshed-access-token")
    )
    let responseScript = UnauthorizedThenSuccessScript(
      unauthorizedRequestCount: .max
    )
    let client = makeClient(
      tokenProvider: tokenProvider,
      accessTokenRefresher: refresher,
      responseScript: responseScript
    )

    await assertUnauthorized {
      _ = try await client.requestData(TokenRefreshBearerTarget())
    }

    XCTAssertEqual(refresher.callCount, 1)
    XCTAssertEqual(responseScript.requestCount, 2)
  }

  func testBearerMutation5xxIsNotAutomaticallyRetried() async {
    let tokenProvider = MemoryAccessTokenProvider()
    tokenProvider.replace(with: "access-token")
    let refresher = TokenRefreshCountingRefresher(
      result: .success("unused-token")
    )
    let responseScript = TokenRefreshFixedResponseScript(
      statusCode: 503
    )
    let client = DefaultAPIClient(
      tokenProvider: tokenProvider,
      accessTokenRefresher: refresher,
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          responseScript.endpoint(for: target)
        },
        stubBuilder: { _ in .immediate }
      )
    )

    do {
      _ = try await client.requestData(
        TokenRefreshBearerTarget(method: .post)
      )
      XCTFail("Expected server failure.")
    } catch let error as APIError {
      guard case .server(let statusCode, _, _) = error else {
        return XCTFail("Expected server error, got \(error)")
      }
      XCTAssertEqual(statusCode, 503)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }

    XCTAssertEqual(responseScript.requestCount, 1)
    XCTAssertEqual(refresher.callCount, 0)
  }

  func testTimeoutAndServerRefreshFailuresSignOutAndRemoveCredentials() async throws {
    let failures: [APIError] = [
      .transport(
        code: URLError.timedOut.rawValue,
        message: "timed out"
      ),
      .server(
        statusCode: 503,
        code: "COMMON503",
        message: "unavailable"
      ),
    ]

    for failure in failures {
      let context = try makeRefreshContext(result: .failure(failure))

      await assertAPIError(failure) {
        _ = try await context.coordinator.refreshAccessToken(
          afterUnauthorized: "access-token"
        )
      }

      XCTAssertEqual(context.sessionStore.state, .signedOut)
      XCTAssertNil(context.tokenProvider.accessToken)
      XCTAssertNil(context.credentialStore.credentials)
      XCTAssertEqual(context.credentialStore.removeCount, 1)
    }
  }

  func testMalformedRefreshResponseSignsOutWithoutSavingIt() async throws {
    let malformedResponse = TokenReissueResponseDTO(
      accessToken: " ",
      refreshToken: "new-refresh-token",
      tokenType: "Bearer",
      memberId: 7,
      onboardingCompleted: true
    )
    let context = try makeRefreshContext(
      result: .success(malformedResponse)
    )

    do {
      _ = try await context.coordinator.refreshAccessToken(
        afterUnauthorized: "access-token"
      )
      XCTFail("Expected malformed response failure.")
    } catch let error as TokenRefreshCoordinatorError {
      XCTAssertEqual(error, .invalidResponse)
    } catch {
      XCTFail("Expected TokenRefreshCoordinatorError, got \(error)")
    }

    XCTAssertEqual(context.sessionStore.state, .signedOut)
    XCTAssertNil(context.tokenProvider.accessToken)
    XCTAssertNil(context.credentialStore.credentials)
    XCTAssertEqual(context.credentialStore.saveCount, 1)
    XCTAssertEqual(context.credentialStore.removeCount, 1)
  }

  func testCredentialSaveFailureSignsOutWithoutPublishingNewSnapshot() async throws {
    let credentialStore = TokenRefreshCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: makeCredentials())
    credentialStore.saveError = CredentialStoreError.keychain(status: -1)
    let remoteDataSource = TokenRefreshRemoteDataSource(
      result: .success(makeReissueResponse())
    )
    let coordinator = TokenRefreshCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: sessionStore
    )

    do {
      _ = try await coordinator.refreshAccessToken(
        afterUnauthorized: "access-token"
      )
      XCTFail("Expected credential save failure.")
    } catch let error as CredentialStoreError {
      XCTAssertEqual(error, .keychain(status: -1))
    } catch {
      XCTFail("Expected CredentialStoreError, got \(error)")
    }

    XCTAssertEqual(sessionStore.state, .signedOut)
    XCTAssertNil(tokenProvider.accessToken)
    XCTAssertNil(credentialStore.credentials)
    XCTAssertEqual(credentialStore.removeCount, 1)
  }

  func testRefreshFailureDoesNotReplaceANewerAccountSession() async throws {
    let credentialStore = TokenRefreshCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: makeCredentials())
    let gate = TokenRefreshGate()
    let remoteDataSource = TokenRefreshRemoteDataSource(
      result: .failure(APIError.authenticationRequired),
      gate: gate
    )
    let coordinator = TokenRefreshCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: sessionStore
    )
    let refreshTask = _Concurrency.Task {
      try await coordinator.refreshAccessToken(
        afterUnauthorized: "access-token"
      )
    }

    try await waitUntil {
      remoteDataSource.reissueCount == 1
    }
    let replacementCredentials = AccountCredentials(
      memberID: 9,
      accessToken: "new-account-token",
      refreshToken: "new-account-refresh-token",
      onboardingCompleted: false
    )
    try sessionStore.establishSession(credentials: replacementCredentials)
    await gate.open()

    do {
      _ = try await refreshTask.value
      XCTFail("Expected original refresh failure.")
    } catch {}

    XCTAssertEqual(credentialStore.credentials, replacementCredentials)
    XCTAssertEqual(tokenProvider.accessToken, "new-account-token")
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: 9,
          onboardingCompleted: false
        )
      )
    )
    XCTAssertEqual(credentialStore.removeCount, 0)
  }

  private func makeRefreshContext(
    result: Result<TokenReissueResponseDTO, Error>
  ) throws -> TokenRefreshTestContext {
    let credentialStore = TokenRefreshCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    try sessionStore.establishSession(credentials: makeCredentials())
    let remoteDataSource = TokenRefreshRemoteDataSource(result: result)
    let coordinator = TokenRefreshCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: sessionStore
    )

    return TokenRefreshTestContext(
      credentialStore: credentialStore,
      tokenProvider: tokenProvider,
      sessionStore: sessionStore,
      coordinator: coordinator
    )
  }

  private func makeCredentials() -> AccountCredentials {
    AccountCredentials(
      memberID: 7,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      onboardingCompleted: true
    )
  }

  private func makeReissueResponse() -> TokenReissueResponseDTO {
    TokenReissueResponseDTO(
      accessToken: "refreshed-access-token",
      refreshToken: "refreshed-refresh-token",
      tokenType: "Bearer",
      memberId: 7,
      onboardingCompleted: false
    )
  }

  private func makeClient(
    tokenProvider: any AccessTokenProviding,
    accessTokenRefresher: any AccessTokenRefreshing,
    responseScript: UnauthorizedThenSuccessScript,
    requestCapture: TokenRefreshRequestCapturePlugin? = nil
  ) -> DefaultAPIClient {
    let additionalPlugins: [any PluginType & Sendable]

    if let requestCapture {
      additionalPlugins = [requestCapture]
    } else {
      additionalPlugins = []
    }

    return DefaultAPIClient(
      tokenProvider: tokenProvider,
      accessTokenRefresher: accessTokenRefresher,
      providerFactory: MoyaProviderFactory(
        endpointBuilder: { target in
          responseScript.endpoint(for: target)
        },
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )
  }

  private func assertUnauthorized(
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected unauthorized response.")
    } catch let error as APIError {
      guard case .server(let statusCode, _, _) = error else {
        return XCTFail("Expected server error, got \(error)")
      }
      XCTAssertEqual(statusCode, 401)
    } catch {
      XCTFail("Expected APIError, got \(error)")
    }
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

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
      guard clock.now < deadline else {
        return XCTFail("Timed out waiting for token refresh state.")
      }

      try await _Concurrency.Task.sleep(for: .milliseconds(10))
    }
  }
}

nonisolated private struct TokenRefreshBearerTarget: MoruTargetType {
  let path = "/private"
  let method: Moya.Method
  let authenticationRequirement = AuthenticationRequirement.bearer

  init(method: Moya.Method = .get) {
    self.method = method
  }

  var task: Moya.Task {
    .requestPlain
  }
}

nonisolated private struct TokenRefreshTestContext {
  let credentialStore: TokenRefreshCredentialStore
  let tokenProvider: MemoryAccessTokenProvider
  let sessionStore: AccountSessionStore
  let coordinator: TokenRefreshCoordinator
}

nonisolated private final class UnauthorizedThenSuccessScript:
  @unchecked Sendable {
  private let lock = NSLock()
  private let unauthorizedRequestCount: Int
  private var storedRequestCount = 0

  init(unauthorizedRequestCount: Int) {
    self.unauthorizedRequestCount = unauthorizedRequestCount
  }

  var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedRequestCount
  }

  func endpoint(for target: MultiTarget) -> Endpoint {
    let statusCode: Int
    let data: Data

    lock.lock()
    storedRequestCount += 1
    let requestCount = storedRequestCount
    lock.unlock()

    if requestCount <= unauthorizedRequestCount {
      statusCode = 401
      data = Data(
        """
        {
          "isSuccess": false,
          "code": "COMMON401",
          "message": "인증이 필요합니다."
        }
        """.utf8
      )
    } else {
      statusCode = 200
      data = Data("OK".utf8)
    }

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
  }
}

nonisolated private final class TokenRefreshFixedResponseScript:
  @unchecked Sendable {
  private let lock = NSLock()
  private let statusCode: Int
  private var storedRequestCount = 0

  init(statusCode: Int) {
    self.statusCode = statusCode
  }

  var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedRequestCount
  }

  func endpoint(for target: MultiTarget) -> Endpoint {
    lock.lock()
    storedRequestCount += 1
    lock.unlock()

    let responseStatusCode = statusCode
    let endpoint = MoyaProvider<MultiTarget>.defaultEndpointMapping(
      for: target
    )
    let data = Data(
      """
      {
        "isSuccess": false,
        "code": "COMMON\(responseStatusCode)",
        "message": "요청을 처리할 수 없습니다."
      }
      """.utf8
    )

    return Endpoint(
      url: endpoint.url,
      sampleResponseClosure: {
        .networkResponse(responseStatusCode, data)
      },
      method: endpoint.method,
      task: endpoint.task,
      httpHeaderFields: endpoint.httpHeaderFields
    )
  }
}

nonisolated private final class TokenRefreshRequestCapturePlugin:
  PluginType,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedAuthorizationHeaders: [String] = []

  var authorizationHeaders: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storedAuthorizationHeaders
  }

  func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
    if let authorization = request.value(
      forHTTPHeaderField: "Authorization"
    ) {
      lock.lock()
      storedAuthorizationHeaders.append(authorization)
      lock.unlock()
    }

    return request
  }
}

nonisolated private final class TokenRefreshCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCredentials: AccountCredentials?
  private var storedSaveCount = 0
  private var storedRemoveCount = 0
  private var storedSaveError: Error?

  var credentials: AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
  }

  var saveCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedSaveCount
  }

  var removeCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedRemoveCount
  }

  var saveError: Error? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storedSaveError
    }
    set {
      lock.lock()
      storedSaveError = newValue
      lock.unlock()
    }
  }

  func load() throws -> AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.lock()
    defer { lock.unlock() }
    storedSaveCount += 1

    if let storedSaveError {
      throw storedSaveError
    }

    storedCredentials = credentials
  }

  func remove() throws {
    lock.lock()
    storedRemoveCount += 1
    storedCredentials = nil
    lock.unlock()
  }
}

nonisolated private final class TokenRefreshRemoteDataSource:
  AuthRemoteDataSource,
  @unchecked Sendable {
  private let lock = NSLock()
  private let result: Result<TokenReissueResponseDTO, Error>
  private let gate: TokenRefreshGate?
  private var storedReissueCount = 0
  private var storedRefreshTokens: [String] = []

  init(
    result: Result<TokenReissueResponseDTO, Error>,
    gate: TokenRefreshGate? = nil
  ) {
    self.result = result
    self.gate = gate
  }

  var reissueCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedReissueCount
  }

  var refreshTokens: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storedRefreshTokens
  }

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    throw APIError.invalidRequest("Unexpected login request.")
  }

  func reissue(refreshToken: String) async throws -> TokenReissueResponseDTO {
    recordReissue(refreshToken: refreshToken)

    if let gate {
      await gate.wait()
    }

    return try result.get()
  }

  private func recordReissue(refreshToken: String) {
    lock.lock()
    storedReissueCount += 1
    storedRefreshTokens.append(refreshToken)
    lock.unlock()
  }

  func logout(refreshToken: String) async throws {
    throw APIError.invalidRequest("Unexpected logout request.")
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    throw APIError.invalidRequest("Unexpected withdrawal request.")
  }
}

private actor TokenRefreshGate {
  private var isOpen = false
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    guard !isOpen else {
      return
    }

    await withCheckedContinuation {
      continuation = $0
    }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}

nonisolated private final class TokenRefreshCountingRefresher:
  AccessTokenRefreshing,
  @unchecked Sendable {
  private let lock = NSLock()
  private let result: Result<String, Error>
  private var storedCallCount = 0

  init(result: Result<String, Error>) {
    self.result = result
  }

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedCallCount
  }

  func refreshAccessToken(
    afterUnauthorized failedAccessToken: String
  ) async throws -> String {
    recordCall()
    return try result.get()
  }

  private func recordCall() {
    lock.lock()
    storedCallCount += 1
    lock.unlock()
  }
}
