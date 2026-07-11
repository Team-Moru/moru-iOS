//
//  MoruSelectIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

enum MoruSelectIconStyle {
  case plus
  case minus
}

struct MoruSelectIcon: View {
  let style: MoruSelectIconStyle

  var body: some View {
    Image(imageName)
      .resizable()
      .scaledToFit()
      .frame(width: 24, height: 24)
  }

  private var imageName: String {
    switch style {
    case .plus:
      AppIcon.moruSelectPlus
    case .minus:
      AppIcon.moruSelectMinus
    }
  }
}
