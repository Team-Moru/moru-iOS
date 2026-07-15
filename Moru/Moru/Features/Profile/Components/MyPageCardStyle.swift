//
//  MyPageCardStyle.swift
//  Moru
//
//  Created by Codex on 7/15/26.
//

import SwiftUI

private struct MyPageCardStyle: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(AppColor.grayWhite.opacity(0.2))
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .shadow(color: AppColor.babyBlue150, radius: 7.5, x: 0, y: 0)
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .inset(by: 0.5)
          .stroke(AppColor.gray150, lineWidth: 1)
      )
  }
}

extension View {
  func moruMyPageCardStyle(cornerRadius: CGFloat = AppSpacing.lg) -> some View {
    modifier(MyPageCardStyle(cornerRadius: cornerRadius))
  }
}
