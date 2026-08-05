//
//  ProfileView.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import AuthenticationServices
import SwiftUI

import GoogleSignInSwift

struct ProfileView: View {
  static let rootAccessibilityIdentifier = "profile.root"
  static let accountCardAccessibilityIdentifier = "profile.account.card"
  static let accountConnectAccessibilityIdentifier = "profile.account.connect"
  static let appleSignInAccessibilityIdentifier = "profile.account.apple-sign-in"
  static let googleSignInAccessibilityIdentifier = "profile.account.google-sign-in"
  static let kakaoSignInAccessibilityIdentifier = "profile.account.kakao-sign-in"
  static let accountLogoutAccessibilityIdentifier = "profile.account.logout"
  static let accountWithdrawalAccessibilityIdentifier = "profile.account.withdrawal"

  @State private var viewModel: ProfileViewModel
  @State private var accountServerViewModel: AccountServerSettingsViewModel
  @ObservedObject private var accountSessionStore: AccountSessionStore
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @State private var displayNameDraft = ""
  @State private var isDisplayNameEditorPresented = false
  @State private var isVoiceSelectionPresented = false
  @State private var isServerVoiceSelectionPresented = false
  @State private var isResetConfirmationPresented = false
  @State private var isAppleSignInPresented = false
  @State private var isWithdrawalConfirmationPresented = false
  @State private var appleAuthorizationSession = AppleAuthorizationSession()
  private let googleAuthorizationSession: any GoogleAuthorizationStarting
  private let kakaoAuthorizationSession: any KakaoAuthorizationStarting
  private let appCapabilities: AppCapabilities
  private let automaticallyLoads: Bool

  init(
    viewModel: ProfileViewModel,
    accountServerViewModel: AccountServerSettingsViewModel =
      AccountServerSettingsViewModel(),
    accountSessionStore: AccountSessionStore,
    googleAuthorizationSession: any GoogleAuthorizationStarting =
      UnavailableGoogleAuthorizationSession(),
    kakaoAuthorizationSession: any KakaoAuthorizationStarting =
      UnavailableKakaoAuthorizationSession(),
    appCapabilities: AppCapabilities = .production,
    automaticallyLoads: Bool = true
  ) {
    _viewModel = State(initialValue: viewModel)
    _accountServerViewModel = State(initialValue: accountServerViewModel)
    _accountSessionStore = ObservedObject(wrappedValue: accountSessionStore)
    self.googleAuthorizationSession = googleAuthorizationSession
    self.kakaoAuthorizationSession = kakaoAuthorizationSession
    self.appCapabilities = appCapabilities
    self.automaticallyLoads = automaticallyLoads
  }

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.state {
        case .loading:
          loadingView
        case .content(let content):
          profileContent(content)
        case .failed(let message):
          failureView(message)
        }
      }
      .background(MoruPilotColor.canvas.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .task {
      guard automaticallyLoads else {
        return
      }

      viewModel.loadProfileSettings()
    }
    .task(id: accountSessionStore.signedInMemberID) {
      let memberID = accountSessionStore.signedInMemberID
      if memberID == nil {
        isServerVoiceSelectionPresented = false
      }
      guard automaticallyLoads else {
        return
      }

      await accountServerViewModel.load(memberID: memberID)
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }

      Task {
        await viewModel.refreshAlarmStatus()
      }
    }
    .sheet(isPresented: $isDisplayNameEditorPresented) {
      displayNameEditor
    }
    .sheet(isPresented: $isVoiceSelectionPresented) {
      voiceSelectionView
    }
    .sheet(isPresented: $isServerVoiceSelectionPresented) {
      if let memberID = accountSessionStore.signedInMemberID {
        AccountServerVoiceSelectionView(
          viewModel: accountServerViewModel,
          memberID: memberID
        )
      }
    }
    .sheet(isPresented: $isAppleSignInPresented) {
      appleSignInSheet
    }
    .confirmationDialog(
      "이 기기의 로컬 데이터를 초기화할까요?",
      isPresented: $isResetConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("초기화", role: .destructive) {
        Task {
          await viewModel.resetConfirmationButtonDidTap()
        }
      }
      Button("취소", role: .cancel) {}
    } message: {
      Text("프로필, 루틴, 수행 기록을 삭제하며 되돌릴 수 없어요.")
    }
    .confirmationDialog(
      "MORU 계정을 탈퇴할까요?",
      isPresented: $isWithdrawalConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("회원 탈퇴", role: .destructive) {
        Task {
          await viewModel.withdrawalConfirmationButtonDidTap()
        }
      }
      Button("취소", role: .cancel) {}
    } message: {
      Text(
        "서버 계정은 삭제되며 되돌릴 수 없어요. "
          + "이 기기의 로컬 프로필, 루틴과 수행 기록은 유지됩니다."
      )
    }
  }

  private func profileContent(_ content: ProfileSettingsLoadResult) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        profileTitle

        displayNameCard(content.profile)
          .padding(.top, MoruPilotSpacing.twelve)

        if appCapabilities.shouldShowAccountUI {
          settingsSection(title: "계정") {
            accountCard
          }
          .padding(.top, MoruPilotSpacing.twentyEight)
        }

        settingsSection(title: ProfileCopy.voiceSettings) {
          voiceCard(content)
        }
        .padding(.top, MoruPilotSpacing.thirtyEight)

        settingsSection(title: ProfileCopy.alarmSettings) {
          alarmStatusCard
        }
        .padding(.top, MoruPilotSpacing.twentyEight)

        settingsSection(title: ProfileCopy.dataManagement) {
          resetCard
        }
        .padding(.top, MoruPilotSpacing.twentyEight)
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
    }
  }

  private var profileTitle: some View {
    Text(ProfileCopy.title)
      .profileFigmaTextStyle(.b3.weight(.semiBold))
      .foregroundStyle(AppColor.gray550)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
  }

  private func settingsSection<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
      Text(title)
        .profileFigmaTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textSecondary)

      content()
    }
  }

  private func displayNameCard(_ profile: LocalProfile) -> some View {
    Button {
      displayNameDraft = profile.displayName
      isDisplayNameEditorPresented = true
    } label: {
      HStack(spacing: 14) {
        Circle()
          .fill(MoruPilotColor.accent)
          .frame(width: 58, height: 58)
          .overlay {
            Text(profileInitial(for: profile.displayName))
              .profileFigmaTextStyle(.b2.weight(.semiBold))
              .foregroundStyle(AppColor.grayWhite)
              .accessibilityHidden(true)
          }

        VStack(alignment: .leading, spacing: 0) {
          Text(profile.displayName)
            .profileFigmaTextStyle(.b2.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textStrong)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .layoutPriority(1)

          Text(ProfileCopy.localProfile)
            .profileFigmaTextStyle(.b4)
            .foregroundStyle(MoruPilotColor.textSecondary)
        }

        Spacer(minLength: MoruPilotSpacing.eight)
      }
      .padding(.horizontal, MoruPilotSpacing.sixteen)
      .padding(.vertical, MoruPilotSpacing.eight)
      .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
      .profilePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("표시 이름, \(profile.displayName)")
    .accessibilityHint("표시 이름을 변경합니다.")
    .accessibilityIdentifier("profile.name")
  }

  private func profileInitial(for displayName: String) -> String {
    String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
  }

  @ViewBuilder
  private var accountCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      switch accountSessionStore.state {
      case .signedOut:
        accountConnectButton(
          detail: "로그인 없이도 모든 로컬 루틴과 기록을 "
            + "계속 사용할 수 있어요."
        )
      case .restoring:
        settingsRow(
          title: "계정 확인 중",
          detail: "저장된 계정 연결을 확인하고 있어요.",
          systemImage: "person.crop.circle.badge.clock",
          showsChevron: false
        )
        .overlay(alignment: .trailing) {
          ProgressView()
            .padding(.trailing, MoruPilotSpacing.sixteen)
            .accessibilityLabel("계정 연결 확인 중")
        }
      case .signedIn(let account):
        signedInAccountActions(account)
      case .failure:
        accountConnectButton(
          detail: "계정 정보를 복구하지 못했어요. "
            + "Apple, Google 또는 Kakao로 다시 연결할 수 있어요."
        )
      }

      if viewModel.isAccountLinkInProgress {
        HStack(spacing: AppSpacing.xs) {
          ProgressView()
          Text("계정을 연결하고 있어요.")
            .profileFigmaTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("계정을 연결하고 있어요.")
      }

      if let action = viewModel.accountLifecycleAction {
        HStack(spacing: AppSpacing.xs) {
          ProgressView()
          Text(accountProgressMessage(for: action))
            .profileFigmaTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accountProgressMessage(for: action))
      }

      if let message = viewModel.accountErrorMessage {
        profileMessage(message, color: AppColor.coral300)
          .accessibilityIdentifier("profile.account.error")
      }
    }
    .accessibilityIdentifier(Self.accountCardAccessibilityIdentifier)
  }

  private func signedInAccountActions(
    _ account: SignedInAccount
  ) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      settingsRow(
        title: "\(Self.providerDisplayName(account.provider)) 계정 연결됨",
        detail: "계정 연결은 선택형 서버 기능에만 사용돼요.",
        systemImage: "person.crop.circle.badge.checkmark",
        showsChevron: false
      )
      .accessibilityLabel(
        "\(Self.providerDisplayName(account.provider)) 계정 연결됨"
      )
      .accessibilityHint("로컬 루틴과 기록은 기기에 계속 저장됩니다.")

      AccountServerSettingsSummaryView(
        viewModel: accountServerViewModel,
        memberID: account.memberID,
        onOpenVoiceSelection: {
          isServerVoiceSelectionPresented = true
        }
      )

      Button {
        Task {
          await viewModel.logoutButtonDidTap()
        }
      } label: {
        settingsRow(
          title: "로그아웃",
          detail: "계정 연결만 종료하며 로컬 데이터는 유지해요.",
          systemImage: "rectangle.portrait.and.arrow.right"
        )
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isAccountLifecycleInProgress)
      .accessibilityHint(
        "서버 로그아웃 실패와 관계없이 이 기기에서 로그아웃합니다."
      )
      .accessibilityIdentifier(Self.accountLogoutAccessibilityIdentifier)

      Button(role: .destructive) {
        isWithdrawalConfirmationPresented = true
      } label: {
        settingsRow(
          title: "회원 탈퇴",
          detail: "서버 계정을 삭제해요. 로컬 데이터 초기화와는 별도예요.",
          systemImage: "person.crop.circle.badge.minus"
        )
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isAccountLifecycleInProgress)
      .accessibilityHint("확인 후 서버 계정을 영구 삭제합니다.")
      .accessibilityIdentifier(Self.accountWithdrawalAccessibilityIdentifier)
    }
  }

  static func providerDisplayName(_ provider: AuthProvider) -> String {
    switch provider {
    case .apple:
      "Apple"
    case .google:
      "Google"
    case .kakao:
      "Kakao"
    case .unknown:
      "MORU"
    }
  }

  private func accountProgressMessage(for action: AccountLifecycleAction) -> String {
    switch action {
    case .logout:
      "로그아웃하고 있어요."
    case .withdrawal:
      "회원 탈퇴를 처리하고 있어요."
    }
  }

  private func accountConnectButton(detail: String) -> some View {
    Button {
      isAppleSignInPresented = true
    } label: {
      settingsRow(
        title: "계정 연결",
        detail: detail,
        systemImage: "person.crop.circle.badge.plus"
      )
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isAccountLinkInProgress)
    .accessibilityLabel("계정 연결")
    .accessibilityHint("선택 사항입니다. 로그인 방법을 선택합니다.")
    .accessibilityIdentifier(Self.accountConnectAccessibilityIdentifier)
  }

  private func voiceCard(_ content: ProfileSettingsLoadResult) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Button {
        isVoiceSelectionPresented = true
      } label: {
        settingsRow(
          title: ProfileCopy.moruVoice,
          detail: content.profile.selectedVoice.displayName,
          systemImage: "speaker.wave.2.fill"
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        "\(ProfileCopy.moruVoice), \(content.profile.selectedVoice.displayName)"
      )
      .accessibilityHint("앱 내장 목소리를 선택하고 미리 듣습니다.")
      .accessibilityIdentifier("profile.voice.chooser")

      if let fallbackNotice = content.fallbackNotice {
        profileMessage(fallbackNotice, color: AppColor.moruTextSecondary)
      }

      if let voiceErrorMessage = viewModel.voiceErrorMessage {
        profileMessage(voiceErrorMessage, color: AppColor.coral300)
      }
    }
  }

  private var alarmStatusCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      settingsRow(
        title: "알람 상태",
        detail: alarmStatusMessage,
        systemImage: "alarm.fill",
        showsChevron: false
      )
      .accessibilityIdentifier("profile.alarm.status")

      HStack {
        switch viewModel.alarmStatus {
        case .configured:
          EmptyView()
        case .fallbackConfigured:
          Button("설정 열기", action: viewModel.alarmSettingsButtonDidTap)
            .buttonStyle(.bordered)
        case .permissionNotDetermined:
          Button("알람 권한 확인") {
            Task {
              await viewModel.alarmAuthorizationButtonDidTap()
            }
          }
          .buttonStyle(.bordered)
          .disabled(viewModel.isAlarmRequestInProgress)
        case .permissionOff:
          Button("설정 열기", action: viewModel.alarmSettingsButtonDidTap)
            .buttonStyle(.bordered)
        case .repairRequired, .unavailable:
          Button("예약 다시 시도") {
            Task {
              await viewModel.alarmRetryButtonDidTap()
            }
          }
          .buttonStyle(.bordered)
          .disabled(viewModel.isAlarmRequestInProgress)
        }
      }
      .tint(MoruPilotColor.accent)
    }
  }

  private var resetCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Button(role: .destructive) {
        isResetConfirmationPresented = true
      } label: {
        settingsRow(
          title: "로컬 데이터 초기화",
          detail: "프로필, 루틴과 수행 기록을 이 기기에서 삭제해요.",
          systemImage: "trash.fill"
        )
      }
      .buttonStyle(.plain)
      .disabled(!viewModel.isResetAvailable)
      .accessibilityIdentifier("profile.reset")

      if viewModel.isResetInProgress {
        HStack(spacing: AppSpacing.xs) {
          ProgressView()
          Text("초기화하고 있어요.")
            .font(AppFont.label1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
      }

      if let message = viewModel.resetAvailabilityMessage {
        profileMessage(message, color: AppColor.moruTextSecondary)
      }

      if let message = viewModel.resetErrorMessage {
        profileMessage(message, color: AppColor.coral300)
      }
    }
  }

  private var alarmStatusMessage: String {
    switch viewModel.alarmStatus {
    case .configured:
      "알람이 정상적으로 설정되어 있어요."
    case .fallbackConfigured:
      "일반 알림으로 예약돼요. "
        + "무음·집중 모드에서는 울리지 않을 수 있어요."
    case .permissionNotDetermined:
      "알람 권한을 아직 확인하지 않았어요."
    case .permissionOff:
      "알람 권한이 꺼져 있어요."
    case .repairRequired:
      "일부 루틴의 알람 예약이 필요해요."
    case .unavailable:
      "알람 상태를 확인할 수 없어요."
    }
  }

  private var loadingView: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        profileTitle

        VStack(spacing: MoruPilotSpacing.twenty) {
          ProfileSkeletonBlock(cornerRadius: MoruPilotSpacing.sixteen)
            .frame(height: 82)
          ProfileSkeletonBlock(cornerRadius: MoruPilotSpacing.twelve)
            .frame(height: 64)
          ProfileSkeletonBlock(cornerRadius: MoruPilotSpacing.twelve)
            .frame(height: 64)
        }
        .padding(.top, MoruPilotSpacing.twelve)

        Text("프로필 설정을 불러오고 있어요.")
          .profileFigmaTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .padding(.top, MoruPilotSpacing.sixteen)
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
    }
    .accessibilityElement(children: .combine)
  }

  private func failureView(_ message: String) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        profileTitle

        VStack(spacing: MoruPilotSpacing.sixteen) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(AppFont.title1SemiBold)
            .foregroundStyle(MoruPilotColor.accent)
            .accessibilityHidden(true)

          Text(message)
            .profileFigmaTextStyle(.b4)
            .foregroundStyle(MoruPilotColor.textSecondary)
            .multilineTextAlignment(.center)

          Button("다시 시도", action: viewModel.retryButtonDidTap)
            .buttonStyle(.borderedProminent)
            .tint(MoruPilotColor.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
    }
  }

  private var displayNameEditor: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        TextField("표시 이름", text: $displayNameDraft)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("표시 이름")

        Text("앞뒤 공백을 제외한 1자에서 20자까지 입력할 수 있어요.")
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)

        if let message = viewModel.displayNameErrorMessage {
          profileMessage(message, color: AppColor.coral300)
        }

        Spacer()
      }
      .padding(AppSpacing.screenHorizontal)
      .navigationTitle("이름 변경")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") {
            isDisplayNameEditorPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("저장") {
            if viewModel.displayNameSaveButtonDidTap(displayNameDraft) {
              isDisplayNameEditorPresented = false
            }
          }
        }
      }
    }
  }

  private var voiceSelectionView: some View {
    NavigationStack {
      List {
        ForEach(VoiceProfile.localVoices) { voice in
          voiceRow(voice)
        }

        if let message = viewModel.voiceErrorMessage {
          profileMessage(message, color: AppColor.coral300)
        }
      }
      .navigationTitle(ProfileCopy.moruVoice)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("닫기") {
            isVoiceSelectionPresented = false
          }
        }
      }
    }
    .onDisappear(perform: viewModel.voiceSelectionViewDidDisappear)
  }

  private var appleSignInSheet: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
        Text("계정 연결")
          .profileFigmaTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)

        Text(
          "계정 연결은 선택 사항이에요. 취소하거나 연결에 실패해도 "
            + "기존 루틴과 기록은 그대로 사용할 수 있어요."
        )
        .profileFigmaTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

        SignInWithAppleButton(.continue) { request in
          _ = appleAuthorizationSession.configure(request)
        } onCompletion: { result in
          let outcome = appleAuthorizationSession.outcome(for: result)
          isAppleSignInPresented = false

          Task {
            await viewModel.appleAuthorizationDidComplete(outcome)
          }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 50)
        .clipShape(RoundedRectangle(cornerRadius: MoruPilotSpacing.twelve))
        .disabled(viewModel.isAccountLinkInProgress)
        .accessibilityLabel("Apple로 계속하기")
        .accessibilityHint("Apple 인증을 시작합니다.")
        .accessibilityIdentifier(Self.appleSignInAccessibilityIdentifier)

        GoogleSignInButton {
          Task {
            let outcome = await googleAuthorizationSession.authorize()
            isAppleSignInPresented = false
            await viewModel.googleAuthorizationDidComplete(outcome)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .disabled(
          viewModel.isAccountLinkInProgress
            || !googleAuthorizationSession.isConfigured
        )
        .accessibilityLabel("Google로 계속하기")
        .accessibilityHint("Google 인증을 시작합니다.")
        .accessibilityIdentifier(Self.googleSignInAccessibilityIdentifier)

        if !googleAuthorizationSession.isConfigured {
          Text(
            "Google 로그인 설정이 준비되지 않았어요. "
              + "공개 OAuth client ID 구성이 필요합니다."
          )
          .profileFigmaTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("profile.account.google-config-required")
        }

        Button {
          Task {
            let outcome = await kakaoAuthorizationSession.authorize()
            isAppleSignInPresented = false
            await viewModel.kakaoAuthorizationDidComplete(outcome)
          }
        } label: {
          Image("KakaoLoginButton")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        }
        .buttonStyle(.plain)
        .disabled(
          viewModel.isAccountLinkInProgress
            || !kakaoAuthorizationSession.isConfigured
        )
        .accessibilityLabel("Kakao로 계속하기")
        .accessibilityHint("Kakao 인증을 시작합니다.")
        .accessibilityIdentifier(Self.kakaoSignInAccessibilityIdentifier)

        if !kakaoAuthorizationSession.isConfigured {
          Text(
            "Kakao 로그인 설정이 준비되지 않았어요. "
              + "공개 Native app key와 URL scheme 구성이 필요합니다."
          )
          .profileFigmaTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("profile.account.kakao-config-required")
        }

        Spacer(minLength: 0)
      }
      .padding(MoruPilotSpacing.twenty)
      .background(MoruPilotColor.canvas.ignoresSafeArea())
      .navigationTitle("계정 연결")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("닫기") {
            isAppleSignInPresented = false
          }
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .accessibilityIdentifier("profile.account.sheet")
  }

  private func voiceRow(_ voice: VoiceProfile) -> some View {
    let isAvailable = viewModel.isVoiceAvailable(voice)
    let isSelected = selectedVoiceID == voice.id

    return VStack(alignment: .leading, spacing: AppSpacing.sm) {
      HStack(spacing: AppSpacing.sm) {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(voice.displayName)
            .font(AppFont.label1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
          Text(isAvailable ? "앱 내장 음성" : "음성 파일 없음")
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppColor.moruBlue)
            .accessibilityLabel("현재 선택됨")
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: AppSpacing.sm) {
          voiceSelectionButton(voice, isAvailable: isAvailable, isSelected: isSelected)
          voicePreviewButton(voice, isAvailable: isAvailable)
        }
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
          voiceSelectionButton(voice, isAvailable: isAvailable, isSelected: isSelected)
          voicePreviewButton(voice, isAvailable: isAvailable)
        }
      }
    }
    .padding(.vertical, AppSpacing.xxs)
  }

  private func voiceSelectionButton(
    _ voice: VoiceProfile,
    isAvailable: Bool,
    isSelected: Bool
  ) -> some View {
    Button(isSelected ? "선택됨" : "선택") {
      if viewModel.voiceSelectionButtonDidTap(voice) {
        isVoiceSelectionPresented = false
      }
    }
    .buttonStyle(.borderedProminent)
    .tint(AppColor.moruBlue)
    .disabled(!isAvailable || isSelected)
  }

  private func voicePreviewButton(
    _ voice: VoiceProfile,
    isAvailable: Bool
  ) -> some View {
    Button("미리 듣기") {
      viewModel.voicePreviewButtonDidTap(voice)
    }
    .buttonStyle(.bordered)
    .disabled(!isAvailable)
    .accessibilityIdentifier("voice.preview.\(voice.id)")
  }

  private var selectedVoiceID: String? {
    guard case .content(let content) = viewModel.state else {
      return nil
    }

    return content.profile.selectedVoice.id
  }

  private func profileMessage(_ message: String, color: Color) -> some View {
    Text(message)
      .profileFigmaTextStyle(.c1)
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func settingsRow(
    title: String,
    detail: String,
    systemImage: String,
    showsChevron: Bool = true
  ) -> some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      Image(systemName: systemImage)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 20, height: 20)
        .background(MoruPilotColor.accentSoft)
        .clipShape(Circle())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .profileFigmaTextStyle(.b4)
          .foregroundStyle(MoruPilotColor.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

        Text(detail)
          .profileFigmaTextStyle(.c2)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: MoruPilotSpacing.eight)

      if showsChevron {
        MoruChevron(color: MoruPilotColor.textPrimary)
      }
    }
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .padding(.vertical, MoruPilotSpacing.eight)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .profilePilotSurface(cornerRadius: MoruPilotSpacing.twelve)
  }
}

private struct ProfileSkeletonBlock: View {
  let cornerRadius: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .fill(
        LinearGradient(
          colors: [
            AppColor.gray150.opacity(0.5),
            AppColor.gray250.opacity(0.5),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .accessibilityHidden(true)
  }
}

private extension View {
  func profileFigmaTextStyle(_ style: MoruTextStyle) -> some View {
    moruPilotTextStyle(style)
  }

  func profilePilotSurface(cornerRadius: CGFloat) -> some View {
    homePilotSurface(cornerRadius: cornerRadius)
  }
}
