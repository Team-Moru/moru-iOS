//
//  MoruApp.swift
//  Moru
//
//  Created by 민혁 on 6/28/26.
//

import SwiftUI

@main
struct MoruApp: App {
  @StateObject private var launchCoordinator = AppLaunchCoordinator()

  var body: some Scene {
    WindowGroup {
      Group {
        switch launchCoordinator.phase {
        case .idle, .constructing, .loadingSession:
          if launchCoordinator.showsLaunchStatus {
            LaunchStatusView()
          } else {
            EmptyView()
          }
        case .ready(let app):
          AppRouter(
            dependencies: app.dependencies,
            sessionStore: app.sessionStore,
            coordinator: app.navigationCoordinator,
            onboardingBuilder: app.onboardingBuilder,
            routinePlayerBuilder: app.routinePlayerBuilder,
            requestSessionReload: launchCoordinator.requestSessionReload,
            retrySessionReload: launchCoordinator.retrySessionReload,
            homeBuilder: app.homeBuilder,
            state: app.routerState
          )
        case .bootstrapFailed(let failure), .sessionFailed(_, let failure):
          LaunchFailureView(message: failure.message, onRetry: launchCoordinator.retry)
        case .recoveryRequired(let failure):
          LaunchRecoveryView(message: failure.message)
        }
      }
      .task {
        launchCoordinator.start()
      }
    }
  }
}

struct LaunchStatusView: View {
  static let message = "루틴을 준비하고 있어요"

  var body: some View {
    Text(Self.message)
  }
}

private struct LaunchFailureView: View {
  let message: String
  let onRetry: @MainActor () -> Void

  var body: some View {
    VStack(spacing: 16) {
      ContentView(
        title: "루틴을 준비할 수 없어요",
        message: message
      )
      Button("다시 시도", action: onRetry)
    }
  }
}

private struct LaunchRecoveryView: View {
  let message: String

  var body: some View {
    ContentView(
      title: "복구가 필요해요",
      message: "\(message)\n앱을 종료한 뒤 다시 시작해 주세요."
    )
  }
}
