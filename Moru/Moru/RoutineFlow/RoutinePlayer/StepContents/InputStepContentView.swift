//
//  InputStepContentView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct InputStepContentView: View {
  let step: RoutineStep
  let onComplete: (String?) -> Void

  var body: some View {
    VStack(spacing: 0) {
      stepTitleSection

      Spacer()
        .frame(height: 42)

      RoutinePlayerOrbView()

      Spacer()
        .frame(height: 44)

      VStack(spacing: 8) {
        Text("음성 안내 중")
          .font(AppFont.caption1SemiBold)
          .foregroundStyle(AppColor.gray350)

        Text(inputGuideText)
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.gray500)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
      }

      Spacer()
        .frame(height: 32)

      VoiceMicButton {
        // TODO: Speech Framework 연결 후
        // 인식된 transcript를 전달합니다.
        onComplete(nil)
      }
    }
    .padding(.horizontal, 24)
  }

  private var stepTitleSection: some View {
    VStack(spacing: 8) {
      Text(step.title)
        .font(AppFont.title2Bold)
        .foregroundStyle(AppColor.gray600)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier(RoutinePlayerAccessibility.input)
        .accessibilityLabel(RoutinePlayerAccessibility.inputLabel(for: step))
        .accessibilityHint("이 단계의 내용을 음성으로 입력합니다.")

      Text("입력형 · \(estimatedMinuteText)")
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.gray400)
    }
  }

  private var estimatedMinuteText: String {
    "\(RoutineDuration.roundedMinutes(for: step.estimatedSeconds))분"
  }

  private var inputGuideText: String {
    if !step.instruction.isEmpty {
      return step.instruction
    }

    return """
      오늘의 다짐을 크게 말해봐요!
      어떤 하루를 만들고 싶나요?
      """
  }
}
