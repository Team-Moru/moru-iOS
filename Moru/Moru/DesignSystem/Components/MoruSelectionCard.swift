//
//  MoruSelectionCard.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruSelectionCard: View {
  let title: String
  let subtitle: String
  let isSelected: Bool
  let style: MoruSelectionCardStyle
  let icon: MoruSelectionCardIcon?
  let action: () -> Void

  init(
    title: String,
    subtitle: String,
    isSelected: Bool,
    style: MoruSelectionCardStyle = .list,
    icon: MoruSelectionCardIcon? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.isSelected = isSelected
    self.style = style
    self.icon = icon
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      content
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var content: some View {
    switch style {
    case .list:
      HStack(spacing: AppSpacing.md) {
        labelStack

        Spacer()

        MoruChevron()
      }
      .padding(.horizontal, AppSpacing.md)
      .frame(width: 353, height: 84)
      .background(AppColor.grayWhite)
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

    case .compact:
      HStack(spacing: AppSpacing.sm) {
        if let icon {
          MoruSelectionIcon(icon: icon)
        }

        labelStack
        Spacer()
      }
      .padding(.horizontal, AppSpacing.sm)
      .frame(width: 170, height: 104)
      .background(AppColor.grayWhite)
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
  }

  private var labelStack: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      Text(title)
        .font(
          style == .compact
            ? AppFont.pretendardSemiBold(size: 18)
            : AppFont.pretendardSemiBold(size: 20)
        )
        .foregroundStyle(AppColor.moruTextStrong)
        .lineLimit(1)
        .minimumScaleFactor(0.86)

      Text(subtitle)
        .font(
          style == .compact
            ? AppFont.pretendardMedium(size: 12)
            : AppFont.pretendardSemiBold(size: 14)
        )
        .foregroundStyle(style == .compact ? AppColor.moruTextSecondary : AppColor.moruTextBody)
        .lineLimit(style == .compact ? 2 : nil)
        .lineSpacing(0)
    }
  }
}

enum MoruSelectionCardStyle {
  case list
  case compact
}
