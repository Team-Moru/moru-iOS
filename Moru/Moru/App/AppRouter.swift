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
          MainTabView(dependencies: dependencies) {
            sessionStore.load()
          }
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
