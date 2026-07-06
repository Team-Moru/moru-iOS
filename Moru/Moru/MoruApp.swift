//
//  MoruApp.swift
//  Moru
//
//  Created by 민혁 on 6/28/26.
//

import SwiftUI

@main
struct MoruApp: App {
  private let bootstrapState: AppBootstrapState

  @MainActor
  init() {
    bootstrapState = AppBootstrapper.make()
  }

  var body: some Scene {
    WindowGroup {
      switch bootstrapState {
      case .ready(let runtime):
        AppRouter(
          dependencies: runtime.dependencies,
          sessionStore: runtime.sessionStore
        )
      case .failed(let failure):
        AppRouter(bootstrapFailureMessage: failure.message)
      }
    }
  }
}
