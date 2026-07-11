//
//  MoruChevron.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruChevron: View {
  var color: Color = AppColor.moruTextPrimary
  var direction: MoruChevronDirection = .right

  var body: some View {
    Image(systemName: "chevron.right")
      .resizable()
      .scaledToFit()
      .foregroundStyle(color)
      .frame(width: 10, height: 18)
      .frame(width: 20, height: 20)
      .rotationEffect(direction.rotation)
  }
}

enum MoruChevronDirection {
  case right
  case down

  var rotation: Angle {
    switch self {
    case .right:
      .degrees(0)
    case .down:
      .degrees(90)
    }
  }
}
