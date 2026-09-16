//
//  HomeFigmaStyle.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

enum HomeCopy {
  /// 루틴을 막 끝낸 새벽 사용자에게 밤 인사를 하지 않기 위한 구간이다.
  static let dawnGreeting = "이른 아침이에요"
  static let morningGreeting = "좋은 아침이에요"
  static let afternoonGreeting = "오늘 하루도 힘내봐요"
  static let eveningGreeting = "편안한 밤 되세요!"
  static let skipped = "건너뜀"
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
    content.moruCard(cornerRadius: cornerRadius)
  }
}

extension View {
  func homePilotSurface(
    cornerRadius: CGFloat = MoruRadius.largeCard
  ) -> some View {
    modifier(HomePilotSurfaceModifier(cornerRadius: cornerRadius))
  }

}
