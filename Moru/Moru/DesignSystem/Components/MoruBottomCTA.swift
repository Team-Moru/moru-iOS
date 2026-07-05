//
//  MoruBottomCTA.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruBottomCTA<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      content
    }
    .padding(.horizontal, AppSpacing.bottomCTAHorizontal)
    .padding(.top, AppSpacing.bottomCTAVertical)
    .padding(.bottom, AppSpacing.lg)
    .background(AppColor.grayWhite)
  }
}
