//
//  MoruRoutineNoteIcon.swift
//  Moru
//
//  Created by Codex on 7/4/26.
//

import SwiftUI

struct MoruRoutineNoteIcon: View {
  let isActive: Bool

  var body: some View {
    Image(isActive ? AppIcon.moruRoutineMenuOn : AppIcon.moruRoutineMenuOff)
      .resizable()
      .scaledToFit()
      .frame(width: 40, height: 40)
  }
}
