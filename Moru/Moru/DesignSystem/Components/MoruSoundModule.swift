//
//  MoruSoundModule.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruSoundModule: View {
  let pauseAction: () -> Void
  let stopAction: () -> Void

  init(
    pauseAction: @escaping () -> Void = {},
    stopAction: @escaping () -> Void = {}
  ) {
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
          MoruSoundPauseButtonIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("일시정지")

        MoruWaveform()

        Button(action: stopAction) {
          MoruSoundStopButtonIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("정지")
      }
      .frame(width: 330, height: 52)
    }
    .frame(width: 353, height: 76)
  }
}
