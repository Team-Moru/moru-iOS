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
    HStack(alignment: .center, spacing: MoruSpacing.twelve) {
      Text("\(order)")
        .moruTextStyle(.c2)
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 24, height: 24)
        .background(MoruColor.accentSoft)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: MoruSpacing.four) {
        TextField("예) 물 한 잔 마시기", text: $step.title, axis: .vertical)
          .moruTextStyle(.c1.weight(.semiBold))
          .foregroundStyle(MoruColor.textStrong)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

        Text("\(step.type.routineSettingTitle) - \(step.estimatedMinutes)분")
          .moruTextStyle(.c2)
          .foregroundStyle(MoruColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onDelete) {
        Image(systemName: "minus.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 22, height: 22)
          .foregroundStyle(MoruColor.accent)
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(step.title) 항목 삭제")
    }
    .padding(.leading, MoruSpacing.sixteen)
    .padding(.trailing, MoruSpacing.eight)
    .padding(.vertical, MoruSpacing.eight)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 62)
    .moruCard()
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
