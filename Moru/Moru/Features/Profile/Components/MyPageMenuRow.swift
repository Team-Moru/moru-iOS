//
//  MyPageMenuRow.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct MyPageMenuRow: View {
  let title: String
  var subtitle: String?
  var titleColor: Color = AppColor.moruTextPrimary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.sm) {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .font(AppFont.body1NormalMedium)
            .foregroundStyle(titleColor)

          if let subtitle {
            Text(subtitle)
              .font(AppFont.caption1Medium)
              .foregroundStyle(AppColor.moruTextSecondary)
          }
        }

        Spacer()

        MoruChevron(color: AppColor.moruTextBody)
      }
      .padding(.horizontal, AppSpacing.lg)
      .frame(height: subtitle == nil ? 61 : 67)
      .moruMyPageCardStyle()
    }
    .buttonStyle(.plain)
  }
}

#if DEBUG
#Preview {
  VStack(spacing: AppSpacing.md) {
    MyPageMenuRow(title: "모루 말투") {}

    MyPageMenuRow(
      title: "로컬 데이터 초기화",
      subtitle: "프로필, 루틴, 수행 기록을 기기에서 삭제합니다.",
      titleColor: AppColor.orange500
    ) {}
  }
  .padding(AppSpacing.screenHorizontal)
  .background(AppColor.gray100)
}
#endif
