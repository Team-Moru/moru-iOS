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

  private let staticLevels: [CGFloat] = [
    0, 0.25, 0.625, 1, 0.75, 0.375, 0.125, 0.5, 0.875, 0.625,
    0.25, 0, 0.5, 0.75, 1, 0.625, 0.375, 0.125, 0.375, 0
  ]

  init(levels: [CGFloat] = [], usesReducedMotion: Bool = false) {
    self.levels = levels
    self.usesReducedMotion = usesReducedMotion
  }

  var body: some View {
    HStack(alignment: .center, spacing: 4.6667) {
      ForEach(displayedLevels.indices, id: \.self) { index in
        Capsule()
          .fill(AppColor.grayWhite)
          .frame(width: 4.6667, height: 8 + 16 * displayedLevels[index])
      }
    }
    .frame(width: 182, height: 24)
    .animation(
      usesReducedMotion ? nil : .linear(duration: 0.05),
      value: displayedLevels
    )
    .accessibilityHidden(true)
  }

  private var displayedLevels: [CGFloat] {
    if usesReducedMotion || levels.count != staticLevels.count {
      return staticLevels
    }

    return levels.map { min(max($0, 0), 1) }
  }
}
