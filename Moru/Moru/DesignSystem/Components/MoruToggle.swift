//
//  MoruToggle.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruToggle: View {
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule()
          .fill(isOn ? AppColor.orange350 : AppColor.moruDisabled)
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
