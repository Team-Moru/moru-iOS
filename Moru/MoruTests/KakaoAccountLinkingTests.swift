//
//  KakaoAccountLinkingTests.swift
//  MoruTests
//

import Foundation
import XCTest

import KakaoSDKCommon
@testable import Moru

final class KakaoAccountLinkingTests: XCTestCase {
  private let nativeAppKey = "0123456789abcdef0123456789abcdef"

  func testPublicConfigurationRequiresValidNativeKeyAndMatchingScheme() {
    XCTAssertNotNil(
      KakaoSignInPublicConfiguration(
        nativeAppKey: nativeAppKey,
        urlScheme: "kakao\(nativeAppKey)"
      )
    )
    XCTAssertNil(
      KakaoSignInPublicConfiguration(
        nativeAppKey: "not-a-native-key",
        urlScheme: "kakaonot-a-native-key"
      )
    )
    XCTAssertNil(
      KakaoSignInPublicConfiguration(
        nativeAppKey: nativeAppKey,
        urlScheme: "kakaomismatched"
      )
    )
  }

  func testRepositoryPlaceholdersKeepKakaoLoginUnavailable() {
    let configuration = SocialLoginPublicConfiguration(
      kakaoNativeAppKey:
        SocialLoginPublicConfiguration.kakaoNativeAppKeyPlaceholder,
      kakaoURLScheme:
        SocialLoginPublicConfiguration.kakaoURLSchemePlaceholder
    )

    XCTAssertNil(configuration.kakaoNativeAppKey)
    XCTAssertNil(configuration.kakaoURLScheme)
    XCTAssertNil(configuration.kakaoSignInConfiguration)
  }

  func testAccessTokenCreatesKakaoAuthorizationWithoutExtraPayload() {
    XCTAssertEqual(
      KakaoAuthorizationAdapter().outcome(accessToken: " access-token "),
      .authorized(
        SocialAuthorization(
          provider: .kakao,
          token: "access-token"
        )
      )
    )
    XCTAssertEqual(
      KakaoAuthorizationAdapter().outcome(accessToken: " "),
      .failed
    )
  }

  func testKakaoCancellationIsNotReportedAsFailure() {
    XCTAssertEqual(
      KakaoAuthorizationAdapter().outcome(
        error: SdkError(reason: .Cancelled)
      ),
      .cancelled
    )
    XCTAssertEqual(
      KakaoAuthorizationAdapter().outcome(
        error: SdkError(reason: .Unknown)
      ),
      .failed
    )
  }

  @MainActor
  func testTalkInstalledUsesTalkLoginOnly() async {
    let client = KakaoUserAPIClientSpy(
      isKakaoTalkLoginAvailable: true,
      talkResult: .success("talk-access-token")
    )
    let session = makeSession(client: client)

    let outcome = await session.authorize()

    XCTAssertEqual(
      outcome,
      .authorized(
        SocialAuthorization(
          provider: .kakao,
          token: "talk-access-token"
        )
      )
    )
    XCTAssertEqual(client.talkLoginCallCount, 1)
    XCTAssertEqual(client.accountLoginCallCount, 0)
  }

  @MainActor
  func testTalkMissingUsesAccountLoginOnly() async {
    let client = KakaoUserAPIClientSpy(
      isKakaoTalkLoginAvailable: false,
      accountResult: .success("account-access-token")
    )
    let session = makeSession(client: client)

    let outcome = await session.authorize()

    XCTAssertEqual(
      outcome,
      .authorized(
        SocialAuthorization(
          provider: .kakao,
          token: "account-access-token"
        )
      )
    )
    XCTAssertEqual(client.talkLoginCallCount, 0)
    XCTAssertEqual(client.accountLoginCallCount, 1)
  }

  @MainActor
  func testTalkCancellationNeverFallsBackToAccountLogin() async {
    let client = KakaoUserAPIClientSpy(
      isKakaoTalkLoginAvailable: true,
      talkResult: .failure(SdkError(reason: .Cancelled))
    )
    let session = makeSession(client: client)

    let outcome = await session.authorize()

    XCTAssertEqual(outcome, .cancelled)
    XCTAssertEqual(client.talkLoginCallCount, 1)
    XCTAssertEqual(client.accountLoginCallCount, 0)
  }

  @MainActor
  func testKakaoAuthorizationSendsOnlyAccessTokenToMORUServer() async throws {
    let remote = KakaoAuthRemoteDataSource()
    let credentialStore = KakaoCredentialStore()
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: remote,
      accountSessionStore: AccountSessionStore(
        credentialStore: credentialStore,
        accessTokenProvider: MemoryAccessTokenProvider(),
        restorationGuard: InMemoryAccountSessionRestorationGuard()
      )
    )

    try await coordinator.login(
      with: SocialAuthorization(
        provider: .kakao,
        token: "kakao-access-token"
      )
    )

    let requests = await remote.requests
    XCTAssertEqual(
      requests,
      [
        KakaoLoginRequest(
          provider: .kakao,
          request: SocialLoginRequestDTO(
            token: "kakao-access-token",
            authorizationCode: nil
          )
        ),
      ]
    )
    XCTAssertEqual(credentialStore.credentials?.provider, .kakao)
  }

  @MainActor
  func testLogoutAndWithdrawalUseDistinctKakaoSDKBoundaries() async throws {
    let client = KakaoUserAPIClientSpy(isKakaoTalkLoginAvailable: true)
    let session = makeSession(client: client)

    try await session.signOut(provider: .kakao, reason: .logout)
    try await session.signOut(provider: .kakao, reason: .withdrawal)

    XCTAssertEqual(client.logoutCallCount, 1)
    XCTAssertEqual(client.unlinkCallCount, 1)
  }

  @MainActor
  private func makeSession(
    client: KakaoUserAPIClientSpy
  ) -> KakaoSignInSession {
    KakaoSignInSession(
      configuration: SocialLoginPublicConfiguration(
        kakaoNativeAppKey: nativeAppKey,
        kakaoURLScheme: "kakao\(nativeAppKey)"
      ),
      userAPIClient: client,
      initializeSDK: { _ in }
    )
  }
}

nonisolated private struct KakaoLoginRequest: Equatable, Sendable {
  let provider: AuthProvider
  let request: SocialLoginRequestDTO
}

private actor KakaoAuthRemoteDataSource: AuthRemoteDataSource {
  private(set) var requests: [KakaoLoginRequest] = []

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    requests.append(KakaoLoginRequest(provider: provider, request: request))
    return LoginResponseDTO(
      memberId: 107,
      accessToken: "moru-access-token",
      refreshToken: "moru-refresh-token",
      isNewMember: false,
      onboardingCompleted: true
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

nonisolated private final class KakaoCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private let lock = NSLock()
  private var storedCredentials: AccountCredentials?

  var credentials: AccountCredentials? {
    lock.withLock {
      storedCredentials
    }
  }

  func load() throws -> AccountCredentials? {
    credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    lock.withLock {
      storedCredentials = credentials
    }
  }

  func remove() throws {
    lock.withLock {
      storedCredentials = nil
    }
  }
}

@MainActor
private final class KakaoUserAPIClientSpy: KakaoUserAPIClient {
  let isKakaoTalkLoginAvailable: Bool
  private let talkResult: Result<String, Error>
  private let accountResult: Result<String, Error>
  private(set) var talkLoginCallCount = 0
  private(set) var accountLoginCallCount = 0
  private(set) var logoutCallCount = 0
  private(set) var unlinkCallCount = 0

  init(
    isKakaoTalkLoginAvailable: Bool,
    talkResult: Result<String, Error> = .success("talk-token"),
    accountResult: Result<String, Error> = .success("account-token")
  ) {
    self.isKakaoTalkLoginAvailable = isKakaoTalkLoginAvailable
    self.talkResult = talkResult
    self.accountResult = accountResult
  }

  func loginWithKakaoTalk(
    completion: @escaping (String?, Error?) -> Void
  ) {
    talkLoginCallCount += 1
    complete(talkResult, with: completion)
  }

  func loginWithKakaoAccount(
    completion: @escaping (String?, Error?) -> Void
  ) {
    accountLoginCallCount += 1
    complete(accountResult, with: completion)
  }

  func logout(completion: @escaping (Error?) -> Void) {
    logoutCallCount += 1
    completion(nil)
  }

  func unlink(completion: @escaping (Error?) -> Void) {
    unlinkCallCount += 1
    completion(nil)
  }

  private func complete(
    _ result: Result<String, Error>,
    with completion: @escaping (String?, Error?) -> Void
  ) {
    switch result {
    case .success(let token):
      completion(token, nil)
    case .failure(let error):
      completion(nil, error)
    }
  }
}
