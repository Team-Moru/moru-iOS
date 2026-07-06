//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct AppRouter: View {
  let dependencies: DependencyContainer
  let sessionStore: SessionStore

  var body: some View {
    Group {
      switch sessionStore.phase {
      case .loading:
        ProgressView()
      case .onboardingRequired:
        ContentView(
          title: "MORU",
          message: "첫 루틴 생성 흐름을 연결할 준비가 되었습니다."
        )
      case .ready:
        ContentView(
          title: "안녕하세요, \(sessionStore.profile?.displayName ?? "모루 사용자")님",
          message: "로컬 루틴 데이터 기준선이 준비되었습니다."
        )
      case .failed(let message):
        ContentView(
          title: "저장소를 열 수 없어요",
          message: message
        )
      }
    }
    .task {
      sessionStore.load()
    }
  }
}
