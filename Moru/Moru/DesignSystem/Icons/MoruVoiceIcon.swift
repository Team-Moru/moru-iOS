//
//  MoruVoiceIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruVoiceOrb: View {
  let size: CGFloat

  var body: some View {
    Image(AppIcon.moruVoiceOrb)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}

struct MoruVoiceOrbSoft: View {
  let size: CGFloat

  var body: some View {
    Image(AppIcon.moruVoiceOrbSoft)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}

struct MoruVoiceHeartIcon: View {
  var body: some View {
    Image(AppIcon.moruVoiceHeartIcon)
      .resizable()
      .scaledToFit()
      .frame(width: 32, height: 32)
  }
}

struct MoruVoicePlayIcon: View {
  var body: some View {
    Image(AppIcon.moruVoicePlayIcon)
      .resizable()
      .scaledToFit()
      .frame(width: 32, height: 32)
  }
}

struct MoruVoiceRecordingIcon: View {
  var body: some View {
    MoruVoicePlayIcon()
  }
}

struct MoruRecordingEndIcon: View {
  var body: some View {
    MoruVoicePlayIcon()
  }
}

struct MoruSoundIcon: View {
  var size: CGFloat = 52

  var body: some View {
    Image(AppIcon.moruMicOrb)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}
