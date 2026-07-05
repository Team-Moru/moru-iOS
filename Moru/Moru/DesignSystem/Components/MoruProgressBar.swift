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

  private let figmaGaugeWidth: CGFloat = 352

  private var progress: CGFloat {
    guard total > 0 else { return 0 }
    return min(max(CGFloat(current) / CGFloat(total), 0), 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(AppColor.moruSurfaceMuted)

          Capsule()
            .fill(AppColor.orange350)
            .frame(width: proxy.size.width * progress)
        }
      }
      .frame(height: 5)
      .frame(maxWidth: figmaGaugeWidth)

      Text("\(current)/\(total)")
        .font(AppFont.pretendardRegular(size: 12))
        .foregroundStyle(AppColor.moruTextBody)
        .frame(maxWidth: figmaGaugeWidth, alignment: .leading)
    }
  }
}
