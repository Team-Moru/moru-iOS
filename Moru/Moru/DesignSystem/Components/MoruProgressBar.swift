//
//  MoruProgressBar.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruProgressBar: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let current: Int
  let total: Int
  let showsLabel: Bool

  init(
    current: Int,
    total: Int,
    showsLabel: Bool = true
  ) {
    self.current = current
    self.total = total
    self.showsLabel = showsLabel
  }

  private var progress: CGFloat {
    guard total > 0 else { return 0 }
    return min(max(CGFloat(current) / CGFloat(total), 0), 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(MoruPilotColor.progressTrack)

          Capsule()
            .fill(MoruPilotColor.accent)
            .frame(width: proxy.size.width * progress)
        }
      }
      .frame(height: 5)
      .frame(maxWidth: .infinity)

      if showsLabel {
        progressLabel
      }
    }
  }

  @ViewBuilder
  private var progressLabel: some View {
    let label = Text("\(current)/\(total)")
      .foregroundStyle(MoruPilotColor.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)

    if dynamicTypeSize.isAccessibilitySize {
      label.font(
        .custom(
          MoruTextWeight.regular.rawValue,
          size: MoruTextStyle.c2.fontSize,
          relativeTo: MoruTextStyle.c2.relativeTextStyle
        )
      )
    } else {
      label.moruTextStyle(.c2.weight(.regular))
    }
  }
}
