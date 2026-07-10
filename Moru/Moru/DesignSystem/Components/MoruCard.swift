//
//  MoruCard.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruCard<Content: View>: View {
  var backgroundColor: Color = AppColor.grayWhite
  var shadowColor: Color = AppShadow.cardColor
  var shadowRadius: CGFloat = AppShadow.cardRadius
  var shadowX: CGFloat = 0
  var shadowY: CGFloat = AppShadow.cardY
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      content
    }
    .padding(AppSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
  }
}
