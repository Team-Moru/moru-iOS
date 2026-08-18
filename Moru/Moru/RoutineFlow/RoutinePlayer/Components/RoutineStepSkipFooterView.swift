//
//  RoutineStepSkipFooterView.swift
//  Moru
//

import SwiftUI

enum RoutineStepFooterAction: String, CaseIterable {
  case skip

  var title: String {
    "건너뛰기"
  }
}

struct RoutineStepSkipFooterView: View {
  let horizontalPadding: CGFloat
  let onSkip: () -> Void

  var body: some View {
    Button(action: onSkip) {
      Text(RoutineStepFooterAction.skip.title)
        .font(
          AppFont.pretendardMedium(
            size: 14,
            relativeTo: .caption
          )
        )
        .foregroundStyle(AppColor.gray300)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, horizontalPadding)
  }
}
