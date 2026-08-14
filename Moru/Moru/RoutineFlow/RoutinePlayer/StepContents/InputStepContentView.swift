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
  let onNoSpeechReminder: () async -> Bool
  let onComplete: (String?) -> Void
  let onAutomaticSkip: () -> Void
  let onSkip: () -> Void
  @State private var feedbackText: String?

  var body: some View {
    VStack(spacing: 0) {
      stepTitleSection

      Spacer()
        .frame(height: hasTranscript ? 73 : 42)

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
        .frame(height: hasTranscript ? 76 : 44)

      if !hasTranscript {
        VStack(spacing: 8) {
          if isGuidancePlaying {
            Text("음성 안내 중")
              .font(AppFont.caption1SemiBold)
              .foregroundStyle(AppColor.gray350)
          }

          Text(feedbackText ?? inputGuideText)
            .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
            .foregroundStyle(AppColor.gray500)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
        }

        Spacer()
          .frame(height: 32)
      }

      VoiceInputControlView(
        speechInputController: speechInputController,
        automaticCompletionIntent: .dictatedInput,
        showsTranscript: false,
        isAutomaticStartBlocked: isAutomaticStartBlocked,
        waitUntilGuidanceFinishes: waitUntilGuidanceFinishes,
        onNoSpeechReminder: {
          feedbackText = "아직 음성이 들리지 않아요. 준비되면 말해 주세요."
          return await onNoSpeechReminder()
        },
        onAutomaticSkip: onAutomaticSkip
      ) { transcript in
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          feedbackText = "음성이 들리지 않았어요. 다시 말해 주세요."
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
  }

  private var stepTitleSection: some View {
    VStack(spacing: 8) {
      Text(step.title)
        .font(AppFont.pretendardSemiBold(size: 22, relativeTo: .title3))
        .foregroundStyle(AppColor.gray600)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text("입력형 · \(estimatedMinuteText)")
        .font(AppFont.pretendardMedium(size: 16, relativeTo: .body))
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
        .font(AppFont.pretendardSemiBold(size: 16, relativeTo: .body))
        .foregroundStyle(AppColor.gray500)

      Text(speechInputController.displayTranscript)
        .font(AppFont.pretendardMedium(size: 18, relativeTo: .body))
        .foregroundStyle(AppColor.gray350)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(RoutinePlayerCopy.transcriptTitle(for: step))
        .accessibilityValue(speechInputController.displayTranscript)
    }
    .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
    .padding(24)
    .background(
      AppColor.babyBlue100.opacity(0.20),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(AppColor.grayWhite.opacity(0.90), lineWidth: 1)
    }
    .shadow(
      color: MoruPilotColor.shadow.opacity(0.42),
      radius: 22,
      y: 10
    )
  }
}
