//
//  OptionalLoginEntryVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/27/26.
//

import Foundation
import SwiftUI
import XCTest

@testable import Moru

@MainActor
final class OptionalLoginEntryVisualTests: XCTestCase {
  func testAccountEntryStatesRenderDeterministicallyAtMediumAndAX3() throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_OPTIONAL_LOGIN_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-optional-login-\(phase)"
    )

    for state in AccountEntryCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let filename = "\(state.rawValue)-\(variant.rawValue).png"
        let first = try MoruVisualCaptureFixture.render(
          screen(for: state),
          filename: filename,
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          screen(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        XCTAssertEqual(first.pngData(), second.pngData())
      }
    }
  }

  private func screen(
    for state: AccountEntryCaptureState
  ) -> some View {
    let viewModel = AccountEntryViewModel(
      socialLoginCoordinator: UnavailableSocialLoginCoordinator(),
      status: state.status
    )
    if state == .loading {
      _ = viewModel.authorizationWillBegin(provider: .apple)
    }

    return AccountEntryView(
      viewModel: viewModel,
      googleAuthorizationSession:
        AccountEntryConfiguredGoogleAuthorizationSession(),
      kakaoAuthorizationSession:
        AccountEntryConfiguredKakaoAuthorizationSession(),
      policyConfiguration: AccountEntryPolicyConfiguration(
        mainURL: URL(string: "https://team-moru.github.io"),
        privacyPolicyURL: URL(
          string: "https://team-moru.github.io/privacy"
        ),
        termsOfServiceURL: URL(
          string: "https://team-moru.github.io/terms"
        ),
        supportURL: URL(
          string: "https://team-moru.github.io/support"
        )
      ),
      providerAvailability: AccountEntryProviderAvailability(
        appleSignInEnabled: true
      ),
      copy: state.copy,
      onContinueWithoutLogin: {}
    )
  }
}

@MainActor
private final class AccountEntryConfiguredGoogleAuthorizationSession:
  GoogleAuthorizationStarting {
  let isConfigured = true

  func authorize() async -> SocialAuthorizationOutcome {
    .failed
  }
}

@MainActor
private final class AccountEntryConfiguredKakaoAuthorizationSession:
  KakaoAuthorizationStarting {
  let isConfigured = true

  func authorize() async -> SocialAuthorizationOutcome {
    .failed
  }
}

private enum AccountEntryCaptureState: String, CaseIterable {
  case idle
  case loading
  case cancelled
  case offline
  case unauthorized = "401"
  case serviceUnavailable = "5xx"
  case keychain
  case longKorean = "long-korean"

  var status: AccountEntryStatus {
    switch self {
    case .idle, .longKorean:
      .idle
    case .loading:
      .loading
    case .cancelled:
      .cancelled
    case .offline:
      .failure(.offline)
    case .unauthorized:
      .failure(.unauthorized)
    case .serviceUnavailable:
      .failure(.serviceUnavailable)
    case .keychain:
      .failure(.keychain)
    }
  }

  var copy: AccountEntryCopy {
    guard self == .longKorean else {
      return .production
    }

    return AccountEntryCopy(
      title: "매일 아침 나에게 꼭 맞는 아주 특별한 루틴을 차분하게 시작해요",
      subtitle: "계정 연결은 선택 사항이며 로그인하지 않아도 이 iPhone에서 "
        + "모든 로컬 루틴과 수행 기록을 계속 만들고 사용할 수 있어요.",
      localFirstGuidance: "루틴과 기록은 이 iPhone에 먼저 안전하게 저장돼요. "
        + "같은 계정으로 로그인하더라도 다른 기기에서 만든 루틴과 기록을 "
        + "자동으로 내려받거나 이 기기의 데이터와 바꾸지 않아요."
    )
  }
}
