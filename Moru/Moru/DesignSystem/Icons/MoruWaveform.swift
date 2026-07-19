//
//  MoruWaveform.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruWaveform: View {
  private let levels: [CGFloat]
  private let usesReducedMotion: Bool

  private enum Metric {
    static let barCount = 20
    static let barWidth: CGFloat = 4.6667
    static let barSpacing: CGFloat = 4.6667
    static let minimumHeight: CGFloat = 8
    static let maximumHeight: CGFloat = 24
    static let contrastGain: CGFloat = 1.8
  }

  init(levels: [CGFloat] = [], usesReducedMotion: Bool = false) {
    self.levels = levels
    self.usesReducedMotion = usesReducedMotion
  }

  var body: some View {
    HStack(alignment: .center, spacing: Metric.barSpacing) {
      ForEach(displayedLevels.indices, id: \.self) { index in
        Capsule()
          .fill(AppColor.grayWhite)
          .frame(
            width: Metric.barWidth,
            height: Metric.minimumHeight
              + (Metric.maximumHeight - Metric.minimumHeight) * displayedLevels[index]
          )
      }
    }
    .frame(width: 182, height: 24)
    .animation(
      usesReducedMotion ? nil : .linear(duration: 0.05),
      value: displayedLevels
    )
    .accessibilityHidden(true)
  }

  var displayedLevels: [CGFloat] {
    guard levels.count == Metric.barCount else {
      return Array(repeating: .zero, count: Metric.barCount)
    }

    let clampedLevels = levels.map { min(max($0, 0), 1) }
    let averageLevel = clampedLevels.reduce(.zero, +) / CGFloat(Metric.barCount)

    return clampedLevels.map { level in
      min(
        max(averageLevel + (level - averageLevel) * Metric.contrastGain, 0),
        1
      )
    }
  }
}
