//
//  ProfileView.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import AuthenticationServices
import SwiftUI
import UIKit

enum ProfileSummaryDisplayNameResolver {
  static func resolve(
    localProfile: LocalProfile,
    sessionState: AccountSessionState,
    serverProfile: ServerAccountProfile?
  ) -> String {
    guard case .signedIn(let account) = sessionState,
          let serverProfile,
          serverProfile.memberID == account.memberID else {
      return localProfile.displayName
    }

    let nickname = serverProfile.nickname.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return nickname.isEmpty ? localProfile.displayName : nickname
  }
}

struct ProfileView: View {
  static let rootAccessibilityIdentifier = "profile.root"
  static let accountCardAccessibilityIdentifier = "profile.account.card"
  static let accountConnectAccessibilityIdentifier = "profile.account.connect"
  static let appleSignInAccessibilityIdentifier = "profile.account.apple-sign-in"
  static let googleSignInAccessibilityIdentifier = "profile.account.google-sign-in"
  static let kakaoSignInAccessibilityIdentifier = "profile.account.kakao-sign-in"
  static let accountLogoutAccessibilityIdentifier = "profile.account.logout"
  static let accountWithdrawalAccessibilityIdentifier = "profile.account.withdrawal"
  static let accountWithdrawalRetryAccessibilityIdentifier =
    "profile.account.withdrawal-retry"
  static let appleWithdrawalReauthenticationAccessibilityIdentifier =
    "profile.account.withdrawal.apple-reauthentication"
  static let accountRoutineArchiveAccessibilityIdentifier =
    "profile.account.routine-archive"
  static let privacyPolicyAccessibilityIdentifier = "profile.support.privacy"
  static let termsOfServiceAccessibilityIdentifier = "profile.support.terms"
  static let contactAccessibilityIdentifier = "profile.support.contact"
  static let geminiDataConsentAccessibilityIdentifier = "profile.gemini-consent"

  @State private var viewModel: ProfileViewModel
  @State private var accountServerViewModel: AccountServerSettingsViewModel
  @State private var serverVoicePreviewPlayer: ServerVoicePreviewPlayer
  @State private var accountRoutineGroupListViewModel:
    AccountRoutineGroupListViewModel
  @State private var accountRoutineGroupDetailViewModel:
    AccountRoutineGroupDetailViewModel
  @ObservedObject private var accountSessionStore: AccountSessionStore
  @ObservedObject private var geminiDataConsentStore: GeminiDataConsentStore
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @State private var displayNameDraft = ""
  @State private var isDisplayNameEditorPresented = false
  @State private var isMoruVoiceSettingsPresented = false
  @State private var isVoiceSelectionPresented = false
  @State private var isServerVoiceSelectionPresented = false
  @State private var isResetConfirmationPresented = false
  @State private var isAppleSignInPresented = false
  @State private var isWithdrawalConfirmationPresented = false
  @State private var supportLinkAlert: ProfileSupportLinkAlert?
  @State private var routineArchiveNavigation =
    AccountRoutineGroupArchiveNavigationState()
  @State private var appleAuthorizationSession = AppleAuthorizationSession()
  private let googleAuthorizationSession: any GoogleAuthorizationStarting
  private let kakaoAuthorizationSession: any KakaoAuthorizationStarting
  private let appCapabilities: AppCapabilities
  private let automaticallyLoads: Bool
  private let supportLinks: ProfileSupportLinks
  private let supportLinkOpener: ProfileSupportLinkOpener

  init(
    viewModel: ProfileViewModel,
    accountServerViewModel: AccountServerSettingsViewModel =
      AccountServerSettingsViewModel(),
    serverVoicePreviewPlayer: ServerVoicePreviewPlayer = ServerVoicePreviewPlayer(),
    accountRoutineGroupRemoteService:
      (any AccountRoutineGroupRemoteServing)? = nil,
    accountSessionStore: AccountSessionStore,
    googleAuthorizationSession: any GoogleAuthorizationStarting =
      UnavailableGoogleAuthorizationSession(),
    kakaoAuthorizationSession: any KakaoAuthorizationStarting =
      UnavailableKakaoAuthorizationSession(),
    geminiDataConsentStore: GeminiDataConsentStore = GeminiDataConsentStore(),
    appCapabilities: AppCapabilities = .production,
    automaticallyLoads: Bool = true,
    supportLinks: ProfileSupportLinks? = nil,
    supportURLOpener: @escaping ProfileSupportLinkOpener.OpenURL = { url in
      await UIApplication.shared.open(url)
    }
  ) {
    _viewModel = State(initialValue: viewModel)
    _accountServerViewModel = State(initialValue: accountServerViewModel)
    _serverVoicePreviewPlayer = State(
      initialValue: serverVoicePreviewPlayer
    )
    _accountRoutineGroupListViewModel = State(
      initialValue: AccountRoutineGroupListViewModel(
        remoteService: accountRoutineGroupRemoteService
      )
    )
    _accountRoutineGroupDetailViewModel = State(
      initialValue: AccountRoutineGroupDetailViewModel(
        remoteService: accountRoutineGroupRemoteService
      )
    )
    _accountSessionStore = ObservedObject(wrappedValue: accountSessionStore)
    _geminiDataConsentStore = ObservedObject(
      wrappedValue: geminiDataConsentStore
    )
    self.googleAuthorizationSession = googleAuthorizationSession
    self.kakaoAuthorizationSession = kakaoAuthorizationSession
    self.appCapabilities = appCapabilities
    self.automaticallyLoads = automaticallyLoads
    self.supportLinkOpener = ProfileSupportLinkOpener(
      openURL: supportURLOpener
    )
    self.supportLinks = supportLinks ?? ProfileSupportLinks(
      policyConfiguration: AccountEntryPolicyConfiguration(
        infoDictionary: Bundle.main.infoDictionary
      )
    )
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
      .navigationDestination(
        isPresented: $routineArchiveNavigation.isArchivePresented
      ) {
        AccountRoutineGroupListView(
          viewModel: accountRoutineGroupListViewModel,
          memberID: accountSessionStore.signedInMemberID,
          onSelectRoutineGroup: { routineGroupID in
            routineArchiveNavigation.presentDetail(
              routineGroupID: routineGroupID
            )
          }
        )
      }
      .navigationDestination(
        isPresented: $routineArchiveNavigation.isDetailPresented
      ) {
        if let selectedRoutineGroupID =
          routineArchiveNavigation.selectedRoutineGroupID {
          AccountRoutineGroupDetailView(
            viewModel: accountRoutineGroupDetailViewModel,
            routineGroupID: selectedRoutineGroupID,
            memberID: accountSessionStore.signedInMemberID
          )
        }
      }
      .navigationDestination(isPresented: $isMoruVoiceSettingsPresented) {
        MoruVoiceSettingsView(
          profileViewModel: viewModel,
          accountServerViewModel: accountServerViewModel,
          onOpenDeviceVoiceSelection: {
            isVoiceSelectionPresented = true
          },
          onOpenServerVoiceSelection: {
            isServerVoiceSelectionPresented = true
          }
        )
      }
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
    .onChange(of: accountSessionStore.signedInMemberID) {
      _, memberID in
      isServerVoiceSelectionPresented = false
      routineArchiveNavigation.reset()
      accountRoutineGroupListViewModel.accountDidChange(
        memberID: memberID
      )
      accountRoutineGroupDetailViewModel.accountDidChange(
        memberID: memberID
      )
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
          previewPlayer: serverVoicePreviewPlayer,
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
      withdrawalConfirmationTitle,
      isPresented: $isWithdrawalConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button(withdrawalConfirmationButtonTitle, role: .destructive) {
        Task {
          await viewModel.withdrawalConfirmationButtonDidTap()
        }
      }
      Button("취소", role: .cancel) {}
    } message: {
      Text(withdrawalConfirmationMessage)
    }
    .alert(item: $supportLinkAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text(ProfileCopy.confirm))
      )
    }
  }

  private func profileContent(_ content: ProfileSettingsLoadResult) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        profileTitle

        profileCard(
          displayName: profileSummaryDisplayName(for: content.profile)
        )
          .padding(.top, MoruPilotSpacing.twelve)

        settingsSection(title: ProfileCopy.voiceSettings) {
          voiceCard(content)
        }
        .padding(.top, MoruPilotSpacing.thirtyEight)

        if appCapabilities.shouldShowAccountUI {
          settingsSection(title: ProfileCopy.account) {
            accountCard
          }
          .padding(.top, MoruPilotSpacing.twentyEight)
        }

        settingsSection(title: ProfileCopy.aiDataHandling) {
          geminiDataConsentCard
        }
        .padding(.top, MoruPilotSpacing.twentyEight)

        settingsSection(title: ProfileCopy.dataManagement) {
          dataManagementCard
        }
        .padding(.top, MoruPilotSpacing.twentyEight)

        supportSection
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

  private func profileCard(displayName: String) -> some View {
    HStack(spacing: 14) {
      profileAvatar(displayName: displayName)

      VStack(alignment: .leading, spacing: 0) {
        Text(displayName)
          .profileFigmaTextStyle(.b2.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
          .layoutPriority(1)

        Text(profileSubtitle)
          .profileFigmaTextStyle(.b4)
          .foregroundStyle(MoruPilotColor.textSecondary)
      }

      Spacer(minLength: MoruPilotSpacing.eight)
    }
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .padding(.vertical, MoruPilotSpacing.eight)
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    .profilePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(displayName), \(profileSubtitle)")
    .accessibilityIdentifier("profile.summary")
  }

  private func profileSummaryDisplayName(
    for localProfile: LocalProfile
  ) -> String {
    ProfileSummaryDisplayNameResolver.resolve(
      localProfile: localProfile,
      sessionState: accountSessionStore.state,
      serverProfile: accountServerViewModel.profileState.value
    )
  }

  @ViewBuilder
  private func profileAvatar(displayName: String) -> some View {
    if case .signedIn = accountSessionStore.state {
      Circle()
        .fill(MoruPilotColor.accent)
        .frame(width: 58, height: 58)
        .overlay {
          Text(profileInitial(for: displayName))
            .profileFigmaTextStyle(.b2.weight(.semiBold))
            .foregroundStyle(AppColor.grayWhite)
        }
        .accessibilityHidden(true)
    } else {
      MoruBrandBadge(size: 58)
    }
  }

  private func profileInitial(for displayName: String) -> String {
    String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
  }

  private var profileSubtitle: String {
    switch accountSessionStore.state {
    case .signedIn(let account):
      "\(Self.providerDisplayName(account.provider)) 계정 연결됨"
    case .restoring:
      "계정 확인 중"
    case .withdrawalPending:
      ProfileCopy.withdrawalPending
    case .signedOut, .failure:
      ProfileCopy.socialLogin
    }
  }

  @ViewBuilder
  private var accountCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      switch accountSessionStore.state {
      case .signedOut:
        accountConnectButton
      case .restoring:
        figmaNavigationRow(title: "계정 확인 중", showsChevron: false)
        .overlay(alignment: .trailing) {
          ProgressView()
            .padding(.trailing, MoruPilotSpacing.sixteen)
            .accessibilityLabel("계정 연결 확인 중")
        }
      case .signedIn:
        signedInAccountActions
      case .withdrawalPending:
        pendingWithdrawalActions
      case .failure:
        accountConnectButton
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

  private var signedInAccountActions: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      Button {
        Task {
          await viewModel.logoutButtonDidTap()
        }
      } label: {
        figmaNavigationRow(title: ProfileCopy.logout)
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
        figmaNavigationRow(title: ProfileCopy.withdraw)
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isAccountLifecycleInProgress)
      .accessibilityHint("확인 후 서버 계정을 영구 삭제합니다.")
      .accessibilityIdentifier(Self.accountWithdrawalAccessibilityIdentifier)
    }
  }

  private var geminiDataConsentCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      Text(geminiDataConsentDescription)
        .profileFigmaTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Button {
        geminiDataConsentStore.presentConsentChoices()
      } label: {
        figmaNavigationRow(title: ProfileCopy.aiDataConsentManage)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Google Gemini 데이터 처리 동의 내용을 확인합니다.")
      .accessibilityIdentifier(Self.geminiDataConsentAccessibilityIdentifier)

      if geminiDataConsentStore.hasExplicitGeminiDataConsent {
        Button(role: .destructive) {
          geminiDataConsentStore.revoke()
        } label: {
          figmaNavigationRow(title: ProfileCopy.aiDataConsentWithdraw)
        }
        .buttonStyle(.plain)
        .accessibilityHint("앞으로 AI 처리로 이어질 수 있는 새 데이터 전송을 중단합니다.")
        .accessibilityIdentifier("profile.gemini-consent.revoke")
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var geminiDataConsentDescription: String {
    if geminiDataConsentStore.hasExplicitGeminiDataConsent {
      return "AI 루틴 기능에 필요한 데이터 전송에 동의했어요. 언제든 철회할 수 있어요."
    }
    return "동의하지 않아도 로컬 루틴은 계속 사용할 수 있어요. AI 처리로 이어질 수 있는 데이터는 전송하지 않아요."
  }

  private var pendingWithdrawalActions: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
      if viewModel.requiresAppleWithdrawalReauthentication {
        profileMessage(
          ProfileCopy.appleWithdrawalReauthenticationDescription,
          color: MoruPilotColor.textSecondary
        )
        .accessibilityIdentifier(
          "profile.account.withdrawal-apple-reauthentication-message"
        )

        SignInWithAppleButton(.continue) { request in
          guard viewModel.appleWithdrawalReauthenticationWillBegin() else {
            return
          }
          guard appleAuthorizationSession.configure(request) else {
            viewModel.appleWithdrawalReauthenticationPreparationDidFail()
            return
          }
        } onCompletion: { result in
          let outcome = appleAuthorizationSession.outcome(for: result)
          Task {
            await viewModel.appleWithdrawalReauthenticationDidComplete(outcome)
          }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 48)
        .disabled(!viewModel.canBeginAppleWithdrawalReauthentication)
        .accessibilityLabel(ProfileCopy.appleWithdrawalReauthentication)
        .accessibilityHint("Apple 인증 뒤 회원탈퇴를 계속합니다.")
        .accessibilityIdentifier(
          Self.appleWithdrawalReauthenticationAccessibilityIdentifier
        )
      } else {
        profileMessage(
          ProfileCopy.withdrawalPendingDescription,
          color: MoruPilotColor.textSecondary
        )
        .accessibilityIdentifier("profile.account.withdrawal-pending-message")

        Button(role: .destructive) {
          isWithdrawalConfirmationPresented = true
        } label: {
          figmaNavigationRow(title: ProfileCopy.retryWithdrawal)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAccountLifecycleInProgress)
        .accessibilityHint(
          "서버 처리 결과가 불확실한 회원탈퇴 요청을 다시 보냅니다."
        )
        .accessibilityIdentifier(
          Self.accountWithdrawalRetryAccessibilityIdentifier
        )
      }
    }
  }

  private var withdrawalConfirmationTitle: String {
    accountSessionStore.isWithdrawalPending
      ? "회원탈퇴를 다시 확인할까요?"
      : "MORU 계정을 탈퇴할까요?"
  }

  private var withdrawalConfirmationButtonTitle: String {
    accountSessionStore.isWithdrawalPending ? "다시 시도" : "회원 탈퇴"
  }

  private var withdrawalConfirmationMessage: String {
    if accountSessionStore.isWithdrawalPending {
      return "이전 요청의 서버 처리 결과를 확인하지 못했어요. "
        + "다시 요청한 뒤 서버 응답이 확인되어야 완료돼요. "
        + "이 기기의 로컬 프로필, 루틴과 수행 기록은 유지됩니다."
    }

    return "서버 계정은 삭제되며 되돌릴 수 없어요. "
      + "이 기기의 로컬 프로필, 루틴과 수행 기록은 유지됩니다."
  }

  static func providerDisplayName(_ provider: AuthProvider) -> String {
    switch provider {
    case .apple:
      "Apple"
    case .google:
      "Google"
    case .kakao:
      "카카오"
    case .unknown:
      "MORU"
    }
  }

  static func shouldShowAccountRoutineArchive(
    accountState: AccountSessionState,
    hasRemoteService: Bool
  ) -> Bool {
    guard case .signedIn = accountState else {
      return false
    }
    return hasRemoteService
  }

  private func accountProgressMessage(for action: AccountLifecycleAction) -> String {
    switch action {
    case .logout:
      "로그아웃하고 있어요."
    case .withdrawal:
      "회원 탈퇴를 처리하고 있어요."
    }
  }

  private var accountConnectButton: some View {
    Button {
      isAppleSignInPresented = true
    } label: {
      figmaNavigationRow(title: ProfileCopy.socialLogin)
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isAccountLinkInProgress)
    .accessibilityLabel(ProfileCopy.socialLogin)
    .accessibilityHint("선택 사항입니다. 로그인 방법을 선택합니다.")
    .accessibilityIdentifier(Self.accountConnectAccessibilityIdentifier)
  }

  private func voiceCard(_ content: ProfileSettingsLoadResult) -> some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Button {
        isMoruVoiceSettingsPresented = true
      } label: {
        figmaNavigationRow(title: ProfileCopy.moruVoice)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        "모루 말투, 기기 내장 음성 \(content.profile.selectedVoice.displayName)"
      )
      .accessibilityHint("기기 내장 음성과 서버 생성 음성을 선택합니다.")
      .accessibilityIdentifier("profile.voice.chooser")

      if let fallbackNotice = content.fallbackNotice {
        profileMessage(fallbackNotice, color: AppColor.moruTextSecondary)
      }

      if let voiceErrorMessage = viewModel.voiceErrorMessage {
        profileMessage(voiceErrorMessage, color: AppColor.coral300)
      }
    }
  }

  private var dataManagementCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      Button(role: .destructive) {
        isResetConfirmationPresented = true
      } label: {
        figmaNavigationRow(title: ProfileCopy.resetLocalData)
      }
      .buttonStyle(.plain)
      .disabled(!viewModel.isResetAvailable || accountSessionStore.isWithdrawalPending)
      .accessibilityIdentifier("profile.reset")

      if viewModel.isResetInProgress {
        HStack(spacing: AppSpacing.xs) {
          ProgressView()
          Text("초기화하고 있어요.")
            .font(AppFont.label1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
      }

      if accountSessionStore.isWithdrawalPending {
        profileMessage(
          ProfileCopy.withdrawalResetUnavailable,
          color: AppColor.moruTextSecondary
        )
      } else if let message = viewModel.resetAvailabilityMessage {
        profileMessage(message, color: AppColor.moruTextSecondary)
      }

      if let message = viewModel.resetErrorMessage {
        profileMessage(message, color: AppColor.coral300)
      }
    }
  }

  private var supportCard: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      ForEach(ProfileSupportLinkDestination.allCases, id: \.self) { destination in
        Button {
          openSupportLink(destination)
        } label: {
          figmaNavigationRow(title: destination.title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.accessibilityLabel)
        .accessibilityHint(destination.accessibilityHint)
        .accessibilityIdentifier(
          Self.supportAccessibilityIdentifier(for: destination)
        )
      }
    }
  }

  private var supportSection: some View {
    settingsSection(title: ProfileCopy.support) {
      supportCard
    }
  }

  private func openSupportLink(_ destination: ProfileSupportLinkDestination) {
    Task {
      supportLinkAlert = await supportLinkOpener.open(
        destination: destination,
        url: supportURL(for: destination)
      )
    }
  }

  private func supportURL(for destination: ProfileSupportLinkDestination) -> URL? {
    switch destination {
    case .privacyPolicy:
      supportLinks.privacyPolicyURL
    case .termsOfService:
      supportLinks.termsOfServiceURL
    case .contact:
      supportLinks.contactURL
    }
  }

  static func supportAccessibilityIdentifier(
    for destination: ProfileSupportLinkDestination
  ) -> String {
    switch destination {
    case .privacyPolicy:
      privacyPolicyAccessibilityIdentifier
    case .termsOfService:
      termsOfServiceAccessibilityIdentifier
    case .contact:
      contactAccessibilityIdentifier
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

        supportSection
          .padding(.top, MoruPilotSpacing.twentyEight)
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
    }
    .accessibilityElement(children: .contain)
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

        supportSection
          .padding(.top, MoruPilotSpacing.twentyEight)
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
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        accountConnectionHeader
          .padding(.top, MoruPilotSpacing.twenty)

        Text(ProfileCopy.accountConnection)
          .profileFigmaTextStyle(.h3.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .padding(.top, MoruPilotSpacing.sixteen)

        Text(ProfileCopy.accountConnectionDescription)
          .profileFigmaTextStyle(.b4)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .padding(.top, MoruPilotSpacing.twelve)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: MoruPilotSpacing.twenty) {
          googleSocialLoginButton
          kakaoSocialLoginButton
          appleSocialLoginButton
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MoruPilotSpacing.thirtyEight)
      }
      .padding(.horizontal, MoruPilotSpacing.twentyEight)
      .padding(.bottom, MoruPilotSpacing.twentyEight)
    }
    .background(MoruPilotColor.profileSurface)
    .presentationDetents([
      .height(dynamicTypeSize.isAccessibilitySize ? 608 : 288),
    ])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(32)
    .presentationBackground(MoruPilotColor.profileSurface)
    .accessibilityIdentifier("profile.account.sheet")
  }

  private var appleSocialLoginButton: some View {
    ZStack {
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
      .frame(width: 56, height: 56)
      .clipShape(Circle())
      .disabled(viewModel.isAccountLinkInProgress)
      .accessibilityLabel("Apple로 계속하기")
      .accessibilityHint("Apple 인증을 시작합니다.")
      .accessibilityIdentifier(Self.appleSignInAccessibilityIdentifier)

      MoruSocialLoginIconButton(
        provider: .apple,
        isLoading: viewModel.isAccountLinkInProgress,
        isDisabled: viewModel.isAccountLinkInProgress
      ) {}
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .frame(width: 56, height: 56)
  }

  private var googleSocialLoginButton: some View {
    let isDisabled = viewModel.isAccountLinkInProgress
      || !googleAuthorizationSession.isConfigured

    return MoruSocialLoginIconButton(
      provider: .google,
      isLoading: false,
      isDisabled: isDisabled
    ) {
      Task {
        let outcome = await googleAuthorizationSession.authorize()
        isAppleSignInPresented = false
        await viewModel.googleAuthorizationDidComplete(outcome)
      }
    }
    .accessibilityLabel("Google로 계속하기")
    .accessibilityHint("Google 인증을 시작합니다.")
    .accessibilityIdentifier(Self.googleSignInAccessibilityIdentifier)
  }

  private var kakaoSocialLoginButton: some View {
    let isDisabled = viewModel.isAccountLinkInProgress
      || !kakaoAuthorizationSession.isConfigured

    return MoruSocialLoginIconButton(
      provider: .kakao,
      isLoading: false,
      isDisabled: isDisabled
    ) {
      Task {
        let outcome = await kakaoAuthorizationSession.authorize()
        isAppleSignInPresented = false
        await viewModel.kakaoAuthorizationDidComplete(outcome)
      }
    }
    .accessibilityLabel("카카오로 계속하기")
    .accessibilityHint("카카오 인증을 시작합니다.")
    .accessibilityIdentifier(Self.kakaoSignInAccessibilityIdentifier)
  }

  private var accountConnectionHeader: some View {
    ZStack {
      Text(ProfileCopy.accountConnection)
        .profileFigmaTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .frame(maxWidth: .infinity)

      HStack {
        Spacer(minLength: 0)

        Button {
          isAppleSignInPresented = false
        } label: {
          Text(ProfileCopy.close)
            .profileFigmaTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruPilotColor.textPrimary)
            .padding(.horizontal, MoruPilotSpacing.sixteen)
            .frame(minHeight: 48)
            .background(AppColor.gray100, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ProfileCopy.close)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 40)
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

  private func figmaNavigationRow(
    title: String,
    showsChevron: Bool = true
  ) -> some View {
    HStack {
      Text(title)
        .profileFigmaTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

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

nonisolated enum ProfileSupportLinkDestination: CaseIterable, Hashable, Sendable {
  case privacyPolicy
  case termsOfService
  case contact

  var title: String {
    switch self {
    case .privacyPolicy:
      ProfileCopy.privacyPolicy
    case .termsOfService:
      ProfileCopy.termsOfService
    case .contact:
      ProfileCopy.contact
    }
  }

  var accessibilityLabel: String {
    title
  }

  var accessibilityHint: String {
    switch self {
    case .privacyPolicy:
      "웹 브라우저에서 개인정보처리방침을 엽니다."
    case .termsOfService:
      "웹 브라우저에서 이용약관을 엽니다."
    case .contact:
      "메일 앱에서 문의 메일을 작성합니다."
    }
  }
}

nonisolated struct ProfileSupportLinkAlert: Equatable, Identifiable, Sendable {
  enum Reason: String, Equatable, Sendable {
    case misconfigured
    case openFailed
  }

  let destination: ProfileSupportLinkDestination
  let reason: Reason

  var id: String {
    "\(destination)-\(reason.rawValue)"
  }

  var title: String {
    ProfileCopy.supportLinkErrorTitle
  }

  var message: String {
    switch reason {
    case .misconfigured:
      ProfileCopy.supportLinkConfigurationError
    case .openFailed:
      ProfileCopy.supportLinkOpenError(title: destination.title)
    }
  }
}

@MainActor
struct ProfileSupportLinkOpener {
  typealias OpenURL = @MainActor (URL) async -> Bool

  private let openURL: OpenURL

  init(
    openURL: @escaping OpenURL = { url in
      await UIApplication.shared.open(url)
    }
  ) {
    self.openURL = openURL
  }

  func open(
    destination: ProfileSupportLinkDestination,
    url: URL?
  ) async -> ProfileSupportLinkAlert? {
    guard let url else {
      return ProfileSupportLinkAlert(
        destination: destination,
        reason: .misconfigured
      )
    }

    guard await openURL(url) else {
      return ProfileSupportLinkAlert(
        destination: destination,
        reason: .openFailed
      )
    }

    return nil
  }
}

struct MoruVoiceSettingsView: View {
  @Bindable var profileViewModel: ProfileViewModel
  @Bindable var accountServerViewModel: AccountServerSettingsViewModel
  let onOpenDeviceVoiceSelection: () -> Void
  let onOpenServerVoiceSelection: () -> Void

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
          Button(action: onOpenDeviceVoiceSelection) {
            voiceSettingsRow(
              title: "기기 내장 음성",
              detail: "\(selectedDeviceVoiceDisplayName) · 미리듣기 가능"
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "기기 내장 음성, \(selectedDeviceVoiceDisplayName)"
          )
          .accessibilityHint("앱 내장 목소리를 선택하고 미리 듣습니다.")
          .accessibilityIdentifier("profile.voice.device")

          Divider()
            .overlay(MoruPilotColor.border)

          Button(action: onOpenServerVoiceSelection) {
            voiceSettingsRow(
              title: "서버 생성 음성",
              detail: serverVoiceDetail
            )
          }
          .buttonStyle(.plain)
          .disabled(!canOpenServerVoiceSelection)
          .accessibilityLabel("서버 생성 음성, \(serverVoiceDetail)")
          .accessibilityHint(serverVoiceAccessibilityHint)
          .accessibilityIdentifier("profile.voice.server")
        }
        .padding(MoruPilotSpacing.sixteen)
        .profilePilotSurface(cornerRadius: MoruPilotSpacing.twelve)

        if let message = profileViewModel.voiceErrorMessage {
          Text(message)
            .profileFigmaTextStyle(.c1)
            .foregroundStyle(AppColor.coral300)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, MoruPilotSpacing.twenty)
      .padding(.top, MoruPilotSpacing.twenty)
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
    }
    .background(MoruPilotColor.canvas.ignoresSafeArea())
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text(ProfileCopy.moruVoice)
          .profileFigmaTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
      }
    }
    .tint(MoruPilotColor.textPrimary)
    .accessibilityIdentifier("profile.voice.settings")
  }

  private var selectedDeviceVoiceDisplayName: String {
    guard case .content(let content) = profileViewModel.state else {
      return "선택 정보 확인 중"
    }
    return content.profile.selectedVoice.displayName
  }

  private var canOpenServerVoiceSelection: Bool {
    !accountServerViewModel.isUpdatingVoice
      && accountServerViewModel.voiceState.value?.isEmpty == false
  }

  private var serverVoiceDetail: String {
    switch accountServerViewModel.voiceState {
    case .content, .loading(previous: .some), .failed(previous: .some):
      let previewStatus = accountServerViewModel.selectedVoiceHasPreview
        ? "미리듣기 가능"
        : "미리듣기 준비 중"
      return "\(accountServerViewModel.selectedVoiceDisplayName) · \(previewStatus)"
    case .empty:
      return "선택 가능한 서버 음성이 없어요"
    case .loading:
      return "서버 음성을 불러오는 중"
    case .failed:
      return "서버 음성을 확인하지 못했어요"
    case .unavailable:
      return "이 빌드에서 사용할 수 없어요"
    case .signedOut:
      return "로그인 후 사용할 수 있어요"
    }
  }

  private var serverVoiceAccessibilityHint: String {
    switch accountServerViewModel.voiceState {
    case .content, .loading(previous: .some), .failed(previous: .some):
      return "서버에 동기화된 루틴의 첫 안내 음성을 선택합니다. 완료·알림에는 기기 내장 음성이 사용됩니다."
    case .signedOut:
      return "로그인한 뒤 서버 음성을 선택할 수 있어요."
    case .unavailable:
      return "이 빌드에서는 서버 음성을 사용할 수 없어요."
    case .loading:
      return "서버 음성 목록을 불러오는 중이에요."
    case .empty:
      return "선택 가능한 서버 음성이 없어요."
    case .failed:
      return "서버 음성 목록을 확인하지 못했어요."
    }
  }

  private func voiceSettingsRow(
    title: String,
    detail: String
  ) -> some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
        Text(title)
          .profileFigmaTextStyle(.b4)
          .foregroundStyle(MoruPilotColor.textPrimary)
        Text(detail)
          .profileFigmaTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: MoruPilotSpacing.eight)
      MoruChevron(color: MoruPilotColor.textPrimary)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .contentShape(Rectangle())
  }
}

private struct MoruBrandBadge: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(AppColor.grayWhite)

      Image(AppImage.moruSplashBrand)
        .resizable()
        .scaledToFit()
        .frame(width: size * 2.36, height: size * 1.09)
        .offset(y: size * 0.34)
        .frame(width: size, height: size)
        .clipped()
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay {
      Circle()
        .stroke(AppColor.grayWhite.opacity(0.68), lineWidth: 1)
    }
    .accessibilityHidden(true)
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
    background(
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(MoruPilotColor.profileSurface)
    )
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    }
    .shadow(color: MoruPilotColor.shadow, radius: 7.5)
  }
}
