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
        HStack(spacing: AppSpacing.md) {
          MoruRoutineNoteIcon(isActive: isActive)
          routineDetails
          MoruToggle(isOn: $isActive)
            .accessibilityLabel("\(routine.title) 활성화")
          editButton
        }
      }
    }
    .padding(.horizontal, AppSpacing.xl)
    .padding(.vertical, AppSpacing.md)
    .frame(maxWidth: .infinity)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 176 : 100)
    .background {
      RoundedRectangle(cornerRadius: AppRadius.lg)
        .fill(isActive ? AppColor.orange150 : AppColor.grayWhite.opacity(0.2))
        .shadow(
          color: AppColor.babyBlue150,
          radius: 10,
          x: 0,
          y: 0
        )
    }
  }

  private var routineDetails: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      Text(routine.title)
        .font(AppFont.pretendardSemiBold(size: 18))
        .foregroundStyle(AppColor.moruTextPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text("\(routine.stepCountText) · \(routine.estimatedDurationText)")
        .font(AppFont.pretendardMedium(size: 13))
        .foregroundStyle(isActive ? AppColor.moruTextTertiary : AppColor.gray200)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
