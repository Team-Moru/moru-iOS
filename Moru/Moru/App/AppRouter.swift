//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct AppRouter: View {
  private enum State {
    case ready(dependencies: DependencyContainer, sessionStore: SessionStore)
    case bootstrapFailed(String)
  }

  private let state: State

  init(dependencies: DependencyContainer, sessionStore: SessionStore) {
    state = .ready(dependencies: dependencies, sessionStore: sessionStore)
  }

  init(bootstrapFailureMessage: String) {
    state = .bootstrapFailed(bootstrapFailureMessage)
  }

  var body: some View {
    Group {
      switch state {
      case .ready(_, let sessionStore):
        SessionContentView(sessionStore: sessionStore)
      case .bootstrapFailed(let message):
        ContentView(
          title: "저장소를 열 수 없어요",
          message: message
        )
      }
    }
  }

  private struct SessionContentView: View {
    @ObservedObject var sessionStore: SessionStore

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
}
