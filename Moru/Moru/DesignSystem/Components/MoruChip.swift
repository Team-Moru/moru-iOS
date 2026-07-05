//
//  MoruChip.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruChip: View {
  let title: String
  let isSelected: Bool

  var body: some View {
    Text(title)
      .font(AppFont.pretendardMedium(size: 14))
      .foregroundStyle(isSelected ? AppColor.grayWhite : AppColor.moruTextSecondary)
      .padding(.horizontal, AppSpacing.md)
      .frame(height: 28)
      .background(isSelected ? AppColor.orange350 : AppColor.moruSurfaceMuted)
      .clipShape(Capsule())
  }
}
