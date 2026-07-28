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
  func testRemoteExchangeFailureReportsOnlySafeStatusAndServerCode() async {
    let reporter = RecordingSocialLoginFailureReporter()
    let credentialStore = GoogleCredentialStore()
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: GoogleAuthRemoteDataSource(
        loginError: APIError.server(
          statusCode: 401,
          code: "GOOGLE_AUDIENCE_INVALID",
          message: "must-not-be-logged"
        )
      ),
      accountSessionStore: AccountSessionStore(
        credentialStore: credentialStore,
        accessTokenProvider: MemoryAccessTokenProvider()
      ),
      failureReporter: reporter
    )
    let viewModel = makeViewModel(coordinator: coordinator)

    await viewModel.googleAuthorizationDidComplete(
      .authorized(
        SocialAuthorization(
          provider: .google,
          token: "must-not-be-logged"
        )
      )
    )

    XCTAssertEqual(
      reporter.diagnostics,
      [
        SocialLoginFailureDiagnostic(
          provider: .google,
          stage: .remoteExchange,
          kind: .server(
            statusCode: 401,
            code: "GOOGLE_AUDIENCE_INVALID"
          )
        ),
      ]
    )
    XCTAssertFalse(
      reporter.diagnostics[0].logMessage.contains("must-not-be-logged")
    )
    XCTAssertNil(credentialStore.credentials)
    XCTAssertEqual(
      viewModel.accountErrorMessage,
      "Google 계정을 연결하지 못했어요. "
        + "로컬 데이터는 그대로 사용할 수 있어요."
    )
  }

  @MainActor
  func testRemoteTransportFailureReportsOnlyNumericCode() async {
    let reporter = RecordingSocialLoginFailureReporter()
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: GoogleAuthRemoteDataSource(
        loginError: APIError.transport(
          code: -1009,
          message: "must-not-be-logged"
        )
      ),
      accountSessionStore: AccountSessionStore(
        credentialStore: GoogleCredentialStore(),
        accessTokenProvider: MemoryAccessTokenProvider()
      ),
      failureReporter: reporter
    )

    do {
      try await coordinator.login(
        with: SocialAuthorization(
          provider: .google,
          token: "must-not-be-logged"
        )
      )
      XCTFail("Expected transport failure.")
    } catch {}

    XCTAssertEqual(
      reporter.diagnostics,
      [
        SocialLoginFailureDiagnostic(
          provider: .google,
          stage: .remoteExchange,
          kind: .transport(code: -1009)
        ),
      ]
    )
    XCTAssertFalse(
      reporter.diagnostics[0].logMessage.contains("must-not-be-logged")
    )
  }

  @MainActor
  func testSessionStorageFailureReportsOnlyKeychainStatus() async {
    let reporter = RecordingSocialLoginFailureReporter()
    let credentialStore = GoogleCredentialStore(
      saveError: CredentialStoreError.keychain(status: -25291)
    )
    let coordinator = SocialLoginCoordinator(
      authRemoteDataSource: GoogleAuthRemoteDataSource(),
      accountSessionStore: AccountSessionStore(
        credentialStore: credentialStore,
        accessTokenProvider: MemoryAccessTokenProvider()
      ),
      failureReporter: reporter
    )

    do {
      try await coordinator.login(
        with: SocialAuthorization(
          provider: .google,
          token: "must-not-be-logged"
        )
      )
      XCTFail("Expected credential storage failure.")
    } catch {}

    XCTAssertEqual(
      reporter.diagnostics,
      [
        SocialLoginFailureDiagnostic(
          provider: .google,
          stage: .sessionStorage,
          kind: .keychain(status: -25291)
        ),
      ]
    )
    XCTAssertFalse(
      reporter.diagnostics[0].logMessage.contains("must-not-be-logged")
    )
    XCTAssertNil(credentialStore.credentials)
  }

  func testUnsafeServerCodeIsNotWrittenToDiagnosticMessage() {
    let diagnostic = SocialLoginFailureDiagnostic.make(
      provider: .google,
      stage: .remoteExchange,
      error: APIError.server(
        statusCode: 401,
        code: "unsafe value@example.com",
        message: "must-not-be-logged"
      )
    )

    XCTAssertEqual(
      diagnostic.kind,
      .server(statusCode: 401, code: nil)
    )
    XCTAssertFalse(diagnostic.logMessage.contains("unsafe"))
    XCTAssertFalse(diagnostic.logMessage.contains("example.com"))
    XCTAssertFalse(diagnostic.logMessage.contains("must-not-be-logged"))

    let nonASCII = SocialLoginFailureDiagnostic.make(
      provider: .unknown("must-not-be-logged"),
      stage: .remoteExchange,
      error: APIError.server(
        statusCode: 401,
        code: "민감정보",
        message: "must-not-be-logged"
      )
    )
    XCTAssertEqual(nonASCII.kind, .server(statusCode: 401, code: nil))
    XCTAssertEqual(
      nonASCII.logMessage,
      "provider=unknown stage=remote_exchange "
        + "kind=server status=401 code=none"
    )
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
  private let loginError: Error?
  private(set) var requests: [GoogleLoginRequest] = []

  init(loginError: Error? = nil) {
    self.loginError = loginError
  }

  func login(
    provider: AuthProvider,
    request: SocialLoginRequestDTO
  ) async throws -> LoginResponseDTO {
    requests.append(GoogleLoginRequest(provider: provider, request: request))
    if let loginError {
      throw loginError
    }

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
  private let saveError: Error?
  private var storedCredentials: AccountCredentials?

  init(saveError: Error? = nil) {
    self.saveError = saveError
  }

  var credentials: AccountCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return storedCredentials
  }

  func load() throws -> AccountCredentials? {
    credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    if let saveError {
      throw saveError
    }

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

nonisolated private final class RecordingSocialLoginFailureReporter:
  SocialLoginFailureReporting,
  @unchecked Sendable {
  private let lock = NSLock()
  private var recordedDiagnostics: [SocialLoginFailureDiagnostic] = []

  var diagnostics: [SocialLoginFailureDiagnostic] {
    lock.lock()
    defer { lock.unlock() }
    return recordedDiagnostics
  }

  func report(_ diagnostic: SocialLoginFailureDiagnostic) {
    lock.lock()
    recordedDiagnostics.append(diagnostic)
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
