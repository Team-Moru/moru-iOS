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
  @Environment(\.scenePhase) private var scenePhase
  @State private var displayNameDraft = ""
  @State private var isDisplayNameEditorPresented = false
  @State private var isVoiceSelectionPresented = false
  @State private var isResetConfirmationPresented = false

  init(viewModel: ProfileViewModel) {
    _viewModel = State(initialValue: viewModel)
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
      .background(AppColor.babyBlue50.ignoresSafeArea())
      .navigationTitle("마이")
      .navigationBarTitleDisplayMode(.large)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .task {
      viewModel.loadProfileSettings()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }

      viewModel.refreshAlarmStatus()
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
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        displayNameCard(content.profile)
        voiceCard(content)
        alarmStatusCard
        resetCard
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.lg)
      .padding(.bottom, AppSpacing.xxl)
    }
  }

  private func displayNameCard(_ profile: LocalProfile) -> some View {
    MoruCard {
      Text("이름")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Button {
        displayNameDraft = profile.displayName
        isDisplayNameEditorPresented = true
      } label: {
        HStack(spacing: AppSpacing.sm) {
          Text(profile.displayName)
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
            .lineLimit(2)
            .layoutPriority(1)

          Spacer()
          MoruChevron(color: AppColor.moruTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("표시 이름, \(profile.displayName)")
      .accessibilityHint("표시 이름을 변경합니다.")
      .accessibilityIdentifier("profile.name")
    }
  }

  private func voiceCard(_ content: ProfileSettingsLoadResult) -> some View {
    MoruCard {
      Text("목소리")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(content.profile.selectedVoice.displayName)
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Button("목소리 선택") {
        isVoiceSelectionPresented = true
      }
      .buttonStyle(.borderedProminent)
      .tint(AppColor.moruBlue)
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
    MoruCard {
      Text("알람 상태")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(alarmStatusMessage)
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .accessibilityIdentifier("profile.alarm.status")

      switch viewModel.alarmStatus {
      case .configured, .unavailable:
        EmptyView()
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
      }
    }
  }

  private var resetCard: some View {
    MoruCard {
      Text("로컬 데이터 초기화")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text("이 기기에 저장된 로컬 데이터를 초기화합니다.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)

      Button("로컬 데이터 초기화", role: .destructive) {
        isResetConfirmationPresented = true
      }
      .buttonStyle(.bordered)
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
      "AlarmKit 권한이 허용되어 있어요."
    case .permissionNotDetermined:
      "알람 권한을 아직 확인하지 않았어요."
    case .permissionOff:
      "알람 권한이 꺼져 있어요."
    case .unavailable:
      "알람 상태를 확인할 수 없어요."
    }
  }

  private var loadingView: some View {
    VStack(spacing: AppSpacing.sm) {
      ProgressView()
      Text("프로필 설정을 불러오고 있어요.")
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func failureView(_ message: String) -> some View {
    VStack(spacing: AppSpacing.md) {
      Text(message)
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)
      Button("다시 시도", action: viewModel.retryButtonDidTap)
        .buttonStyle(.borderedProminent)
        .tint(AppColor.moruBlue)
    }
    .padding(AppSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      .navigationTitle("목소리 선택")
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
          Text(isAvailable ? "사용 가능" : "목소리 설치 필요")
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
      .font(AppFont.label1NormalMedium)
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }
}
