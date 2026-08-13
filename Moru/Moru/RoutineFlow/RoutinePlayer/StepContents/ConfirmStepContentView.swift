//
//  ConfirmStepContentView.swift
//  Moru
//

import SwiftUI

enum ConfirmStepFeedback {
  static let negativeResponse = "아직이군요. 천천히 마무리한 뒤 \"완료했어요\"라고 말해 주세요."
  static let unrecognizedCompletion = "완료했다고 들리지 않아요. 다시 말해 주세요."

  static func completionFailure(for transcript: String) -> String {
    ConfirmTranscriptMatcher.hasNegativeIntent(transcript)
      ? negativeResponse
      : unrecognizedCompletion
  }
}

struct ConfirmStepContentView: View {
  let step: RoutineStep
  let isGuidancePlaying: Bool
  let isAutomaticStartBlocked: Bool
  let speechInputController: SpeechInputController
  let waitUntilGuidanceFinishes: () async -> Bool
  let onComplete: (String?) -> Void
  let onSkip: () -> Void
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
        automaticCompletionIntent: .stepCompletion,
        autoFinishMatch: { transcript in
          RoutineStepCompletionMatcher.match(transcript, for: step)
        },
        isAutomaticStartBlocked: isAutomaticStartBlocked,
        waitUntilGuidanceFinishes: waitUntilGuidanceFinishes
      ) { transcript in
        guard RoutineStepCompletionMatcher.isCompleted(transcript, for: step) else {
          feedbackText = ConfirmStepFeedback.completionFailure(for: transcript)
          return
        }

        onComplete(transcript)
      }

      HStack(spacing: 0) {
        Button {
          speechInputController.cancel()
          onComplete(nil)
        } label: {
          Text("완료했어요")
            .font(
              AppFont.pretendardMedium(
                size: 14,
                relativeTo: .caption
              )
            )
            .foregroundStyle(AppColor.gray400)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("음성 입력 없이 이 단계를 완료합니다")

        Button(action: onSkip) {
          Text("건너뛰기")
            .font(
              AppFont.pretendardMedium(
                size: 14,
                relativeTo: .caption
              )
            )
            .foregroundStyle(AppColor.gray300)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 20)
    }
    .padding(.horizontal, 20)
    .onChange(of: speechInputController.latestTranscriptUpdate) { _, update in
      guard let update,
            ConfirmTranscriptMatcher.hasNegativeIntent(update.text) else {
        return
      }

      feedbackText = ConfirmStepFeedback.negativeResponse
    }
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
