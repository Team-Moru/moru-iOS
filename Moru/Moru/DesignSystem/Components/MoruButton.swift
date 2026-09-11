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

enum MoruButtonMetric {
  /// 주요·보조 CTA의 최소 높이. Figma 파일럿 기준 54pt.
  static let minimumHeight: CGFloat = 54
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
        .padding(.horizontal, MoruSpacing.twenty)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: style == .text ? nil : .infinity)
        .frame(minHeight: MoruButtonMetric.minimumHeight)
        .background(backgroundColor)
        .overlay(
          RoundedRectangle(cornerRadius: AppRadius.pill)
            .stroke(borderColor, lineWidth: style == .secondary ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.45)
  }

  private var foregroundColor: Color {
    switch style {
    case .primary:
      MoruColor.onCTA
    case .secondary:
      MoruColor.textStrong
    case .text:
      AppColor.gray550
    }
  }

  private var backgroundColor: Color {
    switch style {
    case .primary:
      MoruColor.ctaFill
    case .secondary:
      AppColor.grayWhite
    case .text:
      Color.clear
    }
  }

  private var borderColor: Color {
    style == .secondary ? MoruColor.border : Color.clear
  }

  private var verticalPadding: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? AppSpacing.buttonVertical : 0
  }
}
