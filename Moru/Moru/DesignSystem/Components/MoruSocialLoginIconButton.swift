//
//  MoruSocialLoginIconButton.swift
//  Moru
//

import SwiftUI

enum MoruSocialLoginProvider {
  case apple
  case google
  case kakao

  var assetName: String {
    switch self {
    case .apple:
      AppImage.moruLoginApple
    case .google:
      AppImage.moruLoginGoogle
    case .kakao:
      AppImage.moruLoginKakao
    }
  }
}

struct MoruSocialLoginIconButton: View {
  let provider: MoruSocialLoginProvider
  let isLoading: Bool
  let isDisabled: Bool
  let action: @MainActor () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Image(provider.assetName)
          .resizable()
          .scaledToFit()

        if isLoading {
          Circle()
            .fill(AppColor.grayWhite.opacity(0.72))

          ProgressView()
            .tint(AppColor.grayBlack)
            .controlSize(.small)
        }
      }
      .frame(width: 56, height: 56)
      .opacity(isDisabled ? 0.45 : 1)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
  }
}
