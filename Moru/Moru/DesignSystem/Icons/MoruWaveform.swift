//
//  MoruWaveform.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruWaveform: View {
  private let heights: [CGFloat] = [
    8, 12, 18, 24, 20, 14, 10, 16, 22, 18,
    12, 8, 16, 20, 24, 18, 14, 10, 14, 8
  ]

  var body: some View {
    HStack(alignment: .center, spacing: 4.4) {
      ForEach(heights.indices, id: \.self) { index in
        Capsule()
          .fill(AppColor.grayWhite)
          .frame(width: 4.7, height: heights[index])
      }
    }
    .frame(width: 182, height: 24)
  }
}
