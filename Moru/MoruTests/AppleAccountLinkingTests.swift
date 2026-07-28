//
//  AppleAccountLinkingTests.swift
//  MoruTests
//

import AuthenticationServices
import Foundation
import XCTest
@testable import Moru

final class AppleAccountLinkingTests: XCTestCase {
  func testAuthorizationCallbackRequiresBothUTF8Credentials() {
    XCTAssertEqual(
      AppleAuthorizationAdapter().outcome(
        identityToken: Data(" identity-token ".utf8),
        authorizationCode: Data(" authorization-code ".utf8)
      ),
      .authorized(
        SocialAuthorization(
          provider: .apple,
          token: "identity-token",
          authorizationCode: "authorization-code"
        )
      )
    )
    XCTAssertEqual(
      AppleAuthorizationAdapter().outcome(
        identityToken: Data(),
        authorizationCode: Data("authorization-code".utf8)
      ),
      .failed
    )
    XCTAssertEqual(
      AppleAuthorizationAdapter().outcome(
        identityToken: Data([0xFF]),
        authorizationCode: Data("authorization-code".utf8)
      ),
      .failed
    )
    XCTAssertEqual(
      AppleAuthorizationAdapter().outcome(
        identityToken: Data("identity-token".utf8),
        authorizationCode: nil
      ),
      .failed
    )
  }

  func testAuthorizationCancellationIsNotMappedToFailure() {
    let cancellation = NSError(
      domain: ASAuthorizationError.errorDomain,
      code: ASAuthorizationError.canceled.rawValue
    )
    let unknownFailure = NSError(
      domain: ASAuthorizationError.errorDomain,
      code: ASAuthorizationError.failed.rawValue
    )

    XCTAssertEqual(
      AppleAuthorizationAdapter().outcome(for: .failure(cancellation)),
      .cancelled
    )
    XCTAssertEqual(
      AppleAuthorizationAdapter().outcome(for: .failure(unknownFailure)),
      .failed
    )
  }

  @MainActor
  func testAppleLinkPassesBothCredentialsAndStoresSuccessfulSessionOnly() async throws {
    let remoteDataSource = AppleLinkingAuthRemoteDataSourceStub()
    let credentialStore = AppleLinkingCredentialStore()
    let tokenProvider = MemoryAccessTokenProvider()
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: tokenProvider
    )
    let service = SocialLoginCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: accountSessionStore
    )

    try await service.login(
      with: SocialAuthorization(
        provider: .apple,
        token: "identity-token",
        authorizationCode: "authorization-code"
      )
    )

    let loginRequests = await remoteDataSource.loginRequests
    XCTAssertEqual(loginRequests.count, 1)
    XCTAssertEqual(loginRequests.first?.provider, .apple)
    XCTAssertEqual(
      loginRequests.first?.request,
      SocialLoginRequestDTO(
        token: "identity-token",
        authorizationCode: "authorization-code"
      )
    )
    XCTAssertEqual(
      credentialStore.credentials,
      AccountCredentials(
        memberID: 90,
        accessToken: "access-token",
        refreshToken: "refresh-token",
        onboardingCompleted: true,
        provider: .apple
      )
    )
    XCTAssertEqual(tokenProvider.accessToken, "access-token")
    XCTAssertEqual(
      accountSessionStore.state,
      .signedIn(SignedInAccount(memberID: 90, onboardingCompleted: true))
    )
    let nonLoginCallCount = await remoteDataSource.totalNonLoginCallCount
    XCTAssertEqual(nonLoginCallCount, 0)
  }

  @MainActor
  func testRemoteFailureLeavesAccountSignedOutAndLocalProfileUsable() async {
    let remoteDataSource = AppleLinkingAuthRemoteDataSourceStub(
      loginError: APIError.transport(code: -1009, message: "offline")
    )
    let credentialStore = AppleLinkingCredentialStore()
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    let service = SocialLoginCoordinator(
      authRemoteDataSource: remoteDataSource,
      accountSessionStore: accountSessionStore
    )
    let viewModel = makeViewModel(linkingService: service)
    viewModel.loadProfileSettings()

    await viewModel.appleAuthorizationDidComplete(
      .authorized(
        SocialAuthorization(
          provider: .apple,
          token: "identity-token",
          authorizationCode: "authorization-code"
        )
      )
    )

    XCTAssertEqual(accountSessionStore.state, .signedOut)
    XCTAssertNil(credentialStore.credentials)
    XCTAssertFalse(viewModel.isAccountLinkInProgress)
    XCTAssertEqual(
      viewModel.accountErrorMessage,
      "Apple 계정을 연결하지 못했어요. "
        + "로컬 데이터는 그대로 사용할 수 있어요."
    )
    guard case .content(let content) = viewModel.state else {
      return XCTFail("Account failure must not replace the local Profile state.")
    }
    XCTAssertEqual(content.profile.displayName, "로컬 사용자")
  }

  @MainActor
  func testCancellationDoesNotCallRemoteOrPublishError() async {
    let linkingService = SocialLoginCoordinatorSpy()
    let viewModel = makeViewModel(linkingService: linkingService)

    await viewModel.appleAuthorizationDidComplete(.cancelled)

    XCTAssertEqual(linkingService.callCount, 0)
    XCTAssertNil(viewModel.accountErrorMessage)
    XCTAssertFalse(viewModel.isAccountLinkInProgress)
  }

  @MainActor
  func testInvalidAuthorizationDoesNotCallRemoteAndKeepsRetryAvailable() async {
    let linkingService = SocialLoginCoordinatorSpy()
    let viewModel = makeViewModel(linkingService: linkingService)

    await viewModel.appleAuthorizationDidComplete(.failed)

    XCTAssertEqual(linkingService.callCount, 0)
    XCTAssertFalse(viewModel.isAccountLinkInProgress)
    XCTAssertEqual(
      viewModel.accountErrorMessage,
      "Apple 인증 정보를 확인하지 못했어요. "
        + "로컬 데이터는 그대로 사용할 수 있어요."
    )
  }

  @MainActor
  func testAccountAccessibilityIdentifierContractsAreStableAndUnique() {
    let identifiers = [
      ProfileView.accountCardAccessibilityIdentifier,
      ProfileView.accountConnectAccessibilityIdentifier,
      ProfileView.appleSignInAccessibilityIdentifier,
      ProfileView.accountLogoutAccessibilityIdentifier,
      ProfileView.accountWithdrawalAccessibilityIdentifier,
    ]

    XCTAssertEqual(Set(identifiers).count, identifiers.count)
    XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("profile.account.") })
  }

  @MainActor
  private func makeViewModel(
    linkingService: any SocialLoginCoordinating
  ) -> ProfileViewModel {
    ProfileViewModel(
      profileSettingsUseCase: AppleLinkingProfileSettingsUseCase(),
      voicePreviewPlayer: AppleLinkingVoicePreviewPlayer(),
      alarmService: UnavailableProfileAlarmService(),
      socialLoginCoordinator: linkingService,
      resetUseCase: nil,
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
  }
}

private struct AppleLoginRequest: Equatable, Sendable {
  let provider: AuthProvider
  let request: SocialLoginRequestDTO
}

private actor AppleLinkingAuthRemoteDataSourceStub: AuthRemoteDataSource {
  private let loginError: Error?
  private(set) var loginRequests: [AppleLoginRequest] = []
  private(set) var totalNonLoginCallCount = 0

  init(loginError: Error? = nil) {
    self.loginError = loginError
  }

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    loginRequests.append(AppleLoginRequest(provider: provider, request: request))

    if let loginError {
      throw loginError
    }

    return LoginResponseDTO(
      memberId: 90,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      isNewMember: true,
      onboardingCompleted: true
    )
  }

  func reissue(refreshToken: String) async throws -> TokenReissueResponseDTO {
    totalNonLoginCallCount += 1
    throw SocialLoginError.unavailable
  }

  func logout(refreshToken: String) async throws {
    totalNonLoginCallCount += 1
    throw SocialLoginError.unavailable
  }

  func withdraw() async throws -> WithdrawalResponseDTO {
    totalNonLoginCallCount += 1
    throw SocialLoginError.unavailable
  }
}

nonisolated private final class AppleLinkingCredentialStore:
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
private final class SocialLoginCoordinatorSpy: SocialLoginCoordinating {
  private(set) var callCount = 0

  func login(with authorization: SocialAuthorization) async throws {
    callCount += 1
  }
}

@MainActor
private final class AppleLinkingProfileSettingsUseCase:
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
private final class AppleLinkingVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}
