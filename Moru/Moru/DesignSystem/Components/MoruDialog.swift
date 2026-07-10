//
//  MoruDialog.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruDialog: View {
  let title: String
  let message: String
  let primaryTitle: String
  let secondaryTitle: String
  let primaryAction: () -> Void
  let secondaryAction: () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.lg) {
      VStack(spacing: AppSpacing.md) {
        Text(title)
          .font(AppFont.pretendardSemiBold(size: 22))
          .foregroundStyle(AppColor.moruTextStrong)
          .multilineTextAlignment(.center)
          .frame(width: 320)

        Text(message)
          .font(AppFont.pretendardMedium(size: 16))
          .foregroundStyle(AppColor.moruTextSecondary)
          .multilineTextAlignment(.center)
          .frame(width: 320)
      }
      .frame(width: 320)
      .padding(.top, AppSpacing.thirtySix)

      HStack(spacing: 0) {
        dialogActionButton(
          action: primaryAction,
          title: primaryTitle,
          color: AppColor.moruTextSecondary
        )
        Rectangle()
          .fill(AppColor.moruBorder)
          .frame(width: 1, height: 54)
        dialogActionButton(
          action: secondaryAction,
          title: secondaryTitle,
          color: AppColor.moruTextStrong
        )
      }
      .frame(width: 320, height: 54)
    }
    .frame(width: 320)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
  }

  private func dialogActionButton(
    action: @escaping () -> Void,
    title: String,
    color: Color
  ) -> some View {
    SwiftUI.Button(action: action) {
      Text(title)
        .font(AppFont.pretendardSemiBold(size: 16))
        .foregroundStyle(color)
        .frame(width: 159.5, height: 54)
    }
    .buttonStyle(.plain)
  }
}
