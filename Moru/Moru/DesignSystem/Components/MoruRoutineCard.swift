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

  init(
    title: String,
    description: String = "",
    isActive: Bool = false,
    isAddCard: Bool = false
  ) {
    self.title = title
    self.description = description
    self.isAddCard = isAddCard
    self._isActive = .constant(isActive)
  }

  init(
    title: String,
    description: String = "",
    isActive: Binding<Bool>
  ) {
    self.title = title
    self.description = description
    self.isAddCard = false
    self._isActive = isActive
  }

  var body: some View {
    Group {
      if isAddCard {
        HStack(spacing: MoruSpacing.ten) {
          Spacer(minLength: 0)

          addIcon

          Text(title)
            .moruTextStyle(.b4.weight(.semiBold))
            .foregroundStyle(MoruColor.disabled)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 0)
        }
      } else {
        routineCardContent
      }
    }
    .padding(.horizontal, MoruSpacing.twenty)
    .padding(.vertical, AppSpacing.md)
    .frame(maxWidth: .infinity)
    .frame(minHeight: minimumHeight)
    .moruCard(
      cornerRadius: MoruRadius.largeCard,
      tint: backgroundColor
    )
  }

  @ViewBuilder
  private var routineCardContent: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: MoruSpacing.twelve) {
        HStack(alignment: .top, spacing: MoruSpacing.ten) {
          MoruRoutineNoteIcon(isActive: isActive)
          routineLabels
        }

        HStack(spacing: MoruSpacing.four) {
          Spacer(minLength: 0)
          MoruToggle(isOn: $isActive)
          MoruChevron(color: MoruColor.textSecondary)
        }
      }
    } else {
      HStack(spacing: MoruSpacing.ten) {
        MoruRoutineNoteIcon(isActive: isActive)
        routineLabels
        Spacer()
        MoruToggle(isOn: $isActive)
        MoruChevron(color: MoruColor.textSecondary)
      }
    }
  }

  private var routineLabels: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      Text(title)
        .moruTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)

      Text(description)
        .moruTextStyle(.c1)
        .foregroundStyle(routineDescriptionColor)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var addIcon: some View {
    Image(systemName: "plus")
      .resizable()
      .scaledToFit()
      .foregroundStyle(MoruColor.disabled)
      .frame(width: 18, height: 18)
  }

  /// 유리의 틴트. 활성 루틴만 색을 얹고, 나머지는 기본 틴트로 둔다.
  private var backgroundColor: Color {
    if isActive && !isAddCard {
      return MoruColor.accentTint
    }

    return MoruCardModifier.plainTint
  }

  private var routineDescriptionColor: Color {
    isActive ? MoruColor.textTertiary : AppColor.gray200
  }

  private var minimumHeight: CGFloat {
    if isAddCard {
      return dynamicTypeSize.isAccessibilitySize ? 104 : 60
    }

    return dynamicTypeSize.isAccessibilitySize ? 176 : 100
  }
}
