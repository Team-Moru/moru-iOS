//
//  MoruCard.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      content
    }
    .padding(AppSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColor.grayWhite)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    .shadow(color: AppShadow.cardColor, radius: AppShadow.cardRadius, y: AppShadow.cardY)
  }
}
