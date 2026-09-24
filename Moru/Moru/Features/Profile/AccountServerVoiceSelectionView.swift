//
//  AccountServerVoiceSelectionView.swift
//  Moru
//

import SwiftUI

struct AccountServerVoiceSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var viewModel: AccountServerSettingsViewModel
  @Bindable var previewPlayer: ServerVoicePreviewPlayer
  let memberID: Int64

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: MoruSpacing.sixteen) {
          Text(
            "서버에 동기화된 루틴의 첫 안내 음성을 만들 때 "
              + "쓰는 선택입니다. 선택한 서버 음성의 루틴 시작·완료·알림 "
              + "음원을 미리 준비하며, "
              + "준비된 음성은 공통 샘플로 미리 들을 수 있습니다."
          )
          .moruTextStyle(.b4)
          .foregroundStyle(MoruColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

          if viewModel.voicePreparationState != .idle {
            Label(
              preparationStatusText,
              systemImage: preparationStatusImage
            )
            .moruTextStyle(.c1)
            .foregroundStyle(MoruColor.textSecondary)
            .accessibilityIdentifier(
              "profile.account.server-voice.preparation-status"
            )
          }

          voiceContent

          if let message = previewPlayer.errorMessage {
            Text(message)
              .moruTextStyle(.c1)
              .foregroundStyle(AppColor.coral300)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("profile.account.server-voice.preview-error")
          }

          if let message = viewModel.voiceUpdateErrorMessage {
            Text(message)
              .moruTextStyle(.c1)
              .foregroundStyle(AppColor.coral300)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("profile.account.server-voice.error")
          }
        }
        .padding(MoruSpacing.twenty)
      }
      .moruCanvas()
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
    .onDisappear {
      previewPlayer.stopPreview()
    }
  }

  private var preparationStatusText: String {
    switch viewModel.voicePreparationState {
    case .idle:
      ""
    case .preparing:
      "선택은 완료됐어요. 서버 음성을 준비하고 있어요."
    case .ready:
      "서버 음성 준비가 완료됐어요."
    case .retryScheduled:
      "다음 연결 시 서버 음성 준비를 다시 시도해요."
    }
  }

  private var preparationStatusImage: String {
    switch viewModel.voicePreparationState {
    case .idle, .preparing:
      "arrow.down.circle"
    case .ready:
      "checkmark.circle.fill"
    case .retryScheduled:
      "clock.arrow.circlepath"
    }
  }

  @ViewBuilder
  private var voiceContent: some View {
    if let voices = viewModel.voiceState.value, !voices.isEmpty {
      LazyVStack(spacing: MoruSpacing.eight) {
        ForEach(voices, id: \.ttsID) { voice in
          voiceButton(voice)
        }
      }
    } else {
      Text(voiceEmptyMessage)
        .moruTextStyle(.b4)
        .foregroundStyle(MoruColor.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 120)
    }
  }

  private func voiceButton(_ voice: ServerTTSVoice) -> some View {
    let isSelected = viewModel.selectedTTSID == voice.ttsID

    return VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
      HStack(spacing: MoruSpacing.twelve) {
        VStack(alignment: .leading, spacing: MoruSpacing.four) {
          HStack(spacing: MoruSpacing.eight) {
            Text(voice.displayName)
              .moruTextStyle(.b4.weight(.semiBold))
              .foregroundStyle(MoruColor.textStrong)
          }

          Text(voice.description)
            .moruTextStyle(.c1)
            .foregroundStyle(MoruColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: MoruSpacing.eight)

        if viewModel.updatingTTSID == voice.ttsID {
          ProgressView()
            .accessibilityLabel("서버 음성 변경 중")
        } else {
          Image(systemName: selectionImage(isSelected))
            .foregroundStyle(
              isSelected ? MoruColor.accent : MoruColor.textTertiary
            )
            .accessibilityHidden(true)
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: MoruSpacing.eight) {
          selectionButton(voice, isSelected: isSelected)
          previewButton(voice)
        }
        VStack(alignment: .leading, spacing: MoruSpacing.eight) {
          selectionButton(voice, isSelected: isSelected)
          previewButton(voice)
        }
      }
    }
    .padding(MoruSpacing.sixteen)
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    .homePilotSurface(cornerRadius: MoruRadius.card)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("profile.account.server-voice.\(voice.ttsID)")
  }

  private func selectionButton(
    _ voice: ServerTTSVoice,
    isSelected: Bool
  ) -> some View {
    Button(isSelected ? "선택됨" : "선택") {
      previewPlayer.stopPreview()
      Task {
        await viewModel.selectVoice(voice, memberID: memberID)
      }
    }
    .buttonStyle(.borderedProminent)
    .tint(MoruColor.accent)
    .disabled(viewModel.isUpdatingVoice || isSelected)
    .accessibilityLabel(
      "\(voice.displayName) 서버 생성 음성"
        + (isSelected ? ", 현재 선택됨" : " 선택")
    )
  }

  private func previewButton(_ voice: ServerTTSVoice) -> some View {
    Button(previewButtonTitle(for: voice)) {
      previewPlayer.togglePreview(voice, memberID: memberID)
    }
    .buttonStyle(.bordered)
    .tint(MoruColor.accent)
    .disabled(
      viewModel.isUpdatingVoice
        || !previewPlayer.isPreviewAvailable(for: voice)
    )
    .accessibilityLabel("\(voice.displayName) 음성 미리듣기")
    .accessibilityHint(
      previewPlayer.isPreviewAvailable(for: voice)
        ? "공통 샘플 음성을 재생합니다."
        : "미리듣기 음성을 준비하고 있어요."
    )
  }

  private func previewButtonTitle(for voice: ServerTTSVoice) -> String {
    if previewPlayer.isLoading(voice) {
      return "불러오는 중"
    }
    if previewPlayer.isPlaying(voice) {
      return "중지"
    }
    return voice.previewAudioURL == nil ? "준비 중" : "미리 듣기"
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
