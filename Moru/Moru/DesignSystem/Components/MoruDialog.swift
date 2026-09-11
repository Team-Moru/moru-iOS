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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    title: String,
    message: String,
    primaryTitle: String,
    secondaryTitle: String,
    primaryAction: @escaping () -> Void,
    secondaryAction: @escaping () -> Void
  ) {
    self.title = title
    self.message = message
    self.primaryTitle = primaryTitle
    self.secondaryTitle = secondaryTitle
    self.primaryAction = primaryAction
    self.secondaryAction = secondaryAction
  }

  var body: some View {
    VStack(spacing: AppSpacing.lg) {
      VStack(spacing: AppSpacing.md) {
        Text(title)
          .font(AppFont.pretendardSemiBold(size: 22, relativeTo: .title3))
          .foregroundStyle(MoruColor.textStrong)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)

        Text(message)
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(MoruColor.textSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, AppSpacing.lg)
      .padding(.top, AppSpacing.thirtySix)

      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 0) {
          actionButton(
            action: primaryAction,
            title: primaryTitle,
            color: MoruColor.textSecondary
          )
          Rectangle()
            .fill(MoruColor.border)
            .frame(height: 1)
          actionButton(
            action: secondaryAction,
            title: secondaryTitle,
            color: MoruColor.textStrong
          )
        }
      } else {
        HStack(spacing: 0) {
          actionButton(
            action: primaryAction,
            title: primaryTitle,
            color: MoruColor.textSecondary
          )
          Rectangle()
            .fill(MoruColor.border)
            .frame(width: 1, height: 54)
          actionButton(
            action: secondaryAction,
            title: secondaryTitle,
            color: MoruColor.textStrong
          )
        }
        .frame(minHeight: 54)
      }
    }
    .frame(maxWidth: .infinity)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    .padding(.horizontal, MoruSpacing.thirtySix)
  }

  private func actionButton(
    action: @escaping () -> Void,
    title: String,
    color: Color
  ) -> some View {
    SwiftUI.Button(action: action) {
      Text(title)
        .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
