//
//  MoruToggle.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruToggle: View {
  @Binding var isOn: Bool

  init(isOn: Binding<Bool>) {
    _isOn = isOn
  }

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule()
          .fill(isOn ? MoruPilotColor.accent : MoruPilotColor.disabled)
          .frame(width: 52, height: 28)

        Circle()
          .fill(AppColor.grayWhite)
          .frame(width: 20, height: 20)
          .padding(4)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isOn ? "켜짐" : "꺼짐")
  }
}
