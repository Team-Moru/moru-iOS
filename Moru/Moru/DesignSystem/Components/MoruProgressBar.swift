//
//  MoruProgressBar.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruProgressBar: View {
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
            .fill(MoruColor.progressTrack)

          Capsule()
            .fill(MoruColor.accent)
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

  private var progressLabel: some View {
    Text("\(current)/\(total)")
      .moruTextStyle(.c2.weight(.regular))
      .foregroundStyle(MoruColor.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
