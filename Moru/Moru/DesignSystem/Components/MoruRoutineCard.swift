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
  let componentStyle: MoruPilotComponentStyle
  @Binding private var isActive: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    title: String,
    description: String = "",
    isActive: Bool = false,
    isAddCard: Bool = false,
    componentStyle: MoruPilotComponentStyle = .legacy
  ) {
    self.title = title
    self.description = description
    self.isAddCard = isAddCard
    self.componentStyle = componentStyle
    self._isActive = .constant(isActive)
  }

  init(
    title: String,
    description: String = "",
    isActive: Binding<Bool>,
    componentStyle: MoruPilotComponentStyle = .legacy
  ) {
    self.title = title
    self.description = description
    self.isAddCard = false
    self.componentStyle = componentStyle
    self._isActive = isActive
  }

  var body: some View {
    Group {
      if isAddCard {
        HStack(spacing: horizontalContentSpacing) {
          Spacer(minLength: 0)

          addIcon

          addCardTitle
            .foregroundStyle(AppColor.moruDisabled)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 0)
        }
      } else {
        routineCardContent
      }
    }
    .padding(.horizontal, horizontalPadding)
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

  @ViewBuilder
  private var routineCardContent: some View {
    if componentStyle == .figmaPilot && dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
        HStack(alignment: .top, spacing: horizontalContentSpacing) {
          MoruRoutineNoteIcon(isActive: isActive)
          routineLabels
        }

        HStack(spacing: MoruPilotSpacing.four) {
          Spacer(minLength: 0)
          MoruToggle(isOn: $isActive, componentStyle: componentStyle)
          MoruChevron(color: AppColor.moruTextSecondary)
        }
      }
    } else {
      HStack(spacing: horizontalContentSpacing) {
        MoruRoutineNoteIcon(isActive: isActive)
        routineLabels
        Spacer()
        MoruToggle(isOn: $isActive, componentStyle: componentStyle)
        MoruChevron(color: AppColor.moruTextSecondary)
      }
    }
  }

  private var routineLabels: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      constrainedRoutineTitle
        .foregroundStyle(routineTitleColor)

      constrainedRoutineDescription
        .foregroundStyle(routineDescriptionColor)
    }
  }

  @ViewBuilder
  private var constrainedRoutineTitle: some View {
    if componentStyle == .figmaPilot {
      routineTitle
        .fixedSize(horizontal: false, vertical: true)
    } else {
      routineTitle
    }
  }

  @ViewBuilder
  private var constrainedRoutineDescription: some View {
    if componentStyle == .figmaPilot {
      routineDescription
        .fixedSize(horizontal: false, vertical: true)
    } else {
      routineDescription
    }
  }

  @ViewBuilder
  private var addCardTitle: some View {
    if componentStyle == .figmaPilot {
      Text(title)
        .moruTextStyle(.b4.weight(.semiBold))
    } else {
      Text(title)
        .font(AppFont.label1NormalSemiBold)
    }
  }

  @ViewBuilder
  private var routineTitle: some View {
    if componentStyle == .figmaPilot {
      Text(title)
        .moruTextStyle(.b3.weight(.semiBold))
    } else {
      Text(title)
        .font(AppFont.pretendardSemiBold(size: 18))
    }
  }

  @ViewBuilder
  private var routineDescription: some View {
    if componentStyle == .figmaPilot {
      Text(description)
        .moruTextStyle(.c1)
    } else {
      Text(description)
        .font(AppFont.pretendardMedium(size: 14))
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
    guard componentStyle == .figmaPilot else {
      return isAddCard ? AppRadius.routineCard : AppRadius.lg
    }

    return MoruPilotRadius.largeCard
  }

  private var backgroundColor: Color {
    if isActive && !isAddCard {
      return componentStyle == .figmaPilot ? MoruPilotColor.accentTint : AppColor.orange150
    }

    return AppColor.grayWhite.opacity(0.2)
  }

  private var shadowColor: Color {
    if isActive && !isAddCard {
      return Color.clear
    }

    return componentStyle == .figmaPilot ? MoruPilotColor.shadow : AppColor.babyBlue150
  }

  private var shadowRadius: CGFloat {
    isActive && !isAddCard ? 0 : 7.5
  }

  private var routineTitleColor: Color {
    componentStyle == .figmaPilot
      ? MoruPilotColor.textStrong
      : AppColor.moruTextPrimary
  }

  private var routineDescriptionColor: Color {
    if isActive {
      return componentStyle == .figmaPilot
        ? MoruPilotColor.textTertiary
        : AppColor.moruTextTertiary
    }

    return AppColor.gray200
  }

  private var minimumHeight: CGFloat {
    if isAddCard {
      if componentStyle == .figmaPilot {
        return dynamicTypeSize.isAccessibilitySize ? 104 : 60
      }

      return dynamicTypeSize.isAccessibilitySize ? 104 : 64
    }

    return dynamicTypeSize.isAccessibilitySize ? 176 : 100
  }

  private var horizontalPadding: CGFloat {
    guard componentStyle == .figmaPilot else {
      return isAddCard ? AppSpacing.lg : AppSpacing.xl
    }

    return MoruPilotSpacing.twenty
  }

  private var horizontalContentSpacing: CGFloat {
    if componentStyle == .figmaPilot {
      return MoruPilotSpacing.ten
    }

    return isAddCard ? AppSpacing.iconTextGap : AppSpacing.md
  }
}
