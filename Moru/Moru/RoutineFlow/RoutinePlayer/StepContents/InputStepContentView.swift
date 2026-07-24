//
//  InputStepContentView.swift
//  Moru
//

import SwiftUI

struct InputStepContentView: View {
  let step: RoutineStep
  let isGuidancePlaying: Bool
  let isAutomaticStartBlocked: Bool
  let speechInputController: SpeechInputController
  let waitUntilGuidanceFinishes: () async -> Bool
  let onComplete: (String) -> Void
  @State private var feedbackText: String?

  var body: some View {
    VStack(spacing: 0) {
      stepTitleSection

      Spacer()
        .frame(height: hasTranscript ? 62 : 42)

      if hasTranscript {
        transcriptCard
      } else {
        RoutinePlayerOrbView(
          levels: speechInputController.waveformLevels,
          isListening: speechInputController.phase == .listening,
          isPaused: speechInputController.isPaused
        )
      }

      Spacer()
        .frame(height: hasTranscript ? 53 : 44)

      if !hasTranscript {
        VStack(spacing: 8) {
          if isGuidancePlaying {
            Text("음성 안내 중")
              .font(AppFont.caption1SemiBold)
              .foregroundStyle(AppColor.gray350)
          }

          Text(feedbackText ?? inputGuideText)
            .font(
              .custom(
                "Pretendard-SemiBold",
                size: 16,
                relativeTo: .body
              )
            )
            .foregroundStyle(AppColor.gray500)
            .multilineTextAlignment(.center)
        }

        Spacer()
          .frame(height: 32)
      }

      VoiceInputControlView(
        speechInputController: speechInputController,
        automaticCompletionIntent: .dictatedInput,
        showsTranscript: false,
        isAutomaticStartBlocked: isAutomaticStartBlocked,
        waitUntilGuidanceFinishes: waitUntilGuidanceFinishes
      ) { transcript in
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          feedbackText = "음성이 들리지 않았어요. 다시 말해 주세요."
          return
        }

        onComplete(transcript)
      }
    }
    .padding(.horizontal, 20)
  }

  private var stepTitleSection: some View {
    VStack(spacing: 8) {
      Text(step.title)
        .font(
          .custom(
            "Pretendard-SemiBold",
            size: 22,
            relativeTo: .title3
          )
        )
        .foregroundStyle(AppColor.gray600)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text("입력형 · \(estimatedMinuteText)")
        .font(
          .custom(
            "Pretendard-Medium",
            size: 16,
            relativeTo: .body
          )
        )
        .foregroundStyle(AppColor.gray400)
    }
  }

  private var estimatedMinuteText: String {
    let seconds = step.estimatedSeconds ?? 60
    let minutes = max(seconds / 60, 1)
    return "\(minutes)분"
  }

  private var inputGuideText: String {
    RoutinePlayerCopy.guide(for: step)
  }

  private var hasTranscript: Bool {
    !speechInputController.displayTranscript.isEmpty
  }

  private var transcriptCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(RoutinePlayerCopy.transcriptTitle(for: step))
        .font(
          .custom(
            "Pretendard-SemiBold",
            size: 16,
            relativeTo: .body
          )
        )
        .foregroundStyle(AppColor.gray500)

      Text(speechInputController.displayTranscript)
        .font(
          .custom(
            "Pretendard-Medium",
            size: 18,
            relativeTo: .body
          )
        )
        .foregroundStyle(AppColor.gray350)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("인식된 내용")
        .accessibilityValue(speechInputController.displayTranscript)
    }
    .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
    .padding(24)
    .background(
      AppColor.grayWhite.opacity(0.58),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .shadow(
      color: AppColor.orange100.opacity(0.14),
      radius: 24,
      y: 8
    )
  }
}
