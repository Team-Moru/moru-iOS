//
//  ConfirmStepContentView.swift
//  Moru
//

import SwiftUI

struct ConfirmStepContentView: View {
  let step: RoutineStep
  let isGuidancePlaying: Bool
  let isAutomaticStartBlocked: Bool
  let speechInputController: SpeechInputController
  let feedbackText: String?
  let waitUntilGuidanceFinishes: () async -> Bool
  let onComplete: (String) -> Void

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
        if isGuidancePlaying {
          Text("음성 안내 중")
            .font(AppFont.caption1SemiBold)
            .foregroundStyle(AppColor.gray350)
        }

        Text(feedbackText ?? confirmGuideText)
          .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
          .foregroundStyle(AppColor.gray500)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
      }

      Spacer()
        .frame(height: 32)

      VoiceInputControlView(
        speechInputController: speechInputController,
        automaticCompletionIntent: .dictatedInput,
        isAutomaticStartBlocked: isAutomaticStartBlocked,
        waitUntilGuidanceFinishes: waitUntilGuidanceFinishes
      ) { transcript in
        onComplete(transcript)
      }
    }
    .padding(.horizontal, 20)
  }

  private var stepTitleSection: some View {
    VStack(spacing: 8) {
      Text(step.title)
        .font(AppFont.pretendardSemiBold(size: 22, relativeTo: .title3))
        .foregroundStyle(AppColor.gray600)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text("확인형 · \(estimatedMinuteText)")
        .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
        .foregroundStyle(AppColor.gray400)
    }
  }

  private var estimatedMinuteText: String {
    let seconds = step.estimatedSeconds ?? 60
    let minutes = max(seconds / 60, 1)
    return "\(minutes)분"
  }

  private var confirmGuideText: String {
    RoutinePlayerCopy.guide(for: step)
  }
}
