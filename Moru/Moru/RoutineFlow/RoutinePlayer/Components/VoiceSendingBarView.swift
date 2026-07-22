//
//  VoiceSendingBarView.swift
//  Moru
//

import SwiftUI

struct VoiceSendingBarView: View {
  let phase: SpeechInputController.Phase
  let waveformLevels: [CGFloat]
  let onPauseResume: () -> Void
  let onStop: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 8) {
      Text(statusText)
        .font(AppFont.caption1SemiBold)
        .foregroundStyle(AppColor.gray350)
        .accessibilityAddTraits(.updatesFrequently)

      MoruSoundModule(
        levels: waveformLevels,
        isPaused: phase == .paused,
        isFinishing: phase == .finishing,
        usesReducedMotion: reduceMotion,
        pauseAction: onPauseResume,
        stopAction: onStop
      )
    }
    .frame(maxWidth: .infinity)
  }

  private var statusText: String {
    switch phase {
    case .idle:
      return ""
    case .listening:
      return "음성 인식 중"
    case .paused:
      return "음성 인식 일시정지"
    case .finishing:
      return "음성 인식 마무리 중…"
    case .failed:
      return "음성 인식에 실패했어요"
    }
  }
}
