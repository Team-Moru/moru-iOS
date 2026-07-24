//
//  RoutineSettingCard.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineSettingCard: View {
  let routine: RoutineSettingItemState
  @Binding var isActive: Bool
  let componentStyle: MoruPilotComponentStyle
  let onTap: () -> Void
  var onRetryAlarm: (() -> Void)? = nil
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    routine: RoutineSettingItemState,
    isActive: Binding<Bool>,
    componentStyle: MoruPilotComponentStyle = .legacy,
    onTap: @escaping () -> Void,
    onRetryAlarm: (() -> Void)? = nil
  ) {
    self.routine = routine
    _isActive = isActive
    self.componentStyle = componentStyle
    self.onTap = onTap
    self.onRetryAlarm = onRetryAlarm
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: verticalContentSpacing) {
          HStack(alignment: .top, spacing: horizontalContentSpacing) {
            MoruRoutineNoteIcon(isActive: isActive)
            routineDetails
          }

          HStack(spacing: trailingControlSpacing) {
            Spacer(minLength: 0)

            MoruToggle(
              isOn: $isActive,
              componentStyle: componentStyle
            )
              .accessibilityLabel("\(routine.title) 활성화")

            editButton
          }
        }
      } else {
        HStack(spacing: horizontalContentSpacing) {
          MoruRoutineNoteIcon(isActive: isActive)
          routineDetails

          HStack(spacing: trailingControlSpacing) {
            MoruToggle(
              isOn: $isActive,
              componentStyle: componentStyle
            )
              .accessibilityLabel("\(routine.title) 활성화")

            compactEditButton
          }
        }
      }
    }
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 176 : 100)
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

  private var routineDetails: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      routineTitle
      routineDescription

      if let alarmDeliveryText = routine.alarmDeliveryText {
        HStack(spacing: AppSpacing.xs) {
          Text(alarmDeliveryText)
            .font(AppFont.caption1Medium)
            .foregroundStyle(alarmStatusColor)
            .fixedSize(horizontal: false, vertical: true)

          if routine.needsAlarmAction, let onRetryAlarm {
            Button("재시도", action: onRetryAlarm)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.orange500)
              .buttonStyle(.plain)
              .accessibilityLabel("\(routine.title) 알람 예약 재시도")
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var alarmStatusColor: Color {
    routine.needsAlarmAction ? AppColor.orange500 : AppColor.moruTextTertiary
  }

  @ViewBuilder
  private var routineTitle: some View {
    if componentStyle == .figmaPilot {
      Text(routine.title)
        .routineListTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(routine.title)
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var routineDescription: some View {
    let description = "\(routine.stepCountText) · \(routine.estimatedDurationText)"

    if componentStyle == .figmaPilot {
      Text(description)
        .routineListTextStyle(.c1)
        .foregroundStyle(
          isActive ? MoruPilotColor.textTertiary : AppColor.gray200
        )
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(description)
        .font(AppFont.caption1Medium)
        .foregroundStyle(isActive ? AppColor.moruTextTertiary : AppColor.gray200)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var editButton: some View {
    Button(action: onTap) {
      Image(systemName: "chevron.right")
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(AppColor.moruTextSecondary)
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(routine.title) 편집")
  }

  private var compactEditButton: some View {
    Button(action: onTap) {
      MoruChevron(color: AppColor.moruTextSecondary)
    }
    .buttonStyle(.plain)
    .frame(width: 20, height: 44)
    .contentShape(Rectangle().inset(by: -AppSpacing.sm))
    .accessibilityLabel("\(routine.title) 편집")
  }

  private var horizontalPadding: CGFloat {
    componentStyle == .figmaPilot
      ? MoruPilotSpacing.twenty
      : AppSpacing.lg
  }

  private var horizontalContentSpacing: CGFloat {
    componentStyle == .figmaPilot
      ? MoruPilotSpacing.twelve
      : AppSpacing.xs
  }

  private var verticalContentSpacing: CGFloat {
    componentStyle == .figmaPilot
      ? MoruPilotSpacing.twelve
      : AppSpacing.md
  }

  private var trailingControlSpacing: CGFloat {
    componentStyle == .figmaPilot
      ? MoruPilotSpacing.four
      : AppSpacing.xs
  }

  private var cornerRadius: CGFloat {
    componentStyle == .figmaPilot
      ? MoruPilotRadius.largeCard
      : AppRadius.routineCard
  }

  private var backgroundColor: Color {
    if isActive {
      return componentStyle == .figmaPilot
        ? MoruPilotColor.accentTint
        : AppColor.orange150
    }

    return AppColor.grayWhite.opacity(0.2)
  }

  private var shadowColor: Color {
    guard !isActive else {
      return Color.clear
    }

    return componentStyle == .figmaPilot
      ? MoruPilotColor.shadow
      : AppColor.babyBlue150
  }

  private var shadowRadius: CGFloat {
    guard !isActive else {
      return 0
    }

    return componentStyle == .figmaPilot ? 7.5 : 10
  }
}

#if DEBUG
#Preview {
  RoutineSettingCard(
    routine: RoutineSettingItemState(
      id: UUID(),
      title: "활력 루틴",
      
      stepCountText: "4개 루틴",
      estimatedDurationText: "15분",
      isActive: true
    ),
    isActive: .constant(true),
    onTap: {}
  )
  .padding()
  .background(AppColor.babyBlue50)
}
#endif
