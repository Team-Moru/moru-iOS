//
//  MoruToggle.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

/// 켜고 끄는 스위치.
///
/// 캡슐과 손잡이를 직접 그리던 것을 시스템 `Toggle`로 바꿨다. 탭바 유리와
/// 같은 출처에서 외형을 받아야 OS가 바뀔 때 함께 따라간다.
struct MoruToggle: View {
  @Binding var isOn: Bool

  init(isOn: Binding<Bool>) {
    _isOn = isOn
  }

  var body: some View {
    Toggle("", isOn: $isOn)
      .labelsHidden()
      .tint(MoruColor.accent)
      .accessibilityLabel(isOn ? "켜짐" : "꺼짐")
  }
}
