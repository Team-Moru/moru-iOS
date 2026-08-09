//
//  SplashScreenView.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

struct SplashScreenView: View {
  var body: some View {
    GeometryReader { proxy in
      splashBrand
        .frame(width: proxy.size.width, height: 181)
        .position(x: proxy.size.width / 2, y: 327)
        .accessibilityLabel("MORU, 모두의 아침 루틴")
    }
    .background(
      LinearGradient(
        colors: [
          AppColor.grayWhite,
          MoruPilotColor.canvas,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
    )
  }

  private var splashBrand: some View {
    VStack(spacing: 0) {
      Image(AppImage.moruLoginIcon)
        .resizable()
        .scaledToFit()
        .frame(width: 137, height: 109)

      Text("MORU")
        .font(AppFont.pretendardBold(size: 36, relativeTo: .largeTitle))
        .foregroundStyle(AppColor.babyBlue300)
        .lineLimit(1)
        .padding(.top, 14)

      Text("모두의 아침 루틴")
        .font(AppFont.pretendardMedium(size: 14, relativeTo: .callout))
        .foregroundStyle(AppColor.babyBlue250)
        .lineLimit(1)
        .padding(.top, 4)
    }
    .accessibilityElement(children: .combine)
  }
}
