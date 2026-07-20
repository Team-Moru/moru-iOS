//
//  InputStepContentView.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct InputStepContentView: View {
  let step: RoutineStep
  let speechInputController: SpeechInputController
  let onComplete: (String) -> Void
  @State private var feedbackText: String?

  var body: some View {
    VStack(spacing: 0) {
      stepTitleSection

      Spacer()
        .frame(height: 42)

      RoutinePlayerOrbView(
        levels: speechInputController.waveformLevels,
        isListening: speechInputController.phase == .listening,
        isPaused: speechInputController.isPaused
      )

      Spacer()
        .frame(height: 44)

      VStack(spacing: 8) {
        Text("음성 안내 중")
          .font(AppFont.caption1SemiBold)
          .foregroundStyle(AppColor.gray350)

        Text(feedbackText ?? inputGuideText)
          .font(AppFont.body1NormalSemiBold)
          .foregroundStyle(AppColor.gray500)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
      }

      Spacer()
        .frame(height: 32)

      VoiceInputControlView(
        speechInputController: speechInputController,
        autoFinishMatch: { transcript in
          RoutineStepCompletionMatcher.match(transcript, for: step)
        }
      ) { transcript in
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          feedbackText = "음성이 들리지 않았어요. 다시 말해 주세요."
          return
        }

        onComplete(transcript)
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
