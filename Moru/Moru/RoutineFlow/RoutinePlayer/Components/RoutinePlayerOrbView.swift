//
//  RoutinePlayerOrbView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct RoutinePlayerOrbView: View {
  let levels: [CGFloat]
  let isListening: Bool
  let isPaused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    levels: [CGFloat] = [],
    isListening: Bool = false,
    isPaused: Bool = false
  ) {
    self.levels = levels
    self.isListening = isListening
    self.isPaused = isPaused
  }

  var body: some View {
    ZStack {
      Image(AppImage.moruImageHalo)
        .resizable()
        .scaledToFit()
        .scaleEffect(outerHaloScale)
        .opacity(outerHaloOpacity)
        .blur(radius: outerHaloBlur)

      Image(AppImage.moruImageHalo)
        .resizable()
        .scaledToFit()
        .scaleEffect(coreScale)
    }
    .frame(width: 254, height: 254)
    .animation(
      reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.56),
      value: visualIntensity
    )
    .accessibilityHidden(true)
  }

  var visualIntensity: CGFloat {
    guard isListening, !isPaused, !reduceMotion else {
      return .zero
    }

    guard !levels.isEmpty else {
      return .zero
    }

    let averageLevel = levels.reduce(.zero, +) / CGFloat(levels.count)
    let peakLevel = levels.max() ?? .zero
    let combinedLevel = averageLevel * 0.65 + peakLevel * 0.35
    let activeLevel = max(combinedLevel - 0.1, .zero) / 0.9
    return min(max(sqrt(activeLevel) * 1.1, .zero), 1)
  }

  private var coreScale: CGFloat {
    1 + visualIntensity * 0.24
  }

  private var outerHaloScale: CGFloat {
    1 + visualIntensity * 0.4
  }

  private var outerHaloOpacity: Double {
    Double(visualIntensity) * 0.8
  }

  private var outerHaloBlur: CGFloat {
    3 + visualIntensity * 14
  }
}
