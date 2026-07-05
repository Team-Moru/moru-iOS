//
//  MoruTimerStatus.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruTimerStatus: View {
  let remainingTime: String
  let title: String

  var body: some View {
    ZStack {
      Circle()
        .fill(AppColor.orange300)
        .frame(width: 240, height: 240)

      Circle()
        .fill(AppColor.moruSurfaceMuted)
        .frame(width: 196, height: 196)

      VStack(spacing: 0) {
        Text(title)
          .font(AppFont.pretendardBold(size: 16))
          .foregroundStyle(AppColor.moruTextTertiary)

        Text(remainingTime)
          .font(AppFont.pretendardSemiBold(size: 48))
          .foregroundStyle(AppColor.moruTextBody)
      }
    }
    .frame(width: 240, height: 240)
  }
}
