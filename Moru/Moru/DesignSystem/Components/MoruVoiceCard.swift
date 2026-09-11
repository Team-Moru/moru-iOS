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
  @Binding private var isSelected: Bool

  init(name: String, description: String, isSelected: Bool) {
    self.name = name
    self.description = description
    self._isSelected = .constant(isSelected)
  }

  init(name: String, description: String, isSelected: Binding<Bool>) {
    self.name = name
    self.description = description
    self._isSelected = isSelected
  }

  var body: some View {
    Button {
      isSelected.toggle()
    } label: {
      HStack(spacing: AppSpacing.sm) {
        HStack(spacing: AppSpacing.sm) {
          MoruVoicePlayIcon()

          VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(name)
              .font(AppFont.pretendardSemiBold(size: 16))
              .foregroundStyle(MoruColor.textStrong)

            Text(description)
              .font(AppFont.pretendardMedium(size: 12))
              .foregroundStyle(MoruColor.textSecondary)
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
  }
}
