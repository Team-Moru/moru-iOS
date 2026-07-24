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
    VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
      Text(greeting)
        .homeFigmaTextStyle(.h3)
        .foregroundStyle(MoruPilotColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(HomeCopy.encouragement)
        .homeFigmaTextStyle(.b4)
        .foregroundStyle(MoruPilotColor.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .background(alignment: .bottom) {
      Image(AppImage.moruGradientGlow)
        .resizable()
        .scaledToFit()
        .opacity(0.8)
        .frame(width: 353, height: 404)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: 31)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .frame(height: 296)
  }

  private var greeting: String {
    let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      return HomeCopy.greetingWithoutName
    }

    return "\(HomeCopy.greeting)\n\(trimmedName)님"
  }
}

#Preview {
  HomeHeaderView(userName: "다인")
    .background(AppColor.babyBlue50)
}
