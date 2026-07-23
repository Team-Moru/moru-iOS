//
//  RoutineStepDraftRow.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct RoutineStepDraftRow: View {
  @Binding var step: RoutineStepDraftState
  let order: Int
  let onDelete: () -> Void
  let onTapCard: () -> Void

  var body: some View {
    HStack(spacing: AppSpacing.md) {
      Text("\(order)")
        .font(AppFont.pretendardSemiBold(size: 14))
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 24, height: 24)
        .background(AppColor.orange350)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(step.title)
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)
          .lineLimit(1)
          .frame(height: 24)

        Text("\(step.type.routineSettingTitle) - \(step.estimatedMinutes)분")
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }

      Spacer(minLength: AppSpacing.md)

      Button(action: onDelete) {
        Image(systemName: "minus.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 22, height: 22)
          .foregroundStyle(AppColor.orange350)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, AppSpacing.xl)
    .frame(height: 76)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    .overlay(
      RoundedRectangle(cornerRadius: AppRadius.sm)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    )
    .shadow(color: AppColor.babyBlue150, radius: 10, x: 0, y: 0)
    .contentShape(Rectangle())
    .onTapGesture {
      onTapCard()
    }
  }
}

#if DEBUG
#Preview {
  RoutineStepDraftRow(
    step: .constant(RoutineStepDraftState(title: "물 한 잔 마시기", estimatedMinutes: 1)),
    order: 1,
    onDelete: {},
    onTapCard: {}
  )
  .padding()
  .background(AppColor.babyBlue50)
}
#endif
