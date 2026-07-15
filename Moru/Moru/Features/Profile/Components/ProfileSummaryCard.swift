//
//  ProfileSummaryCard.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct ProfileSummaryCard: View {
  let displayName: String
  var action: () -> Void = {}

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.lg) {
        Circle()
          .fill(AppColor.orange350)
          .frame(width: 58.58216, height: 58.58216)

        VStack(alignment: .leading, spacing: AppSpacing.none) {
          Text(displayName)
            .font(AppFont.heading2SemiBold)
            .foregroundStyle(AppColor.moruTextStrong)

          Text("Apple로 로그인")
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(AppColor.gray500)
        }
        .frame(width: 126.64085, alignment: .topLeading)

        Spacer()
      }
      .padding(.horizontal, AppSpacing.lg)
      .padding(.vertical, AppSpacing.lg)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .moruMyPageCardStyle()
    }
    .buttonStyle(.plain)
  }
}

#if DEBUG
#Preview {
  ProfileSummaryCard(displayName: "김다인") {}
    .padding(AppSpacing.screenHorizontal)
    .background(AppColor.gray100)
}
#endif
