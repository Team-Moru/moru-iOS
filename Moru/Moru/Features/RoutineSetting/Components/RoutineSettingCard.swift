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

  var body: some View {
    HStack(spacing: AppSpacing.md) {
      MoruRoutineNoteIcon(isActive: isActive)

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(routine.title)
          .font(AppFont.pretendardSemiBold(size: 18))
          .foregroundStyle(AppColor.moruTextPrimary)

        Text("\(routine.stepCountText) · \(routine.estimatedDurationText)")
          .font(AppFont.pretendardMedium(size: 13))
          .foregroundStyle(isActive ? AppColor.moruTextTertiary : AppColor.gray200)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      MoruToggle(isOn: $isActive)

      Button(action: onTap) {
        Image(systemName: "chevron.right")
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, AppSpacing.xl)
    .padding(.vertical, AppSpacing.md)
    .frame(maxWidth: .infinity)
    .frame(height: 100)
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
