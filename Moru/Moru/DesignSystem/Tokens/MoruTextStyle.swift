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

/// Figma 타이포 스케일을 적용하는 단일 모디파이어.
///
/// 정책: xxxLarge까지는 Figma의 140% 행간을 정확히 적용하고, 접근성 글자 크기
/// (AX1~AX5)에서는 시스템 자연 행간으로 돌아가 긴 한국어 줄바꿈이 잘리지 않게 한다.
private struct MoruTextStyleModifier: ViewModifier {
  let style: MoruTextStyle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric private var scaledLineHeight: CGFloat

  init(style: MoruTextStyle) {
    self.style = style
    _scaledLineHeight = ScaledMetric(
      wrappedValue: style.lineHeight,
      relativeTo: style.relativeTextStyle
    )
  }

  private var lineHeight: AttributedString.LineHeight? {
    guard !dynamicTypeSize.isAccessibilitySize else {
      return nil
    }

    return .exact(points: scaledLineHeight)
  }

  func body(content: Content) -> some View {
    content
      .font(
        .custom(
          style.weight.rawValue,
          size: style.fontSize,
          relativeTo: style.relativeTextStyle
        )
      )
      .lineHeight(lineHeight)
  }
}

extension View {
  func moruTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(MoruTextStyleModifier(style: style))
  }
}
