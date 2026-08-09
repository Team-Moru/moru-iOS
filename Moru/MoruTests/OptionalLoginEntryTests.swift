//
//  OptionalLoginEntryTests.swift
//  MoruTests
//
//  Created by Codex on 7/27/26.
//

import Foundation
import XCTest

@testable import Moru

@MainActor
final class OptionalLoginEntryTests: XCTestCase {
  func testLocalProfileAlwaysRoutesToMainAcrossAccountStates() {
    let states: [AccountSessionState] = [
      .signedOut,
      .restoring,
      .signedIn(
        SignedInAccount(
          memberID: 1,
          onboardingCompleted: false,
          provider: .google
        )
      ),
      .failure(.invalidCredentials),
      .failure(.credentialStoreUnavailable),
    ]

    for state in states {
      XCTAssertEqual(
        destination(
          phase: .ready,
          hasLocalProfile: true,
          accountState: state
        ),
        .main
      )
    }
  }

  func testNoLocalProfileRoutingPreservesOptionalLoginContract() {
    XCTAssertEqual(
      destination(accountState: .restoring),
      .splash
    )
    XCTAssertEqual(
      destination(accountState: .signedOut),
      .accountEntry(nil)
    )
    XCTAssertEqual(
      destination(accountState: .failure(.invalidCredentials)),
      .accountEntry(.invalidCredentials)
    )
    XCTAssertEqual(
      destination(accountState: .failure(.credentialStoreUnavailable)),
      .accountEntry(.credentialStoreUnavailable)
    )
    XCTAssertEqual(
      destination(
        accountState: .signedIn(
          SignedInAccount(
            memberID: 2,
            onboardingCompleted: true,
            provider: .kakao
          )
        )
      ),
      .onboarding
    )
    XCTAssertEqual(
      destination(
        accountState: .signedOut,
        didCompleteAccountEntry: true
      ),
      .onboarding
    )
    XCTAssertEqual(
      destination(
        accountState: .signedOut,
        accountFeaturesEnabled: false
      ),
      .onboarding
    )
  }

  func testSplashAndStorageFailureRemainDedicatedBootstrapStates() {
    XCTAssertEqual(
      destination(
        phase: .loading,
        accountState: .signedOut
      ),
      .splash
    )
    XCTAssertEqual(
      destination(
        phase: .failed("local-store-error"),
        accountState: .signedOut
      ),
      .sessionFailure(
        title: "저장소를 열 수 없어요",
        message: "local-store-error"
      )
    )
  }

  func testReadyWithoutProfileSurfacesInvariantFailure() {
    XCTAssertEqual(
      destination(
        phase: .ready,
        hasLocalProfile: false,
        accountState: .signedOut
      ),
      .sessionFailure(
        title: "프로필 정보를 확인할 수 없어요",
        message: "앱 상태가 올바르지 않아요. 다시 시도해 주세요."
      )
    )
  }

  func testDuplicateProviderRequestsStayLockedUntilCompletion() async {
    let coordinator = AccountEntrySocialLoginCoordinatorStub()
    let viewModel = AccountEntryViewModel(
      socialLoginCoordinator: coordinator
    )

    XCTAssertTrue(viewModel.authorizationWillBegin(provider: .apple))
    XCTAssertFalse(viewModel.authorizationWillBegin(provider: .google))
    XCTAssertTrue(viewModel.isRequestInFlight)
    XCTAssertEqual(viewModel.status, .loading)

    let cancelledResult = await viewModel.authorizationDidComplete(.cancelled)
    XCTAssertFalse(cancelledResult)
    XCTAssertFalse(viewModel.isRequestInFlight)
    XCTAssertEqual(viewModel.status, .cancelled)
    XCTAssertTrue(viewModel.authorizationWillBegin(provider: .kakao))
  }

  func testCancellationNeverCallsMORUServer() async {
    let coordinator = AccountEntrySocialLoginCoordinatorStub()
    let viewModel = AccountEntryViewModel(
      socialLoginCoordinator: coordinator
    )

    XCTAssertTrue(viewModel.authorizationWillBegin(provider: .google))
    let result = await viewModel.authorizationDidComplete(.cancelled)
    XCTAssertFalse(result)

    XCTAssertEqual(coordinator.loginCount, 0)
    XCTAssertEqual(viewModel.status, .cancelled)
  }

  func testSuccessfulLoginCompletesEntryWithoutChangingLocalData() async {
    let coordinator = AccountEntrySocialLoginCoordinatorStub()
    let viewModel = AccountEntryViewModel(
      socialLoginCoordinator: coordinator
    )

    XCTAssertTrue(viewModel.authorizationWillBegin(provider: .kakao))
    let result = await viewModel.authorizationDidComplete(
      .authorized(
        SocialAuthorization(provider: .kakao, token: "provider-token")
      )
    )
    XCTAssertTrue(result)

    XCTAssertEqual(coordinator.loginCount, 1)
    XCTAssertEqual(viewModel.status, .idle)
    XCTAssertFalse(viewModel.isRequestInFlight)
  }

  func testOffline401ServerAndKeychainFailuresUseProviderNeutralStates() async {
    let cases: [(Error, AccountEntryFailure)] = [
      (
        APIError.transport(
          code: URLError.notConnectedToInternet.rawValue,
          message: "offline"
        ),
        .offline
      ),
      (
        APIError.server(
          statusCode: 401,
          code: "AUTH401",
          message: "unauthorized"
        ),
        .unauthorized
      ),
      (
        APIError.server(
          statusCode: 503,
          code: "SERVER503",
          message: "unavailable"
        ),
        .serviceUnavailable
      ),
      (
        CredentialStoreError.keychain(status: -25291),
        .keychain
      ),
    ]

    for (error, expectedFailure) in cases {
      let coordinator = AccountEntrySocialLoginCoordinatorStub(error: error)
      let viewModel = AccountEntryViewModel(
        socialLoginCoordinator: coordinator
      )
      XCTAssertTrue(viewModel.authorizationWillBegin(provider: .apple))

      let result = await viewModel.authorizationDidComplete(
        .authorized(
          SocialAuthorization(
            provider: .apple,
            token: "identity-token",
            authorizationCode: "authorization-code",
            rawNonce: "raw-nonce",
            providerUserIdentifier: "apple-user"
          )
        )
      )
      XCTAssertFalse(result)
      XCTAssertEqual(viewModel.status, .failure(expectedFailure))
      XCTAssertFalse(viewModel.isRequestInFlight)
    }
  }

  func testAccountRestorationFailureDistinguishesKeychainAndStoredCredentials() {
    let invalidCredentials = AccountEntryViewModel(
      socialLoginCoordinator: AccountEntrySocialLoginCoordinatorStub()
    )
    invalidCredentials.accountRestorationDidFail(.invalidCredentials)
    XCTAssertEqual(
      invalidCredentials.status,
      .failure(.invalidStoredCredentials)
    )

    let keychain = AccountEntryViewModel(
      socialLoginCoordinator: AccountEntrySocialLoginCoordinatorStub()
    )
    keychain.accountRestorationDidFail(.credentialStoreUnavailable)
    XCTAssertEqual(keychain.status, .failure(.keychain))
  }

  func testPolicyLinksRequirePublicHTTPSURLs() {
    let configuration = AccountEntryPolicyConfiguration(
      infoDictionary: [
        "MoruMainURL": "https://team-moru.github.io",
        "MoruPrivacyPolicyURL": "https://team-moru.github.io/privacy",
        "MoruTermsOfServiceURL": "http://team-moru.github.io/terms",
        "MoruSupportURL": "https://team-moru.github.io/support",
      ]
    )

    XCTAssertEqual(
      configuration.mainURL?.absoluteString,
      "https://team-moru.github.io"
    )
    XCTAssertEqual(
      configuration.privacyPolicyURL?.absoluteString,
      "https://team-moru.github.io/privacy"
    )
    XCTAssertNil(configuration.termsOfServiceURL)
    XCTAssertEqual(
      configuration.supportURL?.absoluteString,
      "https://team-moru.github.io/support"
    )
    XCTAssertFalse(configuration.isReady)
    XCTAssertEqual(
      AccountEntryPolicyConfiguration(
        infoDictionary: [
          "MoruPrivacyPolicyURL": "$(MORU_PRIVACY_POLICY_URL)",
        ]
      ),
      .unavailable
    )
    XCTAssertTrue(
      AccountEntryPolicyConfiguration(
        infoDictionary: [
          "MoruMainURL": "https://team-moru.github.io",
          "MoruPrivacyPolicyURL": "https://team-moru.github.io/privacy",
          "MoruTermsOfServiceURL": "https://team-moru.github.io/terms",
          "MoruSupportURL": "https://team-moru.github.io/support",
        ]
      ).isReady
    )
  }

  func testPublicWebLinksRejectUnapprovedHostsRoutesAndURLComponents() {
    let configuration = AccountEntryPolicyConfiguration(
      infoDictionary: [
        "MoruMainURL": "https://example.com",
        "MoruPrivacyPolicyURL": "https://team-moru.github.io/terms",
        "MoruTermsOfServiceURL":
          "https://team-moru.github.io/terms?source=login",
        "MoruSupportURL": "https://user@team-moru.github.io/support",
      ]
    )

    XCTAssertEqual(configuration, .unavailable)
  }

  func testAppleLoginRequiresExplicitReleaseReadinessGate() {
    XCTAssertFalse(
      AccountEntryProviderAvailability(
        infoDictionary: nil
      ).appleSignInEnabled
    )
    XCTAssertFalse(
      AccountEntryProviderAvailability(
        infoDictionary: [
          "MoruAppleSignInEnabled": "MORU_APPLE_SIGN_IN_ENABLED_REQUIRED",
        ]
      ).appleSignInEnabled
    )
    XCTAssertTrue(
      AccountEntryProviderAvailability(
        infoDictionary: [
          "MoruAppleSignInEnabled": "YES",
        ]
      ).appleSignInEnabled
    )
  }

  func testAccessibilityIdentifiersAreUniqueAndVoiceOverOrderIsStable() {
    let identifiers = AccountEntryAccessibility.voiceOverOrder

    XCTAssertEqual(Set(identifiers).count, identifiers.count)
    XCTAssertEqual(
      identifiers,
      [
        AccountEntryAccessibility.statusIdentifier,
        AccountEntryAccessibility.googleIdentifier,
        AccountEntryAccessibility.kakaoIdentifier,
        AccountEntryAccessibility.appleIdentifier,
        AccountEntryAccessibility.guestIdentifier,
        AccountEntryAccessibility.mainIdentifier,
        AccountEntryAccessibility.privacyIdentifier,
        AccountEntryAccessibility.termsIdentifier,
        AccountEntryAccessibility.supportIdentifier,
      ]
    )
    XCTAssertTrue(
      ([AccountEntryAccessibility.rootIdentifier] + identifiers)
        .allSatisfy { $0.hasPrefix("account-entry.") }
    )
  }

  func testProfileProviderNamesRemainExplicit() {
    XCTAssertEqual(ProfileView.providerDisplayName(.apple), "Apple")
    XCTAssertEqual(ProfileView.providerDisplayName(.google), "Google")
    XCTAssertEqual(ProfileView.providerDisplayName(.kakao), "Kakao")
    XCTAssertEqual(
      ProfileView.providerDisplayName(.unknown("future")),
      "MORU"
    )
  }

  private func destination(
    phase: SessionStore.Phase = .onboardingRequired,
    hasLocalProfile: Bool = false,
    accountState: AccountSessionState,
    accountFeaturesEnabled: Bool = true,
    didCompleteAccountEntry: Bool = false
  ) -> AppRootDestination {
    AppRouter.rootDestination(
      sessionPhase: phase,
      hasLocalProfile: hasLocalProfile,
      accountState: accountState,
      accountFeaturesEnabled: accountFeaturesEnabled,
      didCompleteAccountEntry: didCompleteAccountEntry
    )
  }
}

@MainActor
private final class AccountEntrySocialLoginCoordinatorStub:
  SocialLoginCoordinating {
  private let error: Error?
  private(set) var loginCount = 0

  init(error: Error? = nil) {
    self.error = error
  }

  func login(with authorization: SocialAuthorization) async throws {
    loginCount += 1
    if let error {
      throw error
    }
  }
}
