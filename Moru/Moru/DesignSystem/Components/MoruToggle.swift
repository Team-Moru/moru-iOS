//
//  MoruToggle.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruToggle: View {
  @Binding var isOn: Bool
  let componentStyle: MoruPilotComponentStyle

  init(
    isOn: Binding<Bool>,
    componentStyle: MoruPilotComponentStyle = .legacy
  ) {
    _isOn = isOn
    self.componentStyle = componentStyle
  }

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule()
          .fill(trackColor)
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

  private var trackColor: Color {
    guard componentStyle == .figmaPilot else {
      return isOn ? AppColor.orange350 : AppColor.moruDisabled
    }

    return isOn ? MoruPilotColor.accent : AppColor.moruDisabled
  }
}
