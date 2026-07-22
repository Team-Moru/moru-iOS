//
//  VoiceMicButton.swift
//  Moru
//
//  Created by 김승겸 on 7/8/26.
//

import SwiftUI

struct VoiceMicButton: View {
  let isDisabled: Bool
  let action: () -> Void

  init(isDisabled: Bool = false, action: @escaping () -> Void) {
    self.isDisabled = isDisabled
    self.action = action
  }

  var body: some View {
    Button {
      action()
    } label: {
      Image(AppIcon.moruMicOrb)
        .resizable()
        .scaledToFit()
        .frame(width: 76, height: 76)
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .accessibilityLabel("음성 입력 시작")
  }
}
