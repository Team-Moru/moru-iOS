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
  let onTap: () -> Void
  var onRetryAlarm: (() -> Void)? = nil
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    routine: RoutineSettingItemState,
    isActive: Binding<Bool>,
    onTap: @escaping () -> Void,
    onRetryAlarm: (() -> Void)? = nil
  ) {
    self.routine = routine
    _isActive = isActive
    self.onTap = onTap
    self.onRetryAlarm = onRetryAlarm
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: MoruPilotSpacing.twelve) {
          HStack(alignment: .top, spacing: MoruPilotSpacing.twelve) {
            MoruRoutineNoteIcon(isActive: isActive)
            routineDetails
          }

          HStack(spacing: MoruPilotSpacing.four) {
            Spacer(minLength: 0)

            MoruToggle(isOn: $isActive)
              .accessibilityLabel("\(routine.title) 활성화")

            editButton
          }
        }
      } else {
        HStack(spacing: MoruPilotSpacing.twelve) {
          MoruRoutineNoteIcon(isActive: isActive)
          routineDetails

          HStack(spacing: MoruPilotSpacing.four) {
            MoruToggle(isOn: $isActive)
              .accessibilityLabel("\(routine.title) 활성화")

            compactEditButton
          }
        }
      }
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.vertical, MoruPilotSpacing.sixteen)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 176 : 100)
    .background {
      RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
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
      Text(routine.title)
        .routineListTextStyle(.b3.weight(.semiBold))
        .foregroundStyle(MoruPilotColor.textStrong)
        .fixedSize(horizontal: false, vertical: true)

      Text(
        RoutineManagementCopy.routineMetadata(
          stepCountText: routine.stepCountText,
          durationText: routine.estimatedDurationText
        )
      )
      .routineListTextStyle(.c1)
      .foregroundStyle(
        isActive ? MoruPilotColor.textTertiary : AppColor.gray200
      )
      .fixedSize(horizontal: false, vertical: true)

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
    routine.needsAlarmAction ? AppColor.orange500 : MoruPilotColor.textTertiary
  }

  private var editButton: some View {
    Button(action: onTap) {
      Image(systemName: "chevron.right")
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(routine.title) 편집")
  }

  private var compactEditButton: some View {
    Button(action: onTap) {
      MoruChevron(color: MoruPilotColor.textSecondary)
    }
    .buttonStyle(.plain)
    .frame(width: 20, height: 44)
    .contentShape(Rectangle().inset(by: -AppSpacing.sm))
    .accessibilityLabel("\(routine.title) 편집")
  }

  private var backgroundColor: Color {
    isActive ? MoruPilotColor.accentTint : AppColor.grayWhite.opacity(0.2)
  }

  private var shadowColor: Color {
    isActive ? Color.clear : MoruPilotColor.shadow
  }

  private var shadowRadius: CGFloat {
    isActive ? 0 : 7.5
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
