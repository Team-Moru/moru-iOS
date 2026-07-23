//
//  MoruRoutineCard.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruRoutineCard: View {
  let title: String
  let description: String
  let isAddCard: Bool
  @Binding private var isActive: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(title: String, description: String = "", isActive: Bool = false, isAddCard: Bool = false) {
    self.title = title
    self.description = description
    self.isAddCard = isAddCard
    self._isActive = .constant(isActive)
  }

  init(title: String, description: String = "", isActive: Binding<Bool>) {
    self.title = title
    self.description = description
    self.isAddCard = false
    self._isActive = isActive
  }

  var body: some View {
    HStack(spacing: isAddCard ? AppSpacing.iconTextGap : AppSpacing.md) {
      if isAddCard {
        Image(systemName: "plus")
          .resizable()
          .scaledToFit()
          .foregroundStyle(AppColor.moruDisabled)
          .frame(width: 22, height: 22)

        Text(title)
          .font(AppFont.pretendardSemiBold(size: 16))
          .foregroundStyle(AppColor.moruDisabled)
          .fixedSize(horizontal: false, vertical: true)

        Spacer()
      } else {
        MoruRoutineNoteIcon(isActive: isActive)

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .font(AppFont.pretendardSemiBold(size: 18))
            .foregroundStyle(AppColor.moruTextPrimary)

          Text(description)
            .font(AppFont.pretendardMedium(size: 14))
            .foregroundStyle(isActive ? AppColor.moruTextTertiary : AppColor.gray200)
        }

        Spacer()

        MoruToggle(isOn: $isActive)
        MoruChevron(color: AppColor.moruTextSecondary)
      }
    }
    .padding(.horizontal, AppSpacing.xl)
    .padding(.vertical, AppSpacing.md)
    .frame(maxWidth: .infinity)
    .frame(minHeight: minimumHeight)
    .background {
      RoundedRectangle(cornerRadius: AppRadius.lg)
        .fill(backgroundColor)
        .shadow(
          color: shadowColor,
          radius: shadowRadius,
          x: 0,
          y: 0
        )
    }
  }

  private var backgroundColor: Color {
    if isActive && !isAddCard {
      return AppColor.orange150
    }

    return AppColor.grayWhite.opacity(0.2)
  }

  private var shadowColor: Color {
    isActive && !isAddCard ? Color.clear : AppColor.babyBlue150
  }

  private var shadowRadius: CGFloat {
    isActive && !isAddCard ? 0 : 7.5
  }

  private var minimumHeight: CGFloat {
    if isAddCard {
      return dynamicTypeSize.isAccessibilitySize ? 104 : 60
    }

    return dynamicTypeSize.isAccessibilitySize ? 176 : 100
  }
}
