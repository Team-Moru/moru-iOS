//
//  ConfirmStepContentView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct ConfirmStepContentView: View {
  let step: RoutineStep
  let onComplete: () -> Void

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

        Text(confirmGuideText)
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.gray500)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
      }

      Spacer()
        .frame(height: 32)

      VoiceMicButton {
        onComplete()
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

      Text("확인형 · \(estimatedMinuteText)")
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.gray400)
    }
  }

  private var estimatedMinuteText: String {
    "\(RoutineDuration.roundedMinutes(for: step.estimatedSeconds))분"
  }

  private var confirmGuideText: String {
    if !step.instruction.isEmpty {
      return step.instruction
    }

    return "완료되었으면 말해주세요."
  }
}
