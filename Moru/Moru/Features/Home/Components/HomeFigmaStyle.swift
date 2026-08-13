//
//  HomeFigmaStyle.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

enum HomeCopy {
  static let morningGreeting = "좋은 아침이에요"
  static let afternoonGreeting = "좋은 오후예요"
  static let eveningGreeting = "좋은 저녁이에요"
  static let greeting = "\(morningGreeting),"
  static let greetingWithoutName = morningGreeting
  static let encouragement = "오늘도 작은 루틴이 큰 변화를 만들어요."
  static let todayRoutine = "오늘의 루틴"
  static let currentRoutine = "현재 사용 중인 루틴"
  static let activeRoutines = "활성 루틴"
}

enum HomeFigmaLayout {
  static let weatherCardHeight: CGFloat = 84
  static let actionableWeatherCardHeight: CGFloat = 104
}

struct HomePilotSurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(AppColor.grayWhite.opacity(0.2))
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .shadow(color: MoruPilotColor.shadow, radius: 15)
  }
}

struct MoruPilotTextStyleModifier: ViewModifier {
  let style: MoruTextStyle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @ViewBuilder
  func body(content: Content) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      content.font(
        .custom(
          style.weight.rawValue,
          size: style.fontSize,
          relativeTo: style.relativeTextStyle
        )
      )
    } else {
      content.moruTextStyle(style)
    }
  }
}

extension View {
  func homePilotSurface(
    cornerRadius: CGFloat = MoruPilotRadius.largeCard
  ) -> some View {
    modifier(HomePilotSurfaceModifier(cornerRadius: cornerRadius))
  }

  func homeFigmaTextStyle(_ style: MoruTextStyle) -> some View {
    moruPilotTextStyle(style)
  }

  func moruPilotTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(MoruPilotTextStyleModifier(style: style))
  }
}
