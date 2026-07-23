//
//  MoruTextStyle.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

enum MoruTextWeight: String, CaseIterable, Sendable {
  case regular = "Pretendard-Regular"
  case medium = "Pretendard-Medium"
  case semiBold = "Pretendard-SemiBold"
  case bold = "Pretendard-Bold"
}

struct MoruTextStyle: Equatable, Sendable {
  let fontSize: CGFloat
  let lineHeight: CGFloat
  let weight: MoruTextWeight
  let relativeTextStyle: Font.TextStyle

  static let d1 = style(48, lineHeight: 67.2, weight: .bold, relativeTo: .largeTitle)
  static let d2 = style(36, lineHeight: 50.4, weight: .bold, relativeTo: .largeTitle)
  static let h1 = style(32, lineHeight: 44.8, weight: .semiBold, relativeTo: .title)
  static let h2 = style(28, lineHeight: 39.2, weight: .semiBold, relativeTo: .title2)
  static let h3 = style(24, lineHeight: 33.6, weight: .semiBold, relativeTo: .title3)
  static let b1 = style(22, lineHeight: 30.8, weight: .medium, relativeTo: .title3)
  static let b2 = style(20, lineHeight: 28, weight: .medium, relativeTo: .body)
  static let b3 = style(18, lineHeight: 25.2, weight: .medium, relativeTo: .body)
  static let b4 = style(16, lineHeight: 22.4, weight: .medium, relativeTo: .body)
  static let c1 = style(14, lineHeight: 19.6, weight: .medium, relativeTo: .caption)
  static let c2 = style(12, lineHeight: 16.8, weight: .medium, relativeTo: .caption2)

  func weight(_ weight: MoruTextWeight) -> MoruTextStyle {
    MoruTextStyle(
      fontSize: fontSize,
      lineHeight: lineHeight,
      weight: weight,
      relativeTextStyle: relativeTextStyle
    )
  }

  private static func style(
    _ fontSize: CGFloat,
    lineHeight: CGFloat,
    weight: MoruTextWeight,
    relativeTo relativeTextStyle: Font.TextStyle
  ) -> MoruTextStyle {
    MoruTextStyle(
      fontSize: fontSize,
      lineHeight: lineHeight,
      weight: weight,
      relativeTextStyle: relativeTextStyle
    )
  }
}

private struct MoruTextStyleModifier: ViewModifier {
  let style: MoruTextStyle

  @ScaledMetric private var scaledFontSize: CGFloat
  @ScaledMetric private var scaledLineHeight: CGFloat

  init(style: MoruTextStyle) {
    self.style = style
    _scaledFontSize = ScaledMetric(
      wrappedValue: style.fontSize,
      relativeTo: style.relativeTextStyle
    )
    _scaledLineHeight = ScaledMetric(
      wrappedValue: style.lineHeight,
      relativeTo: style.relativeTextStyle
    )
  }

  func body(content: Content) -> some View {
    content
      .font(.custom(style.weight.rawValue, size: scaledFontSize))
      .lineSpacing(max(0, scaledLineHeight - scaledFontSize))
  }
}

extension View {
  func moruTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(MoruTextStyleModifier(style: style))
  }
}
