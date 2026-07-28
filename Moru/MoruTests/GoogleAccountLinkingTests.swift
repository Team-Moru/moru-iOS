//
//  GoogleAccountLinkingTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

final class GoogleAccountLinkingTests: XCTestCase {
  func testConfigurationRequiresMatchingPublicOAuthValues() {
    let validConfiguration = GoogleSignInPublicConfiguration(
      clientID: "ios-client.apps.googleusercontent.com",
      serverClientID: "server-client.apps.googleusercontent.com",
      reversedClientID: "com.googleusercontent.apps.ios-client"
    )

    XCTAssertEqual(
      validConfiguration,
      GoogleSignInPublicConfiguration(
        clientID: " ios-client.apps.googleusercontent.com ",
        serverClientID: " server-client.apps.googleusercontent.com ",
        reversedClientID: " com.googleusercontent.apps.ios-client "
      )
    )
    XCTAssertNil(
      GoogleSignInPublicConfiguration(
        clientID: "ios-client.apps.googleusercontent.com",
        serverClientID: nil,
        reversedClientID: "com.googleusercontent.apps.ios-client"
      )
    )
    XCTAssertNil(
      GoogleSignInPublicConfiguration(
        clientID: "ios-client.apps.googleusercontent.com",
        serverClientID: "server-client.apps.googleusercontent.com",
        reversedClientID: "com.googleusercontent.apps.other-client"
      )
    )
  }

  func testRepositoryPlaceholdersKeepGoogleLoginUnavailable() {
    let configuration = SocialLoginPublicConfiguration(
      googleClientID: SocialLoginPublicConfiguration.googleClientIDPlaceholder,
      googleServerClientID:
        SocialLoginPublicConfiguration.googleServerClientIDPlaceholder,
      googleReversedClientID:
        SocialLoginPublicConfiguration.googleReversedClientIDPlaceholder
    )

    XCTAssertNil(configuration.googleClientID)
    XCTAssertNil(configuration.googleServerClientID)
    XCTAssertNil(configuration.googleReversedClientID)
    XCTAssertNil(configuration.googleSignInConfiguration)
  }

  func testRefreshedIDTokenCreatesGoogleAuthorizationWithoutExtraPayload() {
    XCTAssertEqual(
      GoogleAuthorizationAdapter().outcome(idToken: " refreshed-id-token "),
      .authorized(
        SocialAuthorization(
          provider: .google,
          token: "refreshed-id-token"
        )
      )
    )
    XCTAssertEqual(
      GoogleAuthorizationAdapter().outcome(idToken: " "),
      .failed
    )
  }

  func testCancellationIsNotReportedAsFailure() {
    let cancellation = NSError(
      domain: GoogleAuthorizationAdapter.cancellationErrorDomain,
      code: GoogleAuthorizationAdapter.cancellationErrorCode
    )
    let otherError = NSError(
      domain: GoogleAuthorizationAdapter.cancellationErrorDomain,
      code: -1
    )

    XCTAssertEqual(
      GoogleAuthorizationAdapter().outcome(error: cancellation),
      .cancelled
    )
    XCTAssertEqual(
      GoogleAuthorizationAdapter().outcome(error: otherError),
      .failed
    )
  }

  @MainActor
  func testCancellationSkipsMORUServerAndUserFacingError() async {
    let coordinator = GoogleSocialLoginCoordinatorSpy()
    let viewModel = makeViewModel(coordinator: coordinator)

    await viewModel.googleAuthorizationDidComplete(.cancelled)

    XCTAssertEqual(coordinator.authorizations, [])
    XCTAssertNil(viewModel.accountErrorMessage)
    XCTAssertFalse(viewModel.isAccountLinkInProgress)
  }

  @MainActor
  func testGoogleAuthorizationSendsOnlyIDTokenToMORUServer() async throws {
    let remote = GoogleAuthRemoteDataSource()
    let credentialStore = GoogleCredentialStore()
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: remote,
      accountSessionStore: AccountSessionStore(
        credentialStore: credentialStore,
        accessTokenProvider: MemoryAccessTokenProvider()
      )
    )

    try await coordinator.login(
      with: SocialAuthorization(
        provider: .google,
        token: "refreshed-id-token"
      )
    )

    let requests = await remote.requests
    XCTAssertEqual(
      requests,
      [
        GoogleLoginRequest(
          provider: .google,
          request: SocialLoginRequestDTO(
            token: "refreshed-id-token",
            authorizationCode: nil
          )
        ),
      ]
    )
    XCTAssertEqual(credentialStore.credentials?.provider, .google)
  }

  @MainActor
  private func makeViewModel(
    coordinator: any SocialLoginCoordinating
  ) -> ProfileViewModel {
    ProfileViewModel(
      profileSettingsUseCase: GoogleProfileSettingsUseCase(),
      voicePreviewPlayer: GoogleVoicePreviewPlayer(),
      alarmService: UnavailableProfileAlarmService(),
      socialLoginCoordinator: coordinator,
      resetUseCase: nil,
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
  }
}

nonisolated private struct GoogleLoginRequest: Equatable, Sendable {
  let provider: AuthProvider
  let request: SocialLoginRequestDTO
}

private actor GoogleAuthRemoteDataSource: AuthRemoteDataSource {
  private(set) var requests: [GoogleLoginRequest] = []

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    requests.append(GoogleLoginRequest(provider: provider, request: request))
    return LoginResponseDTO(
      memberId: 105,
      accessToken: "access-token",
      refreshToken: "refresh-token",
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

nonisolated private final class GoogleCredentialStore:
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
private final class GoogleSocialLoginCoordinatorSpy: SocialLoginCoordinating {
  private(set) var authorizations: [SocialAuthorization] = []

  func login(with authorization: SocialAuthorization) async throws {
    authorizations.append(authorization)
  }
}

@MainActor
private final class GoogleProfileSettingsUseCase:
  ProfileSettingsUseCaseProtocol {
  private let result = ProfileSettingsLoadResult(
    profile: LocalProfile(displayName: "로컬 사용자"),
    fallbackNotice: nil
  )

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    result
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult {
    result
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

@MainActor
private final class GoogleVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}
