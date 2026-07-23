//
//  MoruApp.swift
//  Moru
//
//  Created by 민혁 on 6/28/26.
//

import SwiftUI
import UIKit

final class MoruApplicationDelegate: NSObject, UIApplicationDelegate {
  let alarmNotificationDelegate: AlarmNotificationDelegate

  override init() {
    alarmNotificationDelegate = AlarmNotificationDelegate()
    super.init()
  }
}

@main
struct MoruApp: App {
  @UIApplicationDelegateAdaptor(MoruApplicationDelegate.self)
  private var applicationDelegate
  @StateObject private var bootstrapper = AppBootstrapper()

  var body: some Scene {
    WindowGroup {
      Group {
        switch bootstrapper.state {
        case .idle, .loading:
          ProgressView()
        case .ready(let app):
          AppRouter(
            dependencies: app.dependencies,
            sessionStore: app.sessionStore,
            coordinator: app.navigationCoordinator,
            onboardingBuilder: app.onboardingBuilder,
            routinePlayerBuilder: app.routinePlayerBuilder
          )
        case .failed(let failure):
          BootstrapFailureView(
            message: failure.message,
            onRetry: bootstrapper.retry
          )
        }
      }
      .task {
        bootstrapper.start()
      }
      .preferredColorScheme(.light)
    }
  }
}

private struct BootstrapFailureView: View {
  let message: String
  let onRetry: @MainActor () -> Void

  var body: some View {
    VStack(spacing: 16) {
      ContentView(
        title: "저장소를 초기화할 수 없어요",
        message: message
      )
      Button("다시 시도", action: onRetry)
    }
  }
}
