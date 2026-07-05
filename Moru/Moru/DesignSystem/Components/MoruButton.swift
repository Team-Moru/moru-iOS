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
        .font(AppFont.pretendardSemiBold(size: 16))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, AppSpacing.buttonHorizontal)
        .padding(.vertical, AppSpacing.buttonVertical)
        .frame(width: buttonWidth)
        .background(backgroundColor)
        .overlay(
          RoundedRectangle(cornerRadius: AppRadius.pill)
            .stroke(borderColor, lineWidth: borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
        .shadow(
          color: shadowColor,
          radius: shadowRadius,
          x: 0,
          y: shadowY
        )
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.45)
  }

  private var foregroundColor: Color {
    switch style {
    case .primary:
      AppColor.grayWhite
    case .secondary:
      AppColor.moruTextPrimary
    case .text:
      AppColor.gray550
    }
  }

  private var backgroundColor: Color {
    switch style {
    case .primary:
      AppColor.orange350
    case .secondary:
      AppColor.grayWhite
    case .text:
      Color.clear
    }
  }

  private var borderColor: Color {
    switch style {
    case .primary, .text:
      Color.clear
    case .secondary:
      Color.clear
    }
  }

  private var borderWidth: CGFloat {
    0
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

  private var shadowColor: Color {
    style == .primary ? AppColor.grayBlack.opacity(0.25) : Color.clear
  }

  private var shadowRadius: CGFloat {
    style == .primary ? 4 : 0
  }

  private var shadowY: CGFloat {
    style == .primary ? 4 : 0
  }
}
