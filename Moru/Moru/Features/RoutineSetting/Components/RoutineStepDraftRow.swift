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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(alignment: .center, spacing: MoruPilotSpacing.twelve) {
      Text("\(order)")
        .routineManagementTextStyle(.c2)
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 24, height: 24)
        .background(MoruPilotColor.accentSoft)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
        TextField("예) 물 한 잔 마시기", text: $step.title, axis: .vertical)
          .routineManagementTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruPilotColor.textStrong)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

        Text("\(step.type.routineSettingTitle) - \(step.estimatedMinutes)분")
          .routineManagementTextStyle(.c2)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onDelete) {
        Image(systemName: "minus.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 22, height: 22)
          .foregroundStyle(MoruPilotColor.accent)
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(step.title) 항목 삭제")
    }
    .padding(.leading, MoruPilotSpacing.sixteen)
    .padding(.trailing, MoruPilotSpacing.eight)
    .padding(.vertical, MoruPilotSpacing.eight)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 62)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
    .overlay(
      RoundedRectangle(cornerRadius: MoruPilotRadius.card)
        .stroke(MoruPilotColor.border, lineWidth: 1)
    )
    .shadow(color: MoruPilotColor.shadow, radius: 7.5, x: 0, y: 0)
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
