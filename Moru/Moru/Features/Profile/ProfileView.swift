//
//  ProfileView.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import SwiftUI

struct ProfileView: View {
  static let rootAccessibilityIdentifier = "profile.root"

  @State private var viewModel: ProfileViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @State private var displayNameDraft = ""
  @State private var isDisplayNameEditorPresented = false
  @State private var isVoiceSelectionPresented = false
  @State private var isResetConfirmationPresented = false
  private let automaticallyLoads: Bool

  init(
    viewModel: ProfileViewModel,
    automaticallyLoads: Bool = true
  ) {
    _viewModel = State(initialValue: viewModel)
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
  }

  private func profileContent(_ content: ProfileSettingsLoadResult) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        profileTitle

        displayNameCard(content.profile)
          .padding(.top, MoruPilotSpacing.twelve)

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
