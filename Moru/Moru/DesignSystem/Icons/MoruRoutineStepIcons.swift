//
//  MoruRoutineStepIcons.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

enum MoruRoutineStepControlIconStyle {
  case minus
  case plus
}

struct MoruRoutineStepControlIcon: View {
  let style: MoruRoutineStepControlIconStyle

  var body: some View {
    Image(imageName)
      .resizable()
      .scaledToFit()
      .frame(width: 24, height: 24)
  }

  private var imageName: String {
    switch style {
    case .minus:
      AppIcon.moruRoutineStepMinusIcon
    case .plus:
      AppIcon.moruRoutineStepPlusIcon
    }
  }
}

struct MoruRoutineStepTypeIcon: View {
  let type: RoutineStepType

  var body: some View {
    Image(imageName)
      .resizable()
      .scaledToFit()
      .frame(width: 28, height: 28)
  }

  private var imageName: String {
    switch type {
    case .confirm:
      AppIcon.moruRoutineStepConfirmIcon
    case .timer:
      AppIcon.moruRoutineStepTimerIcon
    case .input:
      AppIcon.moruRoutineStepInputIcon
    }
  }
}
