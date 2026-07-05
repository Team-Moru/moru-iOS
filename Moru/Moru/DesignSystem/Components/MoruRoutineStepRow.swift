//
//  MoruRoutineStepRow.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruRoutineStepRow: View {
  let index: Int
  let title: String
  let subtitle: String
  let isCompleted: Bool
  let showsSelectControl: Bool
  let selectStyle: MoruSelectControlStyle
  let onSelect: (() -> Void)?

  init(
    index: Int,
    title: String,
    subtitle: String,
    isCompleted: Bool = false,
    showsSelectControl: Bool = true,
    selectStyle: MoruSelectControlStyle = .minus,
    onSelect: (() -> Void)? = nil
  ) {
    self.index = index
    self.title = title
    self.subtitle = subtitle
    self.isCompleted = isCompleted
    self.showsSelectControl = showsSelectControl
    self.selectStyle = selectStyle
    self.onSelect = onSelect
  }

  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      HStack(spacing: AppSpacing.sm) {
        ZStack {
          Circle()
            .fill(AppColor.orange300)
            .frame(width: 20, height: 20)

          Text("\(index)")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.grayWhite)
        }

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .font(AppFont.pretendardSemiBold(size: 14))
            .foregroundStyle(AppColor.moruTextPrimary)

          Text(subtitle)
            .font(AppFont.pretendardMedium(size: 12))
            .foregroundStyle(AppColor.moruTextSecondary)
        }
      }

      Spacer()

      if showsSelectControl {
        MoruSelectControl(style: selectStyle, action: onSelect ?? {})
      }
    }
    .padding(.horizontal, AppSpacing.md)
    .padding(.vertical, AppSpacing.sm)
    .frame(maxWidth: 353, minHeight: 63)
    .background(AppColor.grayWhite)
    .overlay(
      RoundedRectangle(cornerRadius: AppRadius.md)
        .stroke(AppColor.moruBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
  }
}

#Preview("Frame 2147239112") {
  MoruRoutineStepRow(
    index: 1,
    title: "잠자리 정리하기",
    subtitle: "확인형 - 1분"
  )
  .padding(AppSpacing.screenHorizontal)
  .background(AppColor.gray100)
}
