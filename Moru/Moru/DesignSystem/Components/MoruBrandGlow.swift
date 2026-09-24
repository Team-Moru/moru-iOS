//
//  MoruBrandGlow.swift
//  Moru
//

import SwiftUI

/// 인사말·완료 화면 뒤에 깔리는 브랜드 광원.
///
/// 예전에는 PNG 한 장(`moruGradientGlow`)이었다. 그 그림에는 주황 중심 둘레로
/// 회색-보라 링(#CBC7CD, 알파 0.46)이 들어 있었다. 푸른 바탕 위에서는 섞여
/// 보이지 않았지만, 바탕을 따뜻한 중립으로 옮기자 얼룩으로 드러났다.
///
/// 브랜드 주황 하나에서 퍼지도록 코드로 그린다. 바탕색이 무엇이든 회색이
/// 끼어들지 않고, 세기도 한곳에서 조절된다.
struct MoruBrandGlow: View {
  /// 광원의 지름.
  let diameter: CGFloat
  /// 중심의 세기.
  let intensity: Double

  init(diameter: CGFloat, intensity: Double = 0.5) {
    self.diameter = diameter
    self.intensity = intensity
  }

  var body: some View {
    RadialGradient(
      stops: [
        Gradient.Stop(color: MoruColor.accent.opacity(intensity), location: 0),
        Gradient.Stop(color: MoruColor.accent.opacity(intensity * 0.55), location: 0.38),
        Gradient.Stop(color: MoruColor.accent.opacity(intensity * 0.16), location: 0.68),
        Gradient.Stop(color: MoruColor.accent.opacity(0), location: 1),
      ],
      center: .center,
      startRadius: 0,
      endRadius: diameter / 2
    )
    .frame(width: diameter, height: diameter)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

#if DEBUG
#Preview("홈 바탕 위") {
  MoruBrandGlow(diameter: 360)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MoruColor.homeCanvasTop)
}
#endif
