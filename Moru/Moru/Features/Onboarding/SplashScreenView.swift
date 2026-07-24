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
      Image(AppImage.moruSplashBrand)
        .resizable()
        .scaledToFit()
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
}
