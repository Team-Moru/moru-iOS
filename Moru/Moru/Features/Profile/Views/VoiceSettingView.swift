//
//  VoiceSettingView.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct VoiceSettingView: View {
  @Environment(\.dismiss) private var dismiss

  let viewModel: MyPageViewModel

  var body: some View {
    VStack(spacing: AppSpacing.xxl) {
      header

      VStack(alignment: .leading, spacing: AppSpacing.md) {
        MyPageSectionHeader(title: "모루 말투")

        ForEach(viewModel.state.availableVoices) { voice in
          Button {
            viewModel.selectVoice(voice)
          } label: {
            HStack(spacing: AppSpacing.sm) {
              MoruVoicePlayIcon()

              VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(voice.displayName)
                  .font(AppFont.heading3SemiBold)
                  .foregroundStyle(AppColor.moruTextPrimary)

                Text("아침 루틴을 안내하는 로컬 음성")
                  .font(AppFont.caption1Medium)
                  .foregroundStyle(AppColor.moruTextSecondary)
              }

              Spacer()

              MoruCheckIcon(isOn: viewModel.state.selectedVoice.id == voice.id)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 72)
            .moruMyPageCardStyle()
          }
          .buttonStyle(.plain)
        }
      }

      if let errorMessage = viewModel.state.errorMessage {
        Text(errorMessage)
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.orange500)
      }

      Spacer()
    }
    .padding(.horizontal, AppSpacing.screenHorizontal)
    .padding(.bottom, AppSpacing.xxl)
    .background(pageBackground.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }

  private var header: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Text("뒤로")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .buttonStyle(.plain)

      Spacer()

      Text("음성 설정")
        .font(AppFont.heading2Bold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Spacer()

      Color.clear
        .frame(width: 36, height: 1)
    }
    .padding(.top, AppSpacing.fiftySix)
  }

  private var pageBackground: LinearGradient {
    LinearGradient(
      stops: [
        Gradient.Stop(color: AppColor.gray100, location: 0),
        Gradient.Stop(color: AppColor.grayWhite, location: 1),
      ],
      startPoint: UnitPoint(x: 0.5, y: 0),
      endPoint: UnitPoint(x: 0.5, y: 1)
    )
  }
}

#if DEBUG
#Preview {
  VoiceSettingView(viewModel: MyPageViewModel(dependencies: .homePreview))
}
#endif
