
import SwiftUI

struct ProfileView: View {
  @State private var viewModel: ProfileViewModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var displayNameDraft = ""
  @State private var isDisplayNameEditorPresented = false
  @State private var isVoiceSelectionPresented = false
  @State private var isResetConfirmationPresented = false

  static let rootAccessibilityIdentifier = "profile.root"
  static let rootAccessibilityLabel = "마이"
  static let localResetDescription = "이 기기에 저장된 로컬 데이터를 초기화합니다."
  static let nameAccessibilityIdentifier = "profile.name"
  static let alarmStatusAccessibilityIdentifier = "profile.alarm.status"
  static let resetAccessibilityIdentifier = "profile.reset"
  static let voiceChooserAccessibilityIdentifier = "profile.voice.chooser"
  static let voiceSelectionListAccessibilityIdentifier = "voice.selection.list"
  static let notificationOnlyDowngradeDescription = "현재는 기기 알림으로 알려드려요."

  static func voicePreviewAccessibilityIdentifier(for voice: VoiceProfile) -> String {
    "voice.preview.\(voice.id)"
  }

  init(viewModel: ProfileViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.state {
        case .loading:
          ProfileLoadingView()
        case .content(let content):
          profileContent(content)
        case .failed(let message):
          ProfileFailureView(message: message, retryAction: viewModel.retryButtonDidTap)
        }
      }
      .background(AppColor.babyBlue50.ignoresSafeArea())
      .navigationTitle("마이")
      .navigationBarTitleDisplayMode(.large)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .accessibilityLabel(Self.rootAccessibilityLabel)
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
      ProfileDisplayNameEditor(
        displayName: $displayNameDraft,
        errorMessage: viewModel.displayNameErrorMessage,
        onSave: viewModel.displayNameSaveButtonDidTap
      )
    }
    .sheet(isPresented: $isVoiceSelectionPresented) {
      ProfileVoiceSelectionView(
        selectedVoiceID: selectedVoiceID,
        voiceErrorMessage: viewModel.voiceErrorMessage,
        isVoiceAvailable: viewModel.isVoiceAvailable,
        onSelect: { voice in
          let didSave = viewModel.voiceSelectionButtonDidTap(voice)
          if didSave {
            isVoiceSelectionPresented = false
          }
        },
        onPreview: viewModel.voicePreviewButtonDidTap,
        onDisappear: viewModel.voiceSelectionViewDidDisappear
      )
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
      Text("초기화하면 되돌릴 수 없어요.")
    }
  }

  private var selectedVoiceID: String? {
    guard case .content(let content) = viewModel.state else {
      return nil
    }

    return content.profile.selectedVoice.id
  }

  private func profileContent(_ content: ProfileSettingsLoadResult) -> some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        displayNameCard(content)
        voiceCard(content)
        alarmStatusCard
        resetCard
      }
      .padding(.horizontal, AppSpacing.screenHorizontal)
      .padding(.top, AppSpacing.lg)
      .padding(.bottom, AppSpacing.xxl)
    }
  }

  private func displayNameCard(_ content: ProfileSettingsLoadResult) -> some View {
    MoruCard(backgroundColor: AppColor.grayWhite) {
      Text("이름")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Button {
        displayNameDraft = content.profile.displayName
        isDisplayNameEditorPresented = true
      } label: {
        HStack(spacing: AppSpacing.sm) {
          Text(content.profile.displayName)
            .font(AppFont.body1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
            .lineLimit(2)
            .layoutPriority(1)

          Spacer()

          Image(systemName: "chevron.right")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("표시 이름, \(content.profile.displayName)")
      .accessibilityHint("표시 이름을 변경합니다.")
      .accessibilityIdentifier(Self.nameAccessibilityIdentifier)
    }
  }

  private func voiceCard(_ content: ProfileSettingsLoadResult) -> some View {
    MoruCard(backgroundColor: AppColor.grayWhite) {
      Text("목소리")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(Self.currentVoiceName(in: content))
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Button("목소리 선택") {
        isVoiceSelectionPresented = true
      }
      .buttonStyle(.borderedProminent)
      .tint(AppColor.moruBlue)
      .accessibilityHint("기기에서 사용할 수 있는 목소리를 선택합니다.")
      .accessibilityLabel("목소리 선택")
      .accessibilityIdentifier(Self.voiceChooserAccessibilityIdentifier)

      if let notice = viewModel.pendingVoiceNotice(in: content) {
        ProfileMessageCard(message: notice, isSuccess: true) {
          Button("확인", action: viewModel.voiceNoticeAcknowledgeButtonDidTap)
            .accessibilityHint("목소리 변경 안내를 확인합니다.")
        }
      }

      if let recoveryMessage = viewModel.voiceRecoveryMessage(in: content) {
        ProfileMessageCard(message: recoveryMessage, isSuccess: false) {
          if viewModel.shouldOfferVoiceResolutionRetry(in: content) {
            Button("다시 시도", action: viewModel.voiceResolutionRetryButtonDidTap)
              .accessibilityHint("목소리 설정을 다시 확인합니다.")
          }
        }
      }

      if let voiceErrorMessage = viewModel.voiceErrorMessage {
        ProfileMessageCard(message: voiceErrorMessage, isSuccess: false) {
          EmptyView()
        }
      }
    }
  }

  private var alarmStatusCard: some View {
    MoruCard(backgroundColor: AppColor.grayWhite) {
      Text("알람 상태")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(Self.notificationOnlyDowngradeDescription)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.notificationOnlyDowngradeDescription)

      Text(Self.alarmStatusMessage(for: viewModel.alarmStatus))
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(Self.alarmStatusAccessibilityIdentifier)
        .accessibilityLabel(Self.alarmStatusMessage(for: viewModel.alarmStatus))
        .accessibilityHint(Self.alarmStatusAccessibilityHint(for: viewModel.alarmStatus))

      switch viewModel.alarmStatus {
      case .configured:
        EmptyView()
      case .permissionOff:
        Button("설정 열기", action: viewModel.alarmSettingsButtonDidTap)
          .buttonStyle(.bordered)
          .accessibilityHint("기기 설정에서 알림 권한을 엽니다.")
          .accessibilityLabel("설정 열기")
      case .repairRequired:
        Button("다시 시도", action: viewModel.alarmRepairRetryButtonDidTap)
          .buttonStyle(.bordered)
          .accessibilityHint("알림 재예약을 다시 시도합니다.")
          .accessibilityLabel("다시 시도")
      case .unavailable:
        EmptyView()
      }
    }
  }

  private var resetCard: some View {
    MoruCard(backgroundColor: AppColor.grayWhite) {
      Text("로컬 데이터 초기화")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(Self.localResetDescription)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)

      Button("로컬 데이터 초기화", role: .destructive) {
        isResetConfirmationPresented = viewModel.resetButtonDidTap()
      }
      .buttonStyle(.bordered)
      .disabled(viewModel.isResetInProgress || !viewModel.isResetAvailable)
      .accessibilityHint(viewModel.resetAccessibilityHint)
      .accessibilityLabel("로컬 데이터 초기화")
      .accessibilityIdentifier(Self.resetAccessibilityIdentifier)

      if let resetAvailabilityMessage = viewModel.resetAvailabilityMessage {
        Text(resetAvailabilityMessage)
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      if viewModel.isResetInProgress {
        HStack(spacing: AppSpacing.xs) {
          ProgressView()
          Text("초기화하고 있어요.")
            .font(AppFont.label1NormalMedium)
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("로컬 데이터를 초기화하고 있어요.")
      }

      if let resetStatusMessage = viewModel.resetStatusMessage {
        ProfileMessageCard(
          message: resetStatusMessage,
          isSuccess: viewModel.didResetSucceed
        ) {
          EmptyView()
        }
      }
    }
  }

  static func currentVoiceName(in content: ProfileSettingsLoadResult) -> String {
    switch VoiceSelection(rawID: content.profile.selectedVoice.id) {
    case .available(let voice):
      return voice.displayName
    case .unavailable(let rawID):
      if rawID == VoiceProfile.moru.id {
        return "이전 버전 기본 목소리"
      }

      return "알 수 없는 목소리"
    }
  }
  static func alarmStatusMessage(for status: ProfileAlarmStatus) -> String {
    switch status {
    case .configured:
      "알람이 정상적으로 설정됐어요"
    case .permissionOff:
      "알람 권한이 꺼져 있어요"
    case .repairRequired:
      "알람을 다시 예약해야 해요"
    case .unavailable:
      "알람 상태를 확인할 수 없어요"
    }
  }
  static func alarmStatusAccessibilityHint(for status: ProfileAlarmStatus) -> String {
    switch status {
    case .configured:
      "기기 알림으로 알람 상태를 알려드려요."
    case .permissionOff:
      "기기 설정에서 알림 권한을 켜야 해요."
    case .repairRequired:
      "알림 재예약을 다시 시도할 수 있어요."
    case .unavailable:
      "알람 권한이 꺼졌다는 확인 정보가 아직 없어요."
    }
  }
}

private struct ProfileLoadingView: View {
  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      ProgressView()
      Text("프로필 설정을 불러오고 있어요.")
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("프로필 설정을 불러오고 있어요.")
  }
}

private struct ProfileFailureView: View {
  let message: String
  let retryAction: @MainActor () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.md) {
      Text(message)
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)

      Button("다시 시도", action: retryAction)
        .buttonStyle(.borderedProminent)
        .tint(AppColor.moruBlue)
        .accessibilityHint("프로필 설정을 다시 불러옵니다.")
    }
    .padding(AppSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ProfileDisplayNameEditor: View {
  @Binding var displayName: String
  let errorMessage: String?
  let onSave: @MainActor (String) -> Bool

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        Text("표시 이름")
          .font(AppFont.heading3SemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)

        TextField("표시 이름", text: $displayName)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("표시 이름")
          .accessibilityHint("앞뒤 공백을 제외한 1자에서 20자까지 입력할 수 있어요.")

        Text(
          "앞뒤 공백을 제외한 1자에서 20자까지 입력할 수 있어요.\n"
            + "이모지와 제어 문자는 사용할 수 없어요."
        )
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)

        if let errorMessage {
          Text(errorMessage)
            .font(AppFont.label1NormalMedium)
            .foregroundStyle(AppColor.coral300)
            .accessibilityLabel(errorMessage)
        }

        Spacer()
      }
      .padding(AppSpacing.screenHorizontal)
      .navigationTitle("이름 변경")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소", action: dismiss.callAsFunction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("저장") {
            if onSave(displayName) {
              dismiss()
            }
          }
          .accessibilityHint("표시 이름을 저장합니다.")
        }
      }
    }
  }
}

private struct ProfileVoiceSelectionView: View {
  let selectedVoiceID: String?
  let voiceErrorMessage: String?
  let isVoiceAvailable: @MainActor (VoiceProfile) -> Bool
  let onSelect: @MainActor (VoiceProfile) -> Void
  let onPreview: @MainActor (VoiceProfile) -> Void
  let onDisappear: @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    NavigationStack {
      List {
        ForEach(VoiceProfile.localVoices) { voice in
          voiceRow(voice)
        }

        if let voiceErrorMessage {
          Text(voiceErrorMessage)
            .font(AppFont.label1NormalMedium)
            .foregroundStyle(AppColor.coral300)
            .accessibilityLabel(voiceErrorMessage)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(ProfileView.voiceSelectionListAccessibilityIdentifier)
      .navigationTitle("목소리 선택")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("닫기", action: dismiss.callAsFunction)
            .accessibilityHint("목소리 선택을 닫습니다.")
        }
      }
    }
    .onDisappear(perform: onDisappear)
  }

  private func voiceRow(_ voice: VoiceProfile) -> some View {
    let isAvailable = isVoiceAvailable(voice)
    let isSelected = selectedVoiceID == voice.id

    return VStack(alignment: .leading, spacing: AppSpacing.sm) {
      HStack(spacing: AppSpacing.sm) {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(voice.displayName)
            .font(AppFont.label1NormalSemiBold)
            .foregroundStyle(AppColor.moruTextPrimary)
            .lineLimit(2)
            .layoutPriority(1)

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

      voiceActions(for: voice, isAvailable: isAvailable, isSelected: isSelected)
    }
    .padding(.vertical, AppSpacing.xxs)
  }

  @ViewBuilder
  private func voiceActions(
    for voice: VoiceProfile,
    isAvailable: Bool,
    isSelected: Bool
  ) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        voiceSelectionButton(for: voice, isAvailable: isAvailable, isSelected: isSelected)
        voicePreviewButton(for: voice, isAvailable: isAvailable)
      }
    } else {
      HStack(spacing: AppSpacing.sm) {
        voiceSelectionButton(for: voice, isAvailable: isAvailable, isSelected: isSelected)
        voicePreviewButton(for: voice, isAvailable: isAvailable)
      }
    }
  }

  private func voiceSelectionButton(
    for voice: VoiceProfile,
    isAvailable: Bool,
    isSelected: Bool
  ) -> some View {
    Button(isSelected ? "선택됨" : "선택") {
      onSelect(voice)
    }
    .buttonStyle(.borderedProminent)
    .tint(AppColor.moruBlue)
    .disabled(!isAvailable || isSelected)
    .accessibilityLabel("\(voice.displayName) 목소리 선택")
    .accessibilityHint(voiceSelectionHint(isAvailable: isAvailable, isSelected: isSelected))
  }

  private func voicePreviewButton(
    for voice: VoiceProfile,
    isAvailable: Bool
  ) -> some View {
    Button("미리 듣기") {
      onPreview(voice)
    }
    .buttonStyle(.bordered)
    .disabled(!isAvailable)
    .accessibilityIdentifier(ProfileView.voicePreviewAccessibilityIdentifier(for: voice))
    .accessibilityLabel("\(voice.displayName) 목소리 미리 듣기")
    .accessibilityHint(voicePreviewHint(isAvailable: isAvailable))
  }
  private func voiceSelectionHint(isAvailable: Bool, isSelected: Bool) -> String {
    if isSelected {
      return "현재 선택된 목소리예요."
    }

    return isAvailable
      ? "선택하면 이 목소리로 저장돼요."
      : "사용할 수 없는 목소리예요."
  }

  private func voicePreviewHint(isAvailable: Bool) -> String {
    isAvailable
      ? "선택을 저장하지 않고 목소리를 미리 들어요."
      : "사용할 수 없는 목소리예요."
  }
}

private struct ProfileMessageCard<Action: View>: View {
  let message: String
  let isSuccess: Bool
  @ViewBuilder let action: () -> Action

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text(message)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(isSuccess ? AppColor.moruTextPrimary : AppColor.coral300)

      action()
    }
    .padding(AppSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isSuccess ? AppColor.babyBlue100 : AppColor.moruOrangePale)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    .accessibilityElement(children: .contain)
  }
}
