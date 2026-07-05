//
//  MoruTimeSettingCard.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruTimeSettingCard: View {
  let time: String
  let dateDescription: String

  var body: some View {
    VStack(spacing: 0) {
      Text(time)
        .font(AppFont.pretendardSemiBold(size: 80))
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 226, height: 85)

      Text(dateDescription)
        .font(AppFont.pretendardMedium(size: 16))
        .foregroundStyle(AppColor.grayWhite)
        .frame(width: 226, height: 22)
    }
    .frame(width: 226, height: 127)
  }
}
