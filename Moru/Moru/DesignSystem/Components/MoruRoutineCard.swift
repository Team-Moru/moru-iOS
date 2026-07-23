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
    Group {
      if isAddCard {
        HStack(spacing: AppSpacing.iconTextGap) {
          Spacer(minLength: 0)

          addIcon

          Text(title)
            .font(AppFont.label1NormalSemiBold)
            .foregroundStyle(AppColor.moruDisabled)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 0)
        }
      } else {
        HStack(spacing: AppSpacing.md) {
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
    }
    .padding(.horizontal, isAddCard ? AppSpacing.lg : AppSpacing.xl)
    .padding(.vertical, AppSpacing.md)
    .frame(maxWidth: .infinity)
    .frame(minHeight: minimumHeight)
    .background {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(backgroundColor)
        .shadow(
          color: shadowColor,
          radius: shadowRadius,
          x: 0,
          y: 0
        )
    }
  }

  private var addIcon: some View {
    Image(systemName: "plus")
      .resizable()
      .scaledToFit()
      .foregroundStyle(AppColor.moruDisabled)
      .frame(width: 18, height: 18)
  }

  private var cornerRadius: CGFloat {
    isAddCard ? AppRadius.routineCard : AppRadius.lg
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
      return dynamicTypeSize.isAccessibilitySize ? 104 : 64
    }

    return dynamicTypeSize.isAccessibilitySize ? 176 : 100
  }
}
