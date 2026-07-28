//
//  AccountEntryView.swift
//  Moru
//
//  Created by Codex on 7/27/26.
//

import AuthenticationServices
import SwiftUI

import GoogleSignInSwift

nonisolated struct AccountEntryPolicyConfiguration: Equatable, Sendable {
  let privacyPolicyURL: URL?
  let termsOfServiceURL: URL?

  var isReady: Bool {
    privacyPolicyURL != nil && termsOfServiceURL != nil
  }

  init(
    privacyPolicyURL: URL?,
    termsOfServiceURL: URL?
  ) {
    self.privacyPolicyURL = Self.publicHTTPSURL(privacyPolicyURL)
    self.termsOfServiceURL = Self.publicHTTPSURL(termsOfServiceURL)
  }

  init(infoDictionary: [String: Any]?) {
    self.init(
      privacyPolicyURL: Self.url(
        for: "MoruPrivacyPolicyURL",
        in: infoDictionary
      ),
      termsOfServiceURL: Self.url(
        for: "MoruTermsOfServiceURL",
        in: infoDictionary
      )
    )
  }

  static let unavailable = AccountEntryPolicyConfiguration(
    privacyPolicyURL: nil,
    termsOfServiceURL: nil
  )

  private static func url(
    for key: String,
    in infoDictionary: [String: Any]?
  ) -> URL? {
    guard let value = infoDictionary?[key] as? String else {
      return nil
    }

    return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func publicHTTPSURL(_ url: URL?) -> URL? {
    guard let url,
          url.scheme?.lowercased() == "https",
          let host = url.host,
          !host.isEmpty,
          !url.absoluteString.contains("$(") else {
      return nil
    }

    return url
  }
}

nonisolated struct AccountEntryProviderAvailability: Equatable, Sendable {
  let appleSignInEnabled: Bool

  init(appleSignInEnabled: Bool) {
    self.appleSignInEnabled = appleSignInEnabled
  }

  init(infoDictionary: [String: Any]?) {
    let rawValue = infoDictionary?["MoruAppleSignInEnabled"]
    if let value = rawValue as? Bool {
      appleSignInEnabled = value
      return
    }

    let normalizedValue = (rawValue as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    appleSignInEnabled = ["1", "true", "yes"].contains(normalizedValue)
  }

  static let unavailable = AccountEntryProviderAvailability(
    appleSignInEnabled: false
  )
}

nonisolated struct AccountEntryCopy: Equatable, Sendable {
  let title: String
  let subtitle: String
  let localFirstGuidance: String

  static let production = AccountEntryCopy(
    title: "나만의 아침을 시작해요",
    subtitle: "계정을 연결하면 MORU의 선택형 온라인 기능을 사용할 수 있어요.",
    localFirstGuidance: "루틴과 기록은 이 iPhone에 먼저 저장돼요. "
      + "다른 기기의 루틴은 로그인만으로 자동 복원되지 않아요."
  )
}

nonisolated enum AccountEntryAccessibility {
  static let rootIdentifier = "account-entry.root"
  static let titleIdentifier = "account-entry.title"
  static let guidanceIdentifier = "account-entry.local-first-guidance"
  static let statusIdentifier = "account-entry.status"
  static let appleIdentifier = "account-entry.apple-sign-in"
  static let googleIdentifier = "account-entry.google-sign-in"
  static let kakaoIdentifier = "account-entry.kakao-sign-in"
  static let guestIdentifier = "account-entry.continue-without-login"
  static let privacyIdentifier = "account-entry.privacy-policy"
  static let termsIdentifier = "account-entry.terms-of-service"

  static let voiceOverOrder = [
    titleIdentifier,
    guidanceIdentifier,
    statusIdentifier,
    appleIdentifier,
    googleIdentifier,
    kakaoIdentifier,
    guestIdentifier,
    privacyIdentifier,
    termsIdentifier,
  ]
}

struct AccountEntryView: View {
  @State private var viewModel: AccountEntryViewModel
  @State private var appleAuthorizationSession: AppleAuthorizationSession

  private let googleAuthorizationSession: any GoogleAuthorizationStarting
  private let kakaoAuthorizationSession: any KakaoAuthorizationStarting
  private let policyConfiguration: AccountEntryPolicyConfiguration
  private let providerAvailability: AccountEntryProviderAvailability
  private let copy: AccountEntryCopy
  private let restorationFailure: AccountSessionFailure?
  private let onContinueWithoutLogin: @MainActor () -> Void

  init(
    viewModel: AccountEntryViewModel,
    googleAuthorizationSession: any GoogleAuthorizationStarting =
      UnavailableGoogleAuthorizationSession(),
    kakaoAuthorizationSession: any KakaoAuthorizationStarting =
      UnavailableKakaoAuthorizationSession(),
    policyConfiguration: AccountEntryPolicyConfiguration =
      AccountEntryPolicyConfiguration(
        infoDictionary: Bundle.main.infoDictionary
      ),
    providerAvailability: AccountEntryProviderAvailability =
      AccountEntryProviderAvailability(
        infoDictionary: Bundle.main.infoDictionary
      ),
    copy: AccountEntryCopy = .production,
    restorationFailure: AccountSessionFailure? = nil,
    appleAuthorizationSession: AppleAuthorizationSession =
      AppleAuthorizationSession(),
    onContinueWithoutLogin: @escaping @MainActor () -> Void
  ) {
    _viewModel = State(initialValue: viewModel)
    _appleAuthorizationSession = State(initialValue: appleAuthorizationSession)
    self.googleAuthorizationSession = googleAuthorizationSession
    self.kakaoAuthorizationSession = kakaoAuthorizationSession
    self.policyConfiguration = policyConfiguration
    self.providerAvailability = providerAvailability
    self.copy = copy
    self.restorationFailure = restorationFailure
    self.onContinueWithoutLogin = onContinueWithoutLogin
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.twenty) {
        brand
          .accessibilitySortPriority(9)

        header
          .accessibilitySortPriority(8)

        localFirstCard
          .accessibilitySortPriority(7)

        if viewModel.status != .idle {
          statusView
            .accessibilitySortPriority(6)
        }

        providerButtons

        continueWithoutLoginButton
          .accessibilitySortPriority(2)

        policyLinks
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.top, MoruPilotSpacing.thirtyTwo)
      .padding(.bottom, MoruPilotSpacing.thirtySix)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .background(
      LinearGradient(
        colors: [AppColor.grayWhite, MoruPilotColor.canvas],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccountEntryAccessibility.rootIdentifier)
    .task {
      if let restorationFailure {
        viewModel.accountRestorationDidFail(restorationFailure)
      }
    }
  }

  private var brand: some View {
    Image(AppImage.moruSplashBrand)
      .resizable()
      .scaledToFit()
      .frame(maxWidth: .infinity)
      .frame(height: 104)
      .accessibilityLabel("MORU, 모두의 아침 루틴")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Text(copy.title)
        .font(AppFont.pretendardBold(size: 28, relativeTo: .title))
        .foregroundStyle(MoruPilotColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(AccountEntryAccessibility.titleIdentifier)

      Text(copy.subtitle)
        .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var localFirstCard: some View {
    HStack(alignment: .top, spacing: MoruPilotSpacing.twelve) {
      Image(systemName: "iphone.gen3")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MoruPilotColor.accent)
        .accessibilityHidden(true)

      Text(copy.localFirstGuidance)
        .font(AppFont.pretendardMedium(size: 14, relativeTo: .callout))
        .foregroundStyle(MoruPilotColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColor.grayWhite.opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
    .overlay {
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("로컬 우선 안내")
    .accessibilityValue(copy.localFirstGuidance)
    .accessibilityIdentifier(AccountEntryAccessibility.guidanceIdentifier)
  }

  private var statusView: some View {
    HStack(alignment: .top, spacing: MoruPilotSpacing.ten) {
      if viewModel.status == .loading {
        ProgressView()
          .tint(MoruPilotColor.accent)
          .accessibilityHidden(true)
      } else {
        Image(systemName: statusSymbolName)
          .foregroundStyle(statusForegroundColor)
          .accessibilityHidden(true)
      }

      Text(statusMessage)
        .font(AppFont.pretendardMedium(size: 14, relativeTo: .callout))
        .foregroundStyle(MoruPilotColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(MoruPilotSpacing.twelve)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(statusBackgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(statusMessage)
    .accessibilityIdentifier(AccountEntryAccessibility.statusIdentifier)
  }

  private var providerButtons: some View {
    VStack(spacing: MoruPilotSpacing.twelve) {
      appleButton
        .accessibilitySortPriority(5)

      googleButton
        .accessibilitySortPriority(4)

      kakaoButton
        .accessibilitySortPriority(3)
    }
  }

  private var appleButton: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      SignInWithAppleButton(.continue) { request in
        guard viewModel.authorizationWillBegin(provider: .apple) else {
          return
        }

        guard appleAuthorizationSession.configure(request) else {
          viewModel.authorizationPreparationDidFail()
          return
        }
      } onCompletion: { result in
        let outcome = appleAuthorizationSession.outcome(for: result)
        Task {
          await viewModel.authorizationDidComplete(outcome)
        }
      }
      .signInWithAppleButtonStyle(.black)
      .frame(maxWidth: .infinity, minHeight: 52)
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve))
      .disabled(
        viewModel.isRequestInFlight
          || !providerAvailability.appleSignInEnabled
          || !policyConfiguration.isReady
      )
      .accessibilityLabel("Apple로 계속하기")
      .accessibilityHint(appleAccessibilityHint)
      .accessibilityIdentifier(AccountEntryAccessibility.appleIdentifier)

      if !providerAvailability.appleSignInEnabled {
        providerConfigurationMessage(
          "Apple 로그인은 provisioning과 서버 검증이 준비된 빌드에서 사용할 수 있어요."
        )
      }
    }
  }

  private var googleButton: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      GoogleSignInButton {
        Task {
          guard viewModel.authorizationWillBegin(provider: .google) else {
            return
          }

          let outcome = await googleAuthorizationSession.authorize()
          await viewModel.authorizationDidComplete(outcome)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 52)
      .disabled(
        viewModel.isRequestInFlight
          || !googleAuthorizationSession.isConfigured
          || !policyConfiguration.isReady
      )
      .accessibilityLabel("Google로 계속하기")
      .accessibilityHint(googleAccessibilityHint)
      .accessibilityIdentifier(AccountEntryAccessibility.googleIdentifier)

      if !googleAuthorizationSession.isConfigured {
        providerConfigurationMessage(
          "Google 로그인은 공개 OAuth 설정이 준비된 빌드에서 사용할 수 있어요."
        )
      }
    }
  }

  private var kakaoButton: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      Button {
        Task {
          guard viewModel.authorizationWillBegin(provider: .kakao) else {
            return
          }

          let outcome = await kakaoAuthorizationSession.authorize()
          await viewModel.authorizationDidComplete(outcome)
        }
      } label: {
        Image("KakaoLoginButton")
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
      }
      .buttonStyle(.plain)
      .disabled(
        viewModel.isRequestInFlight
          || !kakaoAuthorizationSession.isConfigured
          || !policyConfiguration.isReady
      )
      .accessibilityLabel("Kakao로 계속하기")
      .accessibilityHint(kakaoAccessibilityHint)
      .accessibilityIdentifier(AccountEntryAccessibility.kakaoIdentifier)

      if !kakaoAuthorizationSession.isConfigured {
        providerConfigurationMessage(
          "Kakao 로그인은 공개 Native app key 설정이 준비된 빌드에서 사용할 수 있어요."
        )
      }
    }
  }

  private var continueWithoutLoginButton: some View {
    Button("로그인 없이 시작하기") {
      onContinueWithoutLogin()
    }
    .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
    .foregroundStyle(MoruPilotColor.textStrong)
    .frame(maxWidth: .infinity, minHeight: 52)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve))
    .overlay {
      RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    }
    .disabled(viewModel.isRequestInFlight)
    .accessibilityHint("계정을 연결하지 않고 이 기기의 로컬 온보딩을 시작합니다.")
    .accessibilityIdentifier(AccountEntryAccessibility.guestIdentifier)
  }

  private var policyLinks: some View {
    VStack(spacing: MoruPilotSpacing.eight) {
      Text("계속하면 아래 정책을 확인한 것으로 간주됩니다.")
        .font(AppFont.pretendardMedium(size: 12, relativeTo: .caption))
        .foregroundStyle(MoruPilotColor.textTertiary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: MoruPilotSpacing.sixteen) {
        policyLink(
          title: "개인정보처리방침",
          url: policyConfiguration.privacyPolicyURL,
          identifier: AccountEntryAccessibility.privacyIdentifier
        )
        .accessibilitySortPriority(1)

        policyLink(
          title: "이용약관",
          url: policyConfiguration.termsOfServiceURL,
          identifier: AccountEntryAccessibility.termsIdentifier
        )
        .accessibilitySortPriority(0)
      }

      if policyConfiguration.privacyPolicyURL == nil
          || policyConfiguration.termsOfServiceURL == nil {
        Text("공개 정책 URL이 준비되지 않아 현재 빌드에서는 링크를 열 수 없어요.")
          .font(AppFont.pretendardMedium(size: 12, relativeTo: .caption))
          .foregroundStyle(MoruPilotColor.textTertiary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func policyLink(
    title: String,
    url: URL?,
    identifier: String
  ) -> some View {
    if let url {
      Link(title, destination: url)
        .font(AppFont.pretendardSemiBold(size: 12, relativeTo: .caption))
        .foregroundStyle(MoruPilotColor.textPrimary)
        .accessibilityHint("Safari에서 엽니다.")
        .accessibilityIdentifier(identifier)
    } else {
      Button(title) {}
        .font(AppFont.pretendardSemiBold(size: 12, relativeTo: .caption))
        .foregroundStyle(MoruPilotColor.textTertiary)
        .disabled(true)
        .accessibilityHint("공개 URL이 구성되지 않아 열 수 없습니다.")
        .accessibilityIdentifier(identifier)
    }
  }

  private func providerConfigurationMessage(_ message: String) -> some View {
    Text(message)
      .font(AppFont.pretendardMedium(size: 12, relativeTo: .caption))
      .foregroundStyle(MoruPilotColor.textTertiary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var statusMessage: String {
    switch viewModel.status {
    case .idle:
      return ""
    case .loading:
      return "로그인 정보를 안전하게 확인하고 있어요."
    case .cancelled:
      return "로그인을 취소했어요. 다른 방법을 선택하거나 로그인 없이 시작할 수 있어요."
    case .failure(.offline):
      return "인터넷에 연결되어 있지 않아요. 연결을 확인한 뒤 다시 시도해 주세요."
    case .failure(.unauthorized):
      return "로그인 정보가 만료되었거나 유효하지 않아요. 다시 시도해 주세요."
    case .failure(.serviceUnavailable):
      return "로그인 서비스를 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
    case .failure(.keychain):
      return "이 iPhone의 보안 저장소에서 로그인 정보를 읽거나 저장하지 못했어요."
    case .failure(.invalidStoredCredentials):
      return "저장된 로그인 정보가 유효하지 않아요. 원하는 방법으로 다시 시작해 주세요."
    case .failure(.unavailable):
      return "로그인을 완료하지 못했어요. 다시 시도하거나 로그인 없이 시작할 수 있어요."
    }
  }

  private var statusSymbolName: String {
    viewModel.status == .cancelled
      ? "xmark.circle.fill"
      : "exclamationmark.triangle.fill"
  }

  private var statusForegroundColor: Color {
    viewModel.status == .cancelled
      ? MoruPilotColor.textSecondary
      : AppColor.coral300
  }

  private var statusBackgroundColor: Color {
    viewModel.status == .cancelled
      ? AppColor.gray100.opacity(0.8)
      : AppColor.coral100.opacity(0.75)
  }

  private var googleAccessibilityHint: String {
    guard policyConfiguration.isReady else {
      return "공개 정책 URL이 없어 현재 빌드에서는 사용할 수 없습니다."
    }

    return googleAuthorizationSession.isConfigured
      ? "Google 인증을 시작합니다."
      : "공개 OAuth 설정이 없어 현재 빌드에서는 사용할 수 없습니다."
  }

  private var appleAccessibilityHint: String {
    guard policyConfiguration.isReady else {
      return "공개 정책 URL이 없어 현재 빌드에서는 사용할 수 없습니다."
    }

    return providerAvailability.appleSignInEnabled
      ? "Apple 인증을 시작합니다."
      : "Apple provisioning과 서버 검증이 준비되지 않아 현재 빌드에서는 사용할 수 없습니다."
  }

  private var kakaoAccessibilityHint: String {
    guard policyConfiguration.isReady else {
      return "공개 정책 URL이 없어 현재 빌드에서는 사용할 수 없습니다."
    }

    return kakaoAuthorizationSession.isConfigured
      ? "Kakao 인증을 시작합니다."
      : "공개 Native app key 설정이 없어 현재 빌드에서는 사용할 수 없습니다."
  }
}
