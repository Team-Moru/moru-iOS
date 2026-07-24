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
  let adaptsForAccessibility: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    title: String,
    message: String,
    primaryTitle: String,
    secondaryTitle: String,
    primaryAction: @escaping () -> Void,
    secondaryAction: @escaping () -> Void,
    adaptsForAccessibility: Bool = false
  ) {
    self.title = title
    self.message = message
    self.primaryTitle = primaryTitle
    self.secondaryTitle = secondaryTitle
    self.primaryAction = primaryAction
    self.secondaryAction = secondaryAction
    self.adaptsForAccessibility = adaptsForAccessibility
  }

  var body: some View {
    Group {
      if adaptsForAccessibility {
        adaptiveDialog
      } else {
        legacyDialog
      }
    }
  }

  private var legacyDialog: some View {
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
        legacyDialogActionButton(
          action: primaryAction,
          title: primaryTitle,
          color: AppColor.moruTextSecondary
        )
        Rectangle()
          .fill(AppColor.moruBorder)
          .frame(width: 1, height: 54)
        legacyDialogActionButton(
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

  private var adaptiveDialog: some View {
    VStack(spacing: AppSpacing.lg) {
      VStack(spacing: AppSpacing.md) {
        Text(title)
          .font(AppFont.pretendardSemiBold(size: 22, relativeTo: .title3))
          .foregroundStyle(AppColor.moruTextStrong)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)

        Text(message)
          .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
          .foregroundStyle(AppColor.moruTextSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, AppSpacing.lg)
      .padding(.top, AppSpacing.thirtySix)

      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 0) {
          adaptiveDialogActionButton(
            action: primaryAction,
            title: primaryTitle,
            color: AppColor.moruTextSecondary,
            width: 320
          )
          Rectangle()
            .fill(AppColor.moruBorder)
            .frame(width: 320, height: 1)
          adaptiveDialogActionButton(
            action: secondaryAction,
            title: secondaryTitle,
            color: AppColor.moruTextStrong,
            width: 320
          )
        }
      } else {
        HStack(spacing: 0) {
          adaptiveDialogActionButton(
            action: primaryAction,
            title: primaryTitle,
            color: AppColor.moruTextSecondary,
            width: 159.5
          )
          Rectangle()
            .fill(AppColor.moruBorder)
            .frame(width: 1, height: 54)
          adaptiveDialogActionButton(
            action: secondaryAction,
            title: secondaryTitle,
            color: AppColor.moruTextStrong,
            width: 159.5
          )
        }
        .frame(width: 320)
        .frame(minHeight: 54)
      }
    }
    .frame(width: 320)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
  }

  private func legacyDialogActionButton(
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

  private func adaptiveDialogActionButton(
    action: @escaping () -> Void,
    title: String,
    color: Color,
    width: CGFloat
  ) -> some View {
    SwiftUI.Button(action: action) {
      Text(title)
        .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
        .foregroundStyle(color)
        .frame(width: width)
        .frame(minHeight: 54)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
    }
    .buttonStyle(.plain)
  }
}
