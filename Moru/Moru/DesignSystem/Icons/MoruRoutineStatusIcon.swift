//
//  MoruRoutineStatusIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruRoutineStatusIconStyle {
  case on
  case off
}

struct MoruRoutineStatusIcon: View {
  let style: MoruRoutineStatusIconStyle

  var body: some View {
    Image(imageName)
      .resizable()
      .scaledToFit()
      .frame(width: 25, height: 27)
  }

  private var imageName: String {
    switch style {
    case .on:
      AppIcon.moruStatusCompleted
    case .off:
      AppIcon.moruStatusInProgress
    }
  }
}
