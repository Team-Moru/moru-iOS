//
//  SplashScreenView.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import SwiftUI

nonisolated enum SplashScreenAccessibility {
  static let startIdentifier = "splash.start"
}

struct SplashScreenView: View {
  private let onStart: (@MainActor () -> Void)?

  init(onStart: (@MainActor () -> Void)? = nil) {
    self.onStart = onStart
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        splashBrand
          .frame(width: proxy.size.width, height: 181)
          .position(x: proxy.size.width / 2, y: 327)
          .accessibilityLabel("MORU, 모두의 아침 루틴")

        splashMessage
          .frame(maxWidth: proxy.size.width - AppSpacing.forty)
          .position(x: proxy.size.width / 2, y: 495)

        if let onStart {
          VStack {
            Spacer()

            MoruButton("시작하기", action: onStart)
              .accessibilityIdentifier(
                SplashScreenAccessibility.startIdentifier
              )
              .padding(
                .bottom,
                max(AppSpacing.xxl, proxy.safeAreaInsets.bottom)
              )
          }
        }
      }
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

  private var splashMessage: some View {
    Text("알람이 울리는 그 순간부터,\nAI가 당신의 아침을 코치합니다")
      .font(AppFont.pretendardSemiBold(size: 19, relativeTo: .title3))
      .foregroundStyle(AppColor.babyBlue250)
      .multilineTextAlignment(.center)
      .lineSpacing(AppSpacing.xxs)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel("알람이 울리는 그 순간부터, AI가 당신의 아침을 코치합니다")
  }
}
