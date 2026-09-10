//
//  MoruButton.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruButtonStyle {
  case primary
  case secondary
  case text
}

struct MoruButton: View {
  let title: String
  let style: MoruButtonStyle
  let isEnabled: Bool
  let action: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    _ title: String,
    style: MoruButtonStyle = .primary,
    isEnabled: Bool = true,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.style = style
    self.isEnabled = isEnabled
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .moruTextStyle(.b4.weight(.semiBold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, AppSpacing.buttonHorizontal)
        .padding(.vertical, verticalPadding)
        .frame(width: buttonWidth)
        .frame(minHeight: 54)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.45)
  }

  private var foregroundColor: Color {
    switch style {
    case .primary:
      MoruPilotColor.onCTA
    case .secondary:
      MoruPilotColor.textStrong
    case .text:
      AppColor.gray550
    }
  }

  private var backgroundColor: Color {
    switch style {
    case .primary:
      MoruPilotColor.ctaFill
    case .secondary:
      AppColor.grayWhite
    case .text:
      Color.clear
    }
  }

  private var buttonWidth: CGFloat? {
    switch style {
    case .primary:
      349
    case .secondary:
      353
    case .text:
      nil
    }
  }

  private var verticalPadding: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? AppSpacing.buttonVertical : 0
  }
}
