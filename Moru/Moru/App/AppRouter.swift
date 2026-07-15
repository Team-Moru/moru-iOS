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
      case .ready(let dependencies, let sessionStore):
        SessionContentView(
          dependencies: dependencies,
          sessionStore: sessionStore
        )
      case .bootstrapFailed(let message):
        ContentView(
          title: "저장소를 열 수 없어요",
          message: message
        )
      }
    }
  }

  private struct SessionContentView: View {
    let dependencies: DependencyContainer
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
      Group {
        switch sessionStore.phase {
        case .loading:
          ProgressView()
        case .onboardingRequired:
          OnboardingFlowView(dependencies: dependencies) {
            sessionStore.load()
          }
        case .ready:
            #if DEBUG
            AlarmKitDebugView(
                dependencies: dependencies
            )
            #else
            ContentView(
                title: "안녕하세요, \(sessionStore.profile?.displayName ?? "모루 사용자")님",
                message: "로컬 루틴 데이터 기준선이 준비되었습니다."
            )
            #endif
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
