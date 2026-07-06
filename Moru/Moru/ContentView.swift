//
//  ContentView.swift
//  Moru
//
//  Created by 민혁 on 6/28/26.
//

import SwiftUI

struct ContentView: View {
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "sun.max.fill")
        .imageScale(.large)
        .foregroundStyle(.tint)

      Text(title)
        .font(AppFont.heading1Bold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text(message)
        .font(AppFont.body1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
  }
}

#Preview {
  ContentView(
    title: "MORU",
    message: "첫 루틴 생성 흐름을 연결할 준비가 되었습니다."
  )
}
