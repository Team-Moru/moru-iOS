//
//  MoruSoundSymbol.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruSoundSymbol: View {
  var body: some View {
    Image(systemName: "speaker.wave.2")
      .resizable()
      .scaledToFit()
      .fontWeight(.medium)
      .foregroundStyle(AppColor.orange350)
      .frame(width: 24, height: 24)
  }
}

struct MoruSoundPauseButtonIcon: View {
  var body: some View {
    Image(AppIcon.moruSoundPauseButton)
      .resizable()
      .scaledToFit()
      .frame(width: 52, height: 52)
  }
}

struct MoruSoundStopButtonIcon: View {
  var body: some View {
    Image(AppIcon.moruSoundStopButton)
      .resizable()
      .scaledToFit()
      .frame(width: 52, height: 52)
  }
}
