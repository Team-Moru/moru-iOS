//
//  MoruVoiceCard.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruVoiceCard: View {
  let name: String
  let description: String
  let isSelected: Bool
  /// 이미 선택된 카드를 다시 눌러도 호출된다. 카드에 재생 아이콘이 있으므로
  /// 미리듣기를 다시 들려주는 것이 사용자가 기대하는 동작이다.
  let action: () -> Void

  init(
    name: String,
    description: String,
    isSelected: Bool,
    action: @escaping () -> Void = {}
  ) {
    self.name = name
    self.description = description
    self.isSelected = isSelected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.sm) {
        HStack(spacing: AppSpacing.sm) {
          MoruVoicePlayIcon()

          VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(name)
              .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
              .foregroundStyle(MoruColor.textStrong)
              .fixedSize(horizontal: false, vertical: true)

            Text(description)
              .font(AppFont.pretendardMedium(size: 12, relativeTo: .caption))
              .foregroundStyle(MoruColor.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer()

        MoruCheckIcon(isOn: isSelected)
      }
      .padding(.horizontal, AppSpacing.md)
      .padding(.vertical, AppSpacing.sm)
      .frame(minHeight: 65)
      .background(AppColor.grayWhite)
      .overlay(
        RoundedRectangle(cornerRadius: AppRadius.sm)
          .stroke(MoruColor.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name), \(description)")
    .accessibilityHint("들어보고 이 목소리를 선택합니다.")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}
