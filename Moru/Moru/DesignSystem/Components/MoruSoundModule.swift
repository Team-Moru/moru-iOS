//
//  MoruSoundModule.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruSoundModule: View {
  let levels: [CGFloat]
  let isPaused: Bool
  let isFinishing: Bool
  let usesReducedMotion: Bool
  let pauseAction: () -> Void
  let stopAction: () -> Void

  init(
    levels: [CGFloat] = [],
    isPaused: Bool = false,
    isFinishing: Bool = false,
    usesReducedMotion: Bool = false,
    pauseAction: @escaping () -> Void = {},
    stopAction: @escaping () -> Void = {}
  ) {
    self.levels = levels
    self.isPaused = isPaused
    self.isFinishing = isFinishing
    self.usesReducedMotion = usesReducedMotion
    self.pauseAction = pauseAction
    self.stopAction = stopAction
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: AppRadius.pill)
        .fill(AppColor.moruOrangePale)
        .frame(width: 353, height: 76)

      Ellipse()
        .fill(AppColor.orange300)
        .frame(width: 227, height: 35)
        .blur(radius: 8)

      HStack(spacing: 22) {
        Button(action: pauseAction) {
          if isPaused {
            MoruSoundResumeButtonIcon()
          } else {
            MoruSoundPauseButtonIcon()
          }
        }
        .buttonStyle(.plain)
        .disabled(isFinishing)
        .accessibilityLabel(isPaused ? "음성 인식 재개" : "음성 인식 일시정지")

        MoruWaveform(levels: levels, usesReducedMotion: usesReducedMotion)

        Button(action: stopAction) {
          MoruSoundStopButtonIcon()
        }
        .buttonStyle(.plain)
        .disabled(isFinishing)
        .accessibilityLabel("음성 입력 종료")
        .accessibilityHint("현재 인식 결과를 저장합니다")
      }
      .frame(width: 330, height: 52)
    }
    .frame(width: 353, height: 76)
  }
}
