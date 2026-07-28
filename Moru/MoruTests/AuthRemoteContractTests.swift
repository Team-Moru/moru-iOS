//
//  AuthRemoteContractTests.swift
//  MoruTests
//

import XCTest

import Moya

@testable import Moru

@MainActor
final class AuthRemoteContractTests: XCTestCase {
  func testProviderDecodesKnownValuesCaseInsensitively() throws {
    let decoder = JSONDecoder()

    XCTAssertEqual(
      try decoder.decode(AuthProvider.self, from: Data(#""apple""#.utf8)),
      .apple
    )
    XCTAssertEqual(
      try decoder.decode(AuthProvider.self, from: Data(#""GOOGLE""#.utf8)),
      .google
    )
    XCTAssertEqual(
      try decoder.decode(AuthProvider.self, from: Data(#""Kakao""#.utf8)),
      .kakao
    )
  }

  func testProviderPreservesUnknownServerValue() throws {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    let provider = try decoder.decode(
      AuthProvider.self,
      from: Data(#""naver-v2""#.utf8)
    )

    XCTAssertEqual(provider, .unknown("naver-v2"))
    XCTAssertEqual(provider.serverValue, "naver-v2")
    XCTAssertEqual(
      String(data: try encoder.encode(provider), encoding: .utf8),
      #""naver-v2""#
    )
  }

  func testTargetPathsMethodsAndAuthenticationBoundaries() {
    let loginRequest = SocialLoginRequestDTO(
      token: "social-token",
      authorizationCode: nil
    )
    let login = AuthTarget.login(provider: .apple, request: loginRequest)
    let reissue = AuthTarget.reissue(refreshToken: "refresh-token")
    let logout = AuthTarget.logout(
      request: LogoutRequestDTO(refreshToken: "refresh-token")
    )

    XCTAssertEqual(login.path, "/auth/login/apple")
    XCTAssertEqual(login.method, .post)
    XCTAssertEqual(login.authenticationRequirement, .none)
    XCTAssertEqual(
      AuthTarget.login(provider: .google, request: loginRequest).path,
      "/auth/login/google"
    )
    XCTAssertEqual(
      AuthTarget.login(provider: .kakao, request: loginRequest).path,
      "/auth/login/kakao"
    )
    XCTAssertEqual(reissue.path, "/auth/reissue")
    XCTAssertEqual(reissue.method, .post)
    XCTAssertEqual(reissue.authenticationRequirement, .none)
    XCTAssertEqual(logout.path, "/auth/logout")
    XCTAssertEqual(logout.method, .post)
    XCTAssertEqual(logout.authenticationRequirement, .bearer)
    XCTAssertEqual(AuthTarget.withdrawal.path, "/auth/withdrawal")
    XCTAssertEqual(AuthTarget.withdrawal.method, .delete)
    XCTAssertEqual(AuthTarget.withdrawal.authenticationRequirement, .bearer)
  }

  func testLoginEncodesAppleContractWithoutAuthorizationHeader() async throws {
    let requestCapture = AuthRequestCapturePlugin()
    let client = makeClient(
      data: loginResponseData(),
      tokenProvider: AuthStubAccessTokenProvider(accessToken: "unused-access-token"),
      additionalPlugins: [requestCapture]
    )
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    let response = try await dataSource.login(
      provider: .apple,
      request: SocialLoginRequestDTO(
        token: "apple-identity-token",
        authorizationCode: "apple-authorization-code"
      )
    )

    XCTAssertEqual(response.memberId, 1)
    XCTAssertEqual(response.accessToken, "access-token")
    XCTAssertEqual(response.refreshToken, "refresh-token")
    XCTAssertEqual(response.isNewMember, true)
    XCTAssertEqual(response.onboardingCompleted, false)

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertEqual(request.url?.path, "/auth/login/apple")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"),
      "application/json"
    )

    let body = try jsonBody(from: request)
    XCTAssertEqual(body["token"] as? String, "apple-identity-token")
    XCTAssertEqual(
      body["authorizationCode"] as? String,
      "apple-authorization-code"
    )
  }

  func testLoginResponseAllowsMissingIsNewMember() async throws {
    let data = Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "memberId": 7,
          "accessToken": "access-token",
          "refreshToken": "refresh-token",
          "onboardingCompleted": true
        }
      }
      """.utf8
    )
    let dataSource = DefaultAuthRemoteDataSource(
      apiClient: makeClient(data: data)
    )

    let response = try await dataSource.login(
      provider: .kakao,
      request: SocialLoginRequestDTO(
        token: "kakao-access-token",
        authorizationCode: nil
      )
    )

    XCTAssertEqual(response.memberId, 7)
    XCTAssertNil(response.isNewMember)
    XCTAssertTrue(response.onboardingCompleted)
  }

  func testReissueUsesRefreshHeaderWithoutBearerOrBody() async throws {
    let requestCapture = AuthRequestCapturePlugin()
    let client = makeClient(
      data: reissueResponseData(),
      tokenProvider: AuthStubAccessTokenProvider(accessToken: "unused-access-token"),
      additionalPlugins: [requestCapture]
    )
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    let response = try await dataSource.reissue(
      refreshToken: "exact-refresh-token"
    )

    XCTAssertEqual(response.accessToken, "new-access-token")
    XCTAssertEqual(response.refreshToken, "new-refresh-token")
    XCTAssertEqual(response.tokenType, "Bearer")
    XCTAssertEqual(response.memberId, 1)
    XCTAssertFalse(response.onboardingCompleted)

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertEqual(request.url?.path, "/auth/reissue")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "X-Refresh-Token"),
      "exact-refresh-token"
    )
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(request.httpBody)
  }

  func testLogoutUsesBearerAndRefreshTokenJSONBody() async throws {
    let requestCapture = AuthRequestCapturePlugin()
    let client = makeClient(
      data: voidResponseData(),
      tokenProvider: AuthStubAccessTokenProvider(accessToken: "access-token"),
      additionalPlugins: [requestCapture]
    )
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    try await dataSource.logout(refreshToken: "refresh-token")

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertEqual(request.url?.path, "/auth/logout")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
    XCTAssertEqual(
      try jsonBody(from: request)["refreshToken"] as? String,
      "refresh-token"
    )
  }

  func testWithdrawalUsesBearerAndReturnsServerMessage() async throws {
    let requestCapture = AuthRequestCapturePlugin()
    let client = makeClient(
      data: withdrawalResponseData(),
      tokenProvider: AuthStubAccessTokenProvider(accessToken: "access-token"),
      additionalPlugins: [requestCapture]
    )
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    let response = try await dataSource.withdraw()

    XCTAssertEqual(response.message, "회원 탈퇴가 완료되었습니다.")

    let request = try XCTUnwrap(requestCapture.request)
    XCTAssertEqual(request.url?.path, "/auth/withdrawal")
    XCTAssertEqual(request.httpMethod, "DELETE")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer access-token"
    )
    XCTAssertNil(request.httpBody)
  }

  func testUnsupportedProviderFailsBeforeTransport() async {
    let client = NeverCalledAuthAPIClient()
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    await assertAuthError(.unsupportedProvider("future-provider")) {
      _ = try await dataSource.login(
        provider: .unknown("future-provider"),
        request: SocialLoginRequestDTO(
          token: "social-token",
          authorizationCode: nil
        )
      )
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testBlankSocialTokenFailsBeforeTransport() async {
    let client = NeverCalledAuthAPIClient()
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    await assertAuthError(.invalidSocialToken) {
      _ = try await dataSource.login(
        provider: .google,
        request: SocialLoginRequestDTO(
          token: " \n ",
          authorizationCode: nil
        )
      )
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testBlankRefreshTokenFailsBeforeReissueOrLogoutTransport() async {
    let client = NeverCalledAuthAPIClient()
    let dataSource = DefaultAuthRemoteDataSource(apiClient: client)

    await assertAuthError(.invalidRefreshToken) {
      _ = try await dataSource.reissue(refreshToken: "\t")
    }
    await assertAuthError(.invalidRefreshToken) {
      try await dataSource.logout(refreshToken: "")
    }

    XCTAssertEqual(client.callCount, 0)
  }

  func testServerErrorPassesThroughWithoutAuthSpecificRemapping() async {
    let errorData = Data(
      """
      {
        "isSuccess": false,
        "code": "AUTH4004",
        "message": "유효하지 않은 토큰입니다."
      }
      """.utf8
    )
    let dataSource = DefaultAuthRemoteDataSource(
      apiClient: makeClient(statusCode: 401, data: errorData)
    )

    await assertAPIError(
      .server(
        statusCode: 401,
        code: "AUTH4004",
        message: "유효하지 않은 토큰입니다."
      )
    ) {
      _ = try await dataSource.login(
        provider: .apple,
        request: SocialLoginRequestDTO(
          token: "invalid-token",
          authorizationCode: nil
        )
      )
    }
  }

  func testAuthSampleDataIsDeterministicAndExcludesCallerSecrets() {
    let login = AuthTarget.login(
      provider: .apple,
      request: SocialLoginRequestDTO(
        token: "caller-social-secret",
        authorizationCode: "caller-code-secret"
      )
    )
    let reissue = AuthTarget.reissue(refreshToken: "caller-refresh-secret")

    XCTAssertEqual(login.sampleData, login.sampleData)
    XCTAssertEqual(reissue.sampleData, reissue.sampleData)

    let samples = [
      String(data: login.sampleData, encoding: .utf8),
      String(data: reissue.sampleData, encoding: .utf8)
    ]
    let sampleText = samples.compactMap(\.self).joined()
    XCTAssertFalse(sampleText.contains("caller-social-secret"))
    XCTAssertFalse(sampleText.contains("caller-code-secret"))
    XCTAssertFalse(sampleText.contains("caller-refresh-secret"))
  }

  func testAuthNetworkLogExcludesHeadersAndBodies() {
    let target = MoyaTargetAdapter(
      target: AuthTarget.reissue(refreshToken: "refresh-secret"),
      baseURL: NetworkConfiguration.production.baseURL,
      requestAccessToken: nil
    )
    let message = NetworkLogPlugin.requestMessage(for: target)

    XCTAssertEqual(message, "➡️ POST /auth/reissue")
    XCTAssertFalse(message.contains("refresh-secret"))
  }

  private func assertAuthError(
    _ expected: AuthRemoteDataSourceError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected)")
    } catch let error as AuthRemoteDataSourceError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected AuthRemoteDataSourceError, got \(error)")
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

  private func jsonBody(from request: URLRequest) throws -> [String: Any] {
    let data = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }

  nonisolated private func makeClient(
    statusCode: Int = 200,
    data: Data,
    tokenProvider: any AccessTokenProviding = EmptyAccessTokenProvider(),
    additionalPlugins: [any PluginType & Sendable] = []
  ) -> DefaultAPIClient {
    DefaultAPIClient(
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
        stubBuilder: { _ in .immediate },
        additionalPlugins: additionalPlugins
      )
    )
  }

  nonisolated private func loginResponseData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "memberId": 1,
          "accessToken": "access-token",
          "refreshToken": "refresh-token",
          "isNewMember": true,
          "onboardingCompleted": false
        }
      }
      """.utf8
    )
  }

  nonisolated private func reissueResponseData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "accessToken": "new-access-token",
          "refreshToken": "new-refresh-token",
          "tokenType": "Bearer",
          "memberId": 1,
          "onboardingCompleted": false
        }
      }
      """.utf8
    )
  }

  nonisolated private func voidResponseData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다."
      }
      """.utf8
    )
  }

  nonisolated private func withdrawalResponseData() -> Data {
    Data(
      """
      {
        "isSuccess": true,
        "code": "COMMON200",
        "message": "성공입니다.",
        "result": {
          "message": "회원 탈퇴가 완료되었습니다."
        }
      }
      """.utf8
    )
  }
}

nonisolated private final class AuthStubAccessTokenProvider:
  AccessTokenProviding
{
  let accessToken: String?

  init(accessToken: String?) {
    self.accessToken = accessToken
  }
}

nonisolated private final class AuthRequestCapturePlugin:
  PluginType,
  @unchecked Sendable
{
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

nonisolated private final class NeverCalledAuthAPIClient:
  APIClient,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var calls = 0

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    recordCall()
    throw APIError.invalidRequest("Unexpected request")
  }

  func requestVoid<Target: MoruTargetType>(_ target: Target) async throws {
    recordCall()
    throw APIError.invalidRequest("Unexpected request")
  }

  func requestData<Target: MoruTargetType>(_ target: Target) async throws -> Data {
    recordCall()
    throw APIError.invalidRequest("Unexpected request")
  }

  private func recordCall() {
    lock.lock()
    calls += 1
    lock.unlock()
  }
}
