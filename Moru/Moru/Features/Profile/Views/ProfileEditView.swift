//
//  ProfileEditView.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct ProfileEditView: View {
  @Environment(\.dismiss) private var dismiss

  let viewModel: MyPageViewModel
  @State private var displayName: String = ""

  var body: some View {
    VStack(spacing: AppSpacing.xxl) {
      header

      VStack(alignment: .leading, spacing: AppSpacing.md) {
        MyPageSectionHeader(title: "프로필 이름")

        TextField("이름을 입력해 주세요", text: $displayName)
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)
          .padding(.horizontal, AppSpacing.lg)
          .frame(height: 58)
          .moruMyPageCardStyle()
      }

      if let errorMessage = viewModel.state.errorMessage {
        Text(errorMessage)
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.orange500)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Spacer()

      MoruButton("저장") {
        if viewModel.updateDisplayName(displayName) {
          dismiss()
        }
      }
    }
    .padding(.horizontal, AppSpacing.screenHorizontal)
    .padding(.bottom, AppSpacing.xxl)
    .background(pageBackground.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      displayName = viewModel.state.displayName
    }
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

      Text("프로필 수정")
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
  ProfileEditView(viewModel: MyPageViewModel(dependencies: .homePreview))
}
#endif
