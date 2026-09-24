//
//  MoruCanvasBackground.swift
//  Moru
//

import SwiftUI

/// 화면 바탕.
///
/// 한동안 세로 그라데이션 위에 브랜드 글로우를 깔았다. 카드를 유리로 바꿨을 때
/// "굴절할 것이 없어 유리가 유리로 안 보인다"를 보정하려던 것이었는데, 애초에
/// 유리를 콘텐츠에 쓴 것이 잘못이었다. 콘텐츠에서 유리를 빼고 표면을 시스템
/// 시맨틱 색으로 옮기면서 장식도 함께 걷었다.
///
/// 시스템 위계(`systemGroupedBackground` → `secondarySystemGroupedBackground`)
/// 안에서는 바탕이 조용해야 카드가 선다. 탭바와 버튼의 유리도 이 위계를
/// 기준으로 자기를 그린다. 자세한 것은 `docs/LiquidGlassRules.md`.
struct MoruCanvasBackground: View {
  var body: some View {
    MoruColor.canvas.ignoresSafeArea()
  }
}

extension View {
  /// 화면 바탕을 깐다.
  func moruCanvas() -> some View {
    background(MoruCanvasBackground())
  }
}
