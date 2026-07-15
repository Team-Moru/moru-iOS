//
//  HomeHeaderView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeHeaderView: View {
  let userName: String

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Image(AppImage.moruGradientGlow)
        .resizable()
        .scaledToFit()
        .opacity(0.8)
        .blur(radius: 12)
        .scaleEffect(1.2)
        .frame(width: 380, height: 380)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: -80)
        .allowsHitTesting(false)

      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        Text("좋은 아침이에요,\n\(userName)님")
          .font(AppFont.title2Bold)
          .foregroundStyle(AppColor.moruTextPrimary)
          .lineSpacing(6)

        Text("오늘도 작은 루틴이 큰 변화를 만들어요.")
          .font(AppFont.body1NormalMedium)
          .foregroundStyle(AppColor.moruTextSecondary)
      }
      .padding(.horizontal, AppSpacing.md)
      .padding(.bottom, 15)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 400)
  }
}

#Preview {
  HomeHeaderView(userName: "다인")
    .background(AppColor.babyBlue50)
}
