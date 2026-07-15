//
//  MyPageSectionHeader.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import SwiftUI

struct MyPageSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(AppFont.heading3SemiBold)
      .foregroundStyle(AppColor.moruTextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
