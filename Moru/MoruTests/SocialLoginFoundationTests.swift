//
//  SocialLoginFoundationTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

final class SocialLoginFoundationTests: XCTestCase {
  func testLegacyCredentialPayloadDefaultsToAppleAndNewPayloadStoresProvider() throws {
    let legacyData = Data(
      """
      {
        "memberID": 7,
        "accessToken": "legacy-access-token",
        "refreshToken": "legacy-refresh-token",
        "onboardingCompleted": true
      }
      """.utf8
    )

    let legacyCredentials = try JSONDecoder().decode(
      AccountCredentials.self,
      from: legacyData
    )
    XCTAssertEqual(legacyCredentials.provider, .apple)
    XCTAssertNil(legacyCredentials.providerUserIdentifier)

    let googleCredentials = AccountCredentials(
      memberID: 8,
      accessToken: "google-access-token",
      refreshToken: "google-refresh-token",
      onboardingCompleted: false,
      provider: .google,
      providerUserIdentifier: "google-user-id"
    )
    let encoded = try JSONEncoder().encode(googleCredentials)
    XCTAssertEqual(
      try JSONDecoder().decode(AccountCredentials.self, from: encoded),
      googleCredentials
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    XCTAssertEqual(object["provider"] as? String, "google")
    XCTAssertEqual(
      object["providerUserIdentifier"] as? String,
      "google-user-id"
    )
  }

  func testSocialAuthorizationDescriptionRedactsProviderPayload() {
    let authorization = SocialAuthorization(
      provider: .kakao,
      token: "kakao-access-token",
      authorizationCode: "private-authorization-code",
      rawNonce: "private-raw-nonce",
      providerUserIdentifier: "private-provider-user-id"
    )
    let values = [
      String(describing: authorization),
      String(reflecting: authorization),
    ]

    XCTAssertTrue(values.allSatisfy { $0.contains("kakao") })
    XCTAssertTrue(values.allSatisfy { $0.contains("<redacted>") })
    XCTAssertTrue(values.allSatisfy { !$0.contains("kakao-access-token") })
    XCTAssertTrue(
      values.allSatisfy { !$0.contains("private-authorization-code") }
    )
    XCTAssertTrue(values.allSatisfy { !$0.contains("private-raw-nonce") })
    XCTAssertTrue(
      values.allSatisfy { !$0.contains("private-provider-user-id") }
    )
  }

  @MainActor
  func testCoordinatorStoresProviderFromCommonAuthorization() async throws {
    let remote = SocialLoginRemoteDataSource()
    let credentialStore = SocialLoginCredentialStore()
    let sessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: remote,
      accountSessionStore: sessionStore
    )
    let authorization = SocialAuthorization(
      provider: .kakao,
      token: "kakao-access-token"
    )

    try await coordinator.login(with: authorization)

    let requests = await remote.requests
    XCTAssertEqual(requests, [SocialLoginRequestCapture(
      provider: .kakao,
      request: SocialLoginRequestDTO(
        token: "kakao-access-token",
        authorizationCode: nil
      )
    )])
    XCTAssertEqual(credentialStore.credentials?.provider, .kakao)
    XCTAssertEqual(
      sessionStore.state,
      .signedIn(
        SignedInAccount(
          memberID: 27,
          onboardingCompleted: false,
          provider: .kakao
        )
      )
    )
  }

  @MainActor
  func testCoordinatorRejectsUnknownProviderBeforeRemoteCall() async {
    let remote = SocialLoginRemoteDataSource()
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: remote,
      accountSessionStore: AccountSessionStore(
        credentialStore: SocialLoginCredentialStore(),
        accessTokenProvider: MemoryAccessTokenProvider()
      )
    )

    do {
      try await coordinator.login(
        with: SocialAuthorization(
          provider: .unknown("future-provider"),
          token: "provider-token"
        )
      )
      XCTFail("Unknown providers must not reach the server.")
    } catch let error as SocialLoginError {
      XCTAssertEqual(error, .unsupportedProvider("future-provider"))
    } catch {
      XCTFail("Expected SocialLoginError, got \(error)")
    }

    let requests = await remote.requests
    XCTAssertEqual(requests, [])
  }

  func testPublicConfigurationNormalizesUnconfiguredBuildValues() {
    let configuration = SocialLoginPublicConfiguration(
      infoDictionary: [
        SocialLoginPublicConfiguration.googleClientIDInfoKey: "",
        SocialLoginPublicConfiguration.googleServerClientIDInfoKey:
          "$(MORU_GOOGLE_SERVER_CLIENT_ID)",
        SocialLoginPublicConfiguration.googleReversedClientIDInfoKey:
          " com.googleusercontent.apps.public ",
        SocialLoginPublicConfiguration.kakaoNativeAppKeyInfoKey: "public-kakao-key",
        SocialLoginPublicConfiguration.kakaoURLSchemeInfoKey:
          "kakaopublic-kakao-key",
        "MoruGoogleClientSecret": "must-not-be-read",
        "MoruKakaoAdminKey": "must-not-be-read",
      ]
    )

    XCTAssertNil(configuration.googleClientID)
    XCTAssertNil(configuration.googleServerClientID)
    XCTAssertEqual(
      configuration.googleReversedClientID,
      "com.googleusercontent.apps.public"
    )
    XCTAssertEqual(configuration.kakaoNativeAppKey, "public-kakao-key")
    XCTAssertEqual(configuration.kakaoURLScheme, "kakaopublic-kakao-key")
  }

  @MainActor
  func testCallbackRouterDispatchesOnlyConfiguredProviderSchemes() throws {
    let configuration = SocialLoginPublicConfiguration(
      googleReversedClientID: "com.googleusercontent.apps.public",
      kakaoNativeAppKey: "0123456789abcdef0123456789abcdef",
      kakaoURLScheme: "kakao0123456789abcdef0123456789abcdef"
    )
    let router = AuthCallbackRouter(configuration: configuration)
    let googleHandler = AuthCallbackHandlerSpy()
    let kakaoHandler = AuthCallbackHandlerSpy()
    router.register(googleHandler, for: .google)
    router.register(kakaoHandler, for: .kakao)

    let googleURL = try XCTUnwrap(
      URL(string: "com.googleusercontent.apps.public:/oauth")
    )
    let kakaoURL = try XCTUnwrap(
      URL(string: "kakao0123456789abcdef0123456789abcdef://oauth")
    )
    let unknownURL = try XCTUnwrap(URL(string: "moru://oauth"))

    XCTAssertTrue(router.route(googleURL))
    XCTAssertTrue(router.route(kakaoURL))
    XCTAssertFalse(router.route(unknownURL))
    XCTAssertEqual(googleHandler.urls, [googleURL])
    XCTAssertEqual(kakaoHandler.urls, [kakaoURL])
  }
}
nonisolated private struct SocialLoginRequestCapture: Equatable, Sendable {
  let provider: AuthProvider
  let request: SocialLoginRequestDTO
}

private actor SocialLoginRemoteDataSource: AuthRemoteDataSource {
  private(set) var requests: [SocialLoginRequestCapture] = []

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    requests.append(
      SocialLoginRequestCapture(provider: provider, request: request)
    )
    return LoginResponseDTO(
      memberId: 27,
      accessToken: "server-access-token",
      refreshToken: "server-refresh-token",
      isNewMember: true,
      onboardingCompleted: false
    )
  }

  func reissue(refreshToken: String) async throws -> TokenReissueResponseDTO {
    throw SocialLoginError.unavailable
  }

  func logout(refreshToken: String) async throws {
    throw SocialLoginError.unavailable
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    throw SocialLoginError.unavailable
  }
}

nonisolated private final class SocialLoginCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCredentials: AccountCredentials?

  var credentials: AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
  }

  func load() throws -> AccountCredentials? {
    credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.lock()
    storedCredentials = credentials
    lock.unlock()
  }

  func remove() throws {
    lock.lock()
    storedCredentials = nil
    lock.unlock()
  }
}

@MainActor
private final class AuthCallbackHandlerSpy: AuthCallbackHandling {
  private(set) var urls: [URL] = []

  func handleAuthCallback(_ url: URL) -> Bool {
    urls.append(url)
    return true
  }
}
