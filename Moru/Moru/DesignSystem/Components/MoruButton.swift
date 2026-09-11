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

/// Liquid Glass 버튼. primary는 `.glassProminent` + CTA 틴트, secondary는 `.glass`,
/// text는 `.plain`이다. 셋 다 서로 다른 `PrimitiveButtonStyle` 타입이라 하나의 modifier로
/// 전환할 수 없으므로 분기별로 완결된 버튼을 그린다.
struct MoruButton: View {
  let title: String
  let style: MoruButtonStyle
  let isEnabled: Bool
  /// 저장·전송처럼 결과를 기다리는 동안 스피너를 보여주고 입력을 막는다.
  let isLoading: Bool
  let action: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    _ title: String,
    style: MoruButtonStyle = .primary,
    isEnabled: Bool = true,
    isLoading: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.style = style
    self.isEnabled = isEnabled
    self.isLoading = isLoading
    self.action = action
  }

  var body: some View {
    switch style {
    case .primary:
      Button(action: action) {
        label
      }
      .buttonStyle(.glassProminent)
      .tint(MoruColor.ctaFill)
      .buttonBorderShape(.capsule)
      .controlSize(.extraLarge)
      .buttonSizing(.flexible)
      .frame(maxWidth: .infinity)
      .frame(minHeight: MoruButtonMetric.minimumHeight)
      .disabled(!isEnabled || isLoading)

    case .secondary:
      Button(action: action) {
        label
      }
      .buttonStyle(.glass)
      .buttonBorderShape(.capsule)
      .controlSize(.extraLarge)
      .buttonSizing(.flexible)
      .frame(maxWidth: .infinity)
      .frame(minHeight: MoruButtonMetric.minimumHeight)
      .disabled(!isEnabled || isLoading)

    case .text:
      Button(action: action) {
        label
      }
      .buttonStyle(.plain)
      .disabled(!isEnabled || isLoading)
    }
  }

  private var label: some View {
    HStack(spacing: MoruSpacing.eight) {
      if isLoading {
        ProgressView()
          .tint(foregroundColor)
      }

      Text(title)
        .moruTextStyle(.b4.weight(.semiBold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .foregroundStyle(foregroundColor)
    .padding(.vertical, verticalPadding)
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

  private var verticalPadding: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? AppSpacing.buttonVertical : 0
  }
}
