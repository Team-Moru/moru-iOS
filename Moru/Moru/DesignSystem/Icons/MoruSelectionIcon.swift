//
//  MoruSelectionIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruSelectionCardIcon {
  case energy
  case mind
  case health
  case habit

  var imageName: String {
    switch self {
    case .energy:
      return AppIcon.moruSelectionEnergyIcon
    case .mind:
      return AppIcon.moruSelectionMindIcon
    case .health:
      return AppIcon.moruSelectionHealthIcon
    case .habit:
      return AppIcon.moruSelectionHabitIcon
    }
  }
}

struct MoruSelectionIcon: View {
  let icon: MoruSelectionCardIcon

  var body: some View {
    Image(icon.imageName)
      .resizable()
      .scaledToFit()
      .frame(width: 32, height: 32)
  }
}
