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
  private enum Route {
    case main
    case privacy
    case terms
    case support

    var infoKey: String {
      switch self {
      case .main:
        "MoruMainURL"
      case .privacy:
        "MoruPrivacyPolicyURL"
      case .terms:
        "MoruTermsOfServiceURL"
      case .support:
        "MoruSupportURL"
      }
    }

    var path: String {
      switch self {
      case .main:
        "/"
      case .privacy:
        "/privacy"
      case .terms:
        "/terms"
      case .support:
        "/support"
      }
    }
  }

  private static let allowedHost = "team-moru.github.io"

  let mainURL: URL?
  let privacyPolicyURL: URL?
  let termsOfServiceURL: URL?
  let supportURL: URL?

  var isReady: Bool {
    mainURL != nil
      && privacyPolicyURL != nil
      && termsOfServiceURL != nil
      && supportURL != nil
  }

  init(
    mainURL: URL?,
    privacyPolicyURL: URL?,
    termsOfServiceURL: URL?,
    supportURL: URL?
  ) {
    self.mainURL = Self.publicHTTPSURL(mainURL, route: .main)
    self.privacyPolicyURL = Self.publicHTTPSURL(
      privacyPolicyURL,
      route: .privacy
    )
    self.termsOfServiceURL = Self.publicHTTPSURL(
      termsOfServiceURL,
      route: .terms
    )
    self.supportURL = Self.publicHTTPSURL(supportURL, route: .support)
  }

  init(infoDictionary: [String: Any]?) {
    self.init(
      mainURL: Self.url(for: .main, in: infoDictionary),
      privacyPolicyURL: Self.url(for: .privacy, in: infoDictionary),
      termsOfServiceURL: Self.url(for: .terms, in: infoDictionary),
      supportURL: Self.url(for: .support, in: infoDictionary)
    )
  }

  static let unavailable = AccountEntryPolicyConfiguration(
    mainURL: nil,
    privacyPolicyURL: nil,
    termsOfServiceURL: nil,
    supportURL: nil
  )

  private static func url(
    for route: Route,
    in infoDictionary: [String: Any]?
  ) -> URL? {
    guard let value = infoDictionary?[route.infoKey] as? String else {
      return nil
    }

    return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func publicHTTPSURL(
    _ url: URL?,
    route: Route
  ) -> URL? {
    guard let url,
          url.scheme?.lowercased() == "https",
          url.host?.lowercased() == allowedHost,
          url.port == nil,
          url.user == nil,
          url.password == nil,
          url.query == nil,
          url.fragment == nil,
          (url.path.isEmpty ? "/" : url.path) == route.path,
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
  static let mainIdentifier = "account-entry.main-website"
  static let privacyIdentifier = "account-entry.privacy-policy"
  static let termsIdentifier = "account-entry.terms-of-service"
  static let supportIdentifier = "account-entry.support"

  static let voiceOverOrder = [
    statusIdentifier,
    googleIdentifier,
    kakaoIdentifier,
    appleIdentifier,
    guestIdentifier,
    mainIdentifier,
    privacyIdentifier,
    termsIdentifier,
    supportIdentifier,
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
    GeometryReader { proxy in
      ZStack {
        accountEntryBackground

        ScrollView(showsIndicators: false) {
          VStack(spacing: 0) {
            Spacer()
              .frame(height: max(160, proxy.size.height * 0.275))

            brand
              .accessibilitySortPriority(9)

            Spacer(minLength: 24)

            VStack(spacing: MoruPilotSpacing.sixteen) {
              if viewModel.status != .idle {
                statusView
                  .accessibilitySortPriority(6)
              }

              providerButtons

              continueWithoutLoginButton
                .accessibilitySortPriority(2)

              policyLinks
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
            }
            .padding(.horizontal, MoruPilotSpacing.twenty)
            .padding(.bottom, max(56, proxy.safeAreaInsets.bottom + 48))
          }
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccountEntryAccessibility.rootIdentifier)
    .task {
      if let restorationFailure {
        viewModel.accountRestorationDidFail(restorationFailure)
      }
    }
  }

  private var brand: some View {
    VStack(spacing: MoruPilotSpacing.sixteen) {
      Image(AppImage.moruLoginLogo)
        .resizable()
        .scaledToFit()
        .frame(width: 118, height: 90)
        .accessibilityHidden(true)

      VStack(spacing: 0) {
        Text("MORU")
          .font(AppFont.pretendardBold(size: 36, relativeTo: .largeTitle))
          .foregroundStyle(AppColor.babyBlue300)
          .lineLimit(1)

        Text("모두의 아침 루틴")
          .font(AppFont.pretendardMedium(size: 14, relativeTo: .callout))
          .foregroundStyle(AppColor.babyBlue250)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("MORU, 모두의 아침 루틴")
  }

  private var accountEntryBackground: some View {
    LinearGradient(
      colors: [
        AppColor.grayWhite,
        AppColor.babyBlue50,
        AppColor.babyBlue100,
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
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
    HStack(spacing: MoruPilotSpacing.twenty) {
      googleButton
      kakaoButton
      appleButton
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilitySortPriority(5)
  }

  private var appleButton: some View {
    ZStack {
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
      .frame(width: 56, height: 56)
      .clipShape(Circle())
      .disabled(appleButtonDisabled)
      .accessibilityLabel("Apple로 계속하기")
      .accessibilityHint(appleAccessibilityHint)
      .accessibilityIdentifier(AccountEntryAccessibility.appleIdentifier)

      MoruSocialLoginIconButton(
        provider: .apple,
        isLoading: viewModel.activeProvider == .apple,
        isDisabled: appleButtonDisabled
      ) {}
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .frame(width: 56, height: 56)
  }

  private var googleButton: some View {
    MoruSocialLoginIconButton(
      provider: .google,
      isLoading: viewModel.activeProvider == .google,
      isDisabled: googleButtonDisabled
    ) {
      Task {
        guard viewModel.authorizationWillBegin(provider: .google) else {
          return
        }

        let outcome = await googleAuthorizationSession.authorize()
        await viewModel.authorizationDidComplete(outcome)
      }
    }
    .accessibilityLabel("Google로 계속하기")
    .accessibilityHint(googleAccessibilityHint)
    .accessibilityIdentifier(AccountEntryAccessibility.googleIdentifier)
  }

  private var kakaoButton: some View {
    MoruSocialLoginIconButton(
      provider: .kakao,
      isLoading: viewModel.activeProvider == .kakao,
      isDisabled: kakaoButtonDisabled
    ) {
      Task {
        guard viewModel.authorizationWillBegin(provider: .kakao) else {
          return
        }

        let outcome = await kakaoAuthorizationSession.authorize()
        await viewModel.authorizationDidComplete(outcome)
      }
    }
    .accessibilityLabel("Kakao로 계속하기")
    .accessibilityHint(kakaoAccessibilityHint)
    .accessibilityIdentifier(AccountEntryAccessibility.kakaoIdentifier)
  }

  private var continueWithoutLoginButton: some View {
    Button("로그인 없이 시작하기") {
      onContinueWithoutLogin()
    }
    .font(AppFont.pretendardMedium(size: 14, relativeTo: .callout))
    .foregroundStyle(AppColor.gray300)
    .frame(maxWidth: .infinity)
    .disabled(viewModel.isRequestInFlight)
    .accessibilityHint("계정을 연결하지 않고 바로 MORU를 시작합니다.")
    .accessibilityIdentifier(AccountEntryAccessibility.guestIdentifier)
  }

  private var appleButtonDisabled: Bool {
    viewModel.isRequestInFlight
      || !providerAvailability.appleSignInEnabled
      || !policyConfiguration.isReady
  }

  private var googleButtonDisabled: Bool {
    viewModel.isRequestInFlight
      || !googleAuthorizationSession.isConfigured
      || !policyConfiguration.isReady
  }

  private var kakaoButtonDisabled: Bool {
    viewModel.isRequestInFlight
      || !kakaoAuthorizationSession.isConfigured
      || !policyConfiguration.isReady
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
          title: "MORU 홈",
          url: policyConfiguration.mainURL,
          identifier: AccountEntryAccessibility.mainIdentifier
        )

        policyLink(
          title: "개인정보처리방침",
          url: policyConfiguration.privacyPolicyURL,
          identifier: AccountEntryAccessibility.privacyIdentifier
        )
      }

      HStack(spacing: MoruPilotSpacing.sixteen) {
        policyLink(
          title: "이용약관",
          url: policyConfiguration.termsOfServiceURL,
          identifier: AccountEntryAccessibility.termsIdentifier
        )

        policyLink(
          title: "고객지원",
          url: policyConfiguration.supportURL,
          identifier: AccountEntryAccessibility.supportIdentifier
        )
      }

      if !policyConfiguration.isReady {
        Text(
          "공개 웹 URL이 준비되지 않아 현재 빌드에서는 "
            + "링크를 열 수 없어요."
        )
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
