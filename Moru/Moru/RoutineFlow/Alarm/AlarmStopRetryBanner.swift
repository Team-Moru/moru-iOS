//
//  AlarmStopRetryBanner.swift
//  Moru
//

import SwiftUI

/// AlarmKit 직접 진입에서 알람 정지가 실패했을 때 플레이어 상단에 얹는 배너.
/// 루틴은 그대로 진행하고 알람만 다시 끈다.
struct AlarmStopRetryBanner: View {
  static let title = "알람을 멈추지 못했어요."
  static let message = "루틴은 계속할 수 있어요. 알람만 다시 꺼 볼게요."
  static let retryTitle = "다시 시도"

  let isRetrying: Bool
  let onRetry: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(Self.title)
          .moruTextStyle(.b4.weight(.semiBold))
          .foregroundStyle(MoruColor.textStrong)

        Text(Self.message)
          .moruTextStyle(.c1)
          .foregroundStyle(MoruColor.textSecondary)
      }
      .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)

      MoruButton(Self.retryTitle, style: .text, isEnabled: !isRetrying) {
        onRetry()
      }
    }
    .padding(.horizontal, MoruSpacing.twenty)
    .padding(.vertical, MoruSpacing.twelve)
    .background(AppColor.grayWhite, in: RoundedRectangle(cornerRadius: MoruRadius.largeCard))
    .shadow(color: MoruColor.shadow, radius: 12, y: 4)
    .padding(.horizontal, MoruSpacing.twenty)
    .padding(.top, MoruSpacing.eight)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(Self.title) \(Self.message)")
  }
}

#Preview("알람 정지 재시도 배너") {
  VStack {
    AlarmStopRetryBanner(isRetrying: false) {}
    AlarmStopRetryBanner(isRetrying: true) {}
    Spacer()
  }
  .background(AppColor.babyBlue50)
}
