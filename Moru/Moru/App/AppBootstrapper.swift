//
//  AppBootstrapper.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

struct AppRuntime {
  let modelContainer: ModelContainer
  let dependencies: DependencyContainer
  let sessionStore: SessionStore
}

struct AppBootstrapFailure: Equatable {
  let message: String
}

enum AppBootstrapState {
  case ready(AppRuntime)
  case failed(AppBootstrapFailure)
}

enum AppBootstrapper {
  @MainActor
  static func make(
    modelContainerFactory: () throws -> ModelContainer = {
      try ModelContainer.moruContainer()
    }
  ) -> AppBootstrapState {
    do {
      let modelContainer = try modelContainerFactory()
      let dependencies = DependencyContainer.local(modelContext: modelContainer.mainContext)
      let sessionStore = SessionStore(
        localProfileRepository: dependencies.localProfileRepository
      )
      return .ready(
        AppRuntime(
          modelContainer: modelContainer,
          dependencies: dependencies,
          sessionStore: sessionStore
        )
      )
    } catch {
      let message = "저장소 초기화에 실패했습니다. 앱을 다시 실행해 주세요."
      return .failed(
        AppBootstrapFailure(
          message: "\(message) \(error.localizedDescription)"
        )
      )
    }
  }
}
