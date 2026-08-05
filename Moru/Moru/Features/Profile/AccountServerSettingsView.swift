//
//  AccountServerSettingsView.swift
//  Moru
//

import SwiftUI

struct AccountServerSettingsSummaryView: View {
  @Bindable var viewModel: AccountServerSettingsViewModel
  let memberID: Int64
  let onOpenVoiceSelection: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
      accountRow(
        title: "계정 닉네임",
        detail: profileDetail,
        systemImage: "person.text.rectangle"
      )
      accountRow(
        title: "계정 스트릭",
        detail: streakDetail,
        systemImage: "flame"
      )
      accountRow(
        title: "구독",
        detail: subscriptionDetail,
        systemImage: "checkmark.seal"
      )

      Button(action: onOpenVoiceSelection) {
        accountRow(
          title: "서버 생성 음성",
          detail: voiceDetail,
          systemImage: "waveform"
        )
      }
      .buttonStyle(.plain)
      .disabled(!canOpenVoiceSelection)
      .accessibilityHint(
        "기기 내 안내 음성과 별도입니다. 미리듣기는 제공되지 않습니다."
      )
      .accessibilityIdentifier("profile.account.server-voice")

      if hasLoadFailure {
        Button("계정 정보 다시 불러오기") {
          Task {
            await viewModel.load(memberID: memberID)
          }
        }
        .buttonStyle(.bordered)
        .tint(MoruPilotColor.accent)
        .accessibilityIdentifier("profile.account.server-retry")
      }
    }
    .accessibilityIdentifier("profile.account.server-settings")
  }

  private var profileDetail: String {
    if let profile = viewModel.profileState.value {
      let provider = loginTypeText(profile.loginType)
      return "\(profile.nickname) · \(provider)"
        + staleSuffix(for: viewModel.profileState)
    }
    return statePlaceholder(
      viewModel.profileState,
      failure: "계정 프로필 확인 불가"
    )
  }

  private var streakDetail: String {
    if let streak = viewModel.streakState.value {
      let completedThisWeek = streak.weeklyStatus.filter { $0 }.count
      return "현재 \(streak.currentDays)일 · 최고 \(streak.bestDays)일"
        + " · 이번 주 완료 \(completedThisWeek)일"
        + staleSuffix(for: viewModel.streakState)
    }
    return statePlaceholder(
      viewModel.streakState,
      failure: "계정 스트릭 확인 불가"
    )
  }

  private var subscriptionDetail: String {
    if let subscription = viewModel.subscriptionState.value {
      return subscriptionText(subscription)
        + staleSuffix(for: viewModel.subscriptionState)
    }
    return statePlaceholder(
      viewModel.subscriptionState,
      failure: "구독 정보 확인 불가"
    )
  }

  private var voiceDetail: String {
    switch viewModel.voiceState {
    case .content, .loading(previous: .some), .failed(previous: .some):
      return viewModel.selectedVoiceDisplayName
        + staleSuffix(for: viewModel.voiceState)
    case .empty:
      return "선택 가능한 서버 음성 없음"
    case .loading:
      return "서버 음성 불러오는 중"
    case .failed:
      return "서버 음성 확인 불가"
    case .unavailable:
      return "이 빌드에서 사용할 수 없음"
    case .signedOut:
      return "로그인 필요"
    }
  }

  private var canOpenVoiceSelection: Bool {
    guard !viewModel.isUpdatingVoice else {
      return false
    }
    return viewModel.voiceState.value?.isEmpty == false
  }

  private var hasLoadFailure: Bool {
    isFailed(viewModel.profileState)
      || isFailed(viewModel.streakState)
      || isFailed(viewModel.voiceState)
      || isFailed(viewModel.subscriptionState)
  }

  private func isFailed<Value>(
    _ state: AccountServerResourceState<Value>
  ) -> Bool {
    if case .failed = state {
      return true
    }
    return false
  }

  private func staleSuffix<Value>(
    for state: AccountServerResourceState<Value>
  ) -> String {
    switch state {
    case .loading:
      " · 업데이트 중"
    case .failed:
      " · 업데이트 실패"
    case .unavailable, .signedOut, .content, .empty:
      ""
    }
  }

  private func statePlaceholder<Value>(
    _ state: AccountServerResourceState<Value>,
    failure: String
  ) -> String {
    switch state {
    case .loading:
      "불러오는 중"
    case .failed:
      failure
    case .unavailable:
      "이 빌드에서 사용할 수 없음"
    case .signedOut:
      "로그인 필요"
    case .empty:
      "표시할 정보 없음"
    case .content:
      failure
    }
  }

  private func loginTypeText(_ loginType: ServerAccountLoginType) -> String {
    switch loginType {
    case .google:
      "Google"
    case .naver:
      "Naver"
    case .kakao:
      "Kakao"
    case .apple:
      "Apple"
    case .unknown:
      "로그인 방식 확인 불가"
    }
  }

  private func subscriptionText(
    _ subscription: ServerSubscriptionInfo
  ) -> String {
    switch subscription.plan {
    case .free:
      "FREE"
    case .pro:
      subscription.isActive ? "PRO · 활성" : "PRO · 비활성"
    case .unknown:
      "확인되지 않은 플랜"
    }
  }

  private func accountRow(
    title: String,
    detail: String,
    systemImage: String
  ) -> some View {
    HStack(spacing: MoruPilotSpacing.twelve) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MoruPilotColor.accent)
        .frame(width: 30)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
        Text(title)
          .moruPilotTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
        Text(detail)
          .moruPilotTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: MoruPilotSpacing.eight)
    }
    .padding(.horizontal, MoruPilotSpacing.sixteen)
    .padding(.vertical, MoruPilotSpacing.twelve)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    .accessibilityElement(children: .combine)
  }
}

struct AccountServerVoiceSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var viewModel: AccountServerSettingsViewModel
  let memberID: Int64

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.sixteen) {
          Text(
            "서버에서 루틴 음성을 만들 때 쓰는 선택입니다. "
              + "기기 내 안내 음성과 별도이며 미리듣기는 제공되지 않습니다."
          )
          .moruPilotTextStyle(.b4)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

          voiceContent

          if let message = viewModel.voiceUpdateErrorMessage {
            Text(message)
              .moruPilotTextStyle(.c1)
              .foregroundStyle(AppColor.coral300)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("profile.account.server-voice.error")
          }
        }
        .padding(MoruPilotSpacing.twenty)
      }
      .background(MoruPilotColor.canvas.ignoresSafeArea())
      .navigationTitle("서버 생성 음성")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("닫기") {
            dismiss()
          }
          .disabled(viewModel.isUpdatingVoice)
        }
      }
    }
    .interactiveDismissDisabled(viewModel.isUpdatingVoice)
    .accessibilityIdentifier("profile.account.server-voice.sheet")
  }

  @ViewBuilder
  private var voiceContent: some View {
    if let voices = viewModel.voiceState.value, !voices.isEmpty {
      LazyVStack(spacing: MoruPilotSpacing.eight) {
        ForEach(voices, id: \.ttsID) { voice in
          voiceButton(voice)
        }
      }
    } else {
      Text(voiceEmptyMessage)
        .moruPilotTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 120)
    }
  }

  private func voiceButton(_ voice: ServerTTSVoice) -> some View {
    let isSelected = viewModel.selectedTTSID == voice.ttsID
    let isLocked = voice.isProOnly
      && !viewModel.hasActiveProSubscription

    return Button {
      Task {
        await viewModel.selectVoice(voice, memberID: memberID)
      }
    } label: {
      HStack(spacing: MoruPilotSpacing.twelve) {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
          HStack(spacing: MoruPilotSpacing.eight) {
            Text(voice.displayName)
              .moruPilotTextStyle(.b4.weight(.semiBold))
              .foregroundStyle(MoruPilotColor.textStrong)

            if voice.isProOnly {
              Text("PRO")
                .moruPilotTextStyle(.c2.weight(.semiBold))
                .foregroundStyle(MoruPilotColor.accent)
            }
          }

          Text(voice.description)
            .moruPilotTextStyle(.c1)
            .foregroundStyle(MoruPilotColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: MoruPilotSpacing.eight)

        if viewModel.updatingTTSID == voice.ttsID {
          ProgressView()
            .accessibilityLabel("서버 음성 변경 중")
        } else {
          Image(systemName: isLocked ? "lock.fill" : selectionImage(isSelected))
            .foregroundStyle(
              isSelected ? MoruPilotColor.accent : MoruPilotColor.textTertiary
            )
            .accessibilityHidden(true)
        }
      }
      .padding(MoruPilotSpacing.sixteen)
      .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
      .homePilotSurface(cornerRadius: MoruPilotSpacing.sixteen)
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isUpdatingVoice || isLocked)
    .accessibilityLabel(
      "\(voice.displayName), \(voice.description)"
        + (voice.isProOnly ? ", PRO 전용" : "")
        + (isSelected ? ", 선택됨" : "")
    )
    .accessibilityHint(
      isLocked
        ? "활성 PRO 구독 확인이 필요합니다."
        : "서버 생성 음성으로 선택합니다."
    )
  }

  private var voiceEmptyMessage: String {
    switch viewModel.voiceState {
    case .loading:
      "서버 음성을 불러오고 있어요."
    case .empty:
      "선택 가능한 서버 음성이 없어요."
    case .failed:
      "서버 음성을 확인하지 못했어요."
    case .unavailable:
      "이 빌드에서는 서버 음성을 사용할 수 없어요."
    case .signedOut:
      "로그인 후 서버 음성을 선택할 수 있어요."
    case .content:
      "선택 가능한 서버 음성이 없어요."
    }
  }

  private func selectionImage(_ isSelected: Bool) -> String {
    isSelected ? "checkmark.circle.fill" : "circle"
  }
}
