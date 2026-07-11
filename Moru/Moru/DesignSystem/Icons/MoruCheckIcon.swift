//
//  MoruCheckIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruCheckIcon: View {
  let isOn: Bool

  var body: some View {
    Image(isOn ? AppIcon.moruCheckOn : AppIcon.moruCheckOff)
      .resizable()
      .scaledToFit()
    .frame(width: 24, height: 24)
  }
}

struct MoruSmallCheckIcon: View {
  var body: some View {
    Image(AppIcon.moruSmallCheck)
      .resizable()
      .scaledToFit()
      .frame(width: 16, height: 16)
  }
}
