//
//  MoruFireIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruFireIcon: View {
  let size: CGFloat
  var background: Color = AppColor.orange100

  var body: some View {
    Image(AppIcon.moruFireIcon)
      .resizable()
      .scaledToFit()
    .frame(width: size, height: size)
  }
}
