//
//  MoruCard.swift
//  Moru
//

import SwiftUI

/// 콘텐츠 카드 표면. **유리가 아니다.**
///
/// 애플 가이드는 Liquid Glass를 콘텐츠 위에 떠 있는 계층 — 탭바·툴바·시트·버튼 —
/// 에만 쓰라고 못박는다. 목록·표·카드는 읽는 것이지 조작하는 것이 아니다.
/// 이 선을 넘으면 무엇이 누를 수 있는 것이고 무엇이 내용인지 구별이 무너진다.
///
///   "Liquid Glass is exclusively for the navigation layer that floats above
///    app content. Never apply to content itself (lists, tables, media)."
///
/// 한동안 카드를 전부 유리로 바꿔 봤다가 되돌렸다. 배경과 겉돌았고, 원인은
/// 배경이 아니라 계층이었다. 자세한 것은 `docs/LiquidGlassRules.md`.
///
/// 표면 색은 시스템 시맨틱 색이다 — 바탕이 `systemGroupedBackground`,
/// 카드가 `secondarySystemGroupedBackground`. 명도 관계를 우리가 정하지 않고
/// 애플이 정한 것을 받는다. 프로필 카드가 배경과 255 중 2밖에 차이나지 않아
/// 보이지 않던 문제가 이걸로 구조적으로 사라진다. 테두리도 필요 없다 —
/// 시스템 위계가 이미 카드를 세운다.
struct MoruCardModifier: ViewModifier {
  /// 색을 얹지 않은 기본 카드.
  static let plainTint = Color.clear

  let cornerRadius: CGFloat
  /// 상태나 강조를 나타낼 때만 색을 준다. 장식으로 쓰지 않는다 —
  /// 카드마다 색이 있으면 그 색이 아무 뜻도 갖지 못한다.
  let tint: Color

  func body(content: Content) -> some View {
    content
      .background(MoruColor.cardSurface, in: shape)
      .background(tint, in: shape)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }
}

extension View {
  /// - Parameter tint: 상태·강조를 담을 때만 넘긴다. 기본은 색 없음.
  func moruCard(
    cornerRadius: CGFloat = MoruRadius.card,
    tint: Color = MoruCardModifier.plainTint
  ) -> some View {
    modifier(MoruCardModifier(cornerRadius: cornerRadius, tint: tint))
  }
}
