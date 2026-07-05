//
//  MoruCheckBadge.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruCheckState {
  case off
  case on
}

struct MoruCheckBadge: View {
  let state: MoruCheckState

  init(state: MoruCheckState) {
    self.state = state
  }

  var body: some View {
    statusIcon
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch state {
    case .on:
      MoruRoutineStatusIcon(style: .on)
    case .off:
      MoruRoutineStatusIcon(style: .off)
    }
  }

  private var accessibilityLabel: String {
    state.accessibilityLabel
  }
}

private extension MoruCheckState {
  var accessibilityLabel: String {
    switch self {
    case .off:
      return "꺼짐"
    case .on:
      return "켜짐"
    }
  }
}
