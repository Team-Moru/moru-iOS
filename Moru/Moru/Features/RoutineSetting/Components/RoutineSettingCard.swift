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

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          HStack(alignment: .top, spacing: AppSpacing.md) {
            MoruRoutineNoteIcon(isActive: isActive)
            routineDetails
          }

          HStack(spacing: AppSpacing.md) {
            MoruToggle(isOn: $isActive)
              .accessibilityLabel("\(routine.title) 활성화")

            Spacer()
            editButton
          }
        }
      } else {
        HStack(spacing: AppSpacing.xs) {
          MoruRoutineNoteIcon(isActive: isActive)
          routineDetails
          MoruToggle(isOn: $isActive)
            .accessibilityLabel("\(routine.title) 활성화")
          compactEditButton
        }
      }
    }
    .padding(.horizontal, AppSpacing.lg)
    .padding(.vertical, AppSpacing.md)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 176 : 100)
    .background {
      RoundedRectangle(cornerRadius: AppRadius.routineCard)
        .fill(isActive ? AppColor.orange150 : AppColor.grayWhite.opacity(0.2))
        .shadow(
          color: isActive ? Color.clear : AppColor.babyBlue150,
          radius: isActive ? 0 : 10,
          x: 0,
          y: 0
        )
    }
  }

  private var routineDetails: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      Text(routine.title)
        .font(AppFont.body1NormalSemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text("\(routine.stepCountText) · \(routine.estimatedDurationText)")
        .font(AppFont.caption1Medium)
        .foregroundStyle(isActive ? AppColor.moruTextTertiary : AppColor.gray200)
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
    routine.needsAlarmAction ? AppColor.orange500 : AppColor.moruTextTertiary
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
