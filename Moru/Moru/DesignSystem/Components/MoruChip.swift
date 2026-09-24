//
//  MoruChip.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

/// 고를 수 있는 칩. 누르는 것이라 유리를 쓴다.
/// 선택 상태만 틴트를 얹는다 — 틴트는 의미를 담을 때만 쓴다.
struct MoruChip: View {
  let title: String
  let isSelected: Bool

  var body: some View {
    Text(title)
      .font(AppFont.pretendardMedium(size: 14))
      .foregroundStyle(isSelected ? AppColor.grayWhite : MoruColor.textSecondary)
      .padding(.horizontal, AppSpacing.md)
      .frame(height: 28)
      .glassEffect(
        isSelected ? .regular.tint(MoruColor.accent) : .regular,
        in: .capsule
      )
  }
}
