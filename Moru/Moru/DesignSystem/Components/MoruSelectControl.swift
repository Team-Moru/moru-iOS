//
//  MoruSelectControl.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruSelectControlStyle {
  case plus
  case minus
}

struct MoruSelectControl: View {
  let style: MoruSelectControlStyle
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      MoruSelectIcon(style: iconStyle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    switch style {
    case .plus:
      "추가"
    case .minus:
      "삭제"
    }
  }

  private var iconStyle: MoruSelectIconStyle {
    switch style {
    case .plus:
      .plus
    case .minus:
      .minus
    }
  }
}
