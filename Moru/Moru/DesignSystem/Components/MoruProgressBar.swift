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
  let componentStyle: MoruPilotComponentStyle

  private let figmaGaugeWidth: CGFloat = 352

  init(
    current: Int,
    total: Int,
    componentStyle: MoruPilotComponentStyle = .legacy
  ) {
    self.current = current
    self.total = total
    self.componentStyle = componentStyle
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
            .fill(trackColor)

          Capsule()
            .fill(progressColor)
            .frame(width: proxy.size.width * progress)
        }
      }
      .frame(height: 5)
      .frame(maxWidth: figmaGaugeWidth)

      progressLabel
    }
  }

  @ViewBuilder
  private var progressLabel: some View {
    let label = Text("\(current)/\(total)")
      .foregroundStyle(labelColor)
      .frame(maxWidth: figmaGaugeWidth, alignment: .leading)

    if componentStyle == .figmaPilot {
      label.moruTextStyle(.c2.weight(.regular))
    } else {
      label.font(AppFont.pretendardRegular(size: 12))
    }
  }

  private var trackColor: Color {
    componentStyle == .figmaPilot
      ? MoruPilotColor.progressTrack
      : AppColor.moruSurfaceMuted
  }

  private var progressColor: Color {
    componentStyle == .figmaPilot ? MoruPilotColor.accent : AppColor.orange350
  }

  private var labelColor: Color {
    componentStyle == .figmaPilot ? MoruPilotColor.textPrimary : AppColor.moruTextBody
  }
}
