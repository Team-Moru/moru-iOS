//
//  MoruApp.swift
//  Moru
//
//  Created by 민혁 on 6/28/26.
//

import SwiftData
import SwiftUI

@main
struct MoruApp: App {
  private let modelContainer: ModelContainer
  private let dependencies: DependencyContainer
  @State private var sessionStore: SessionStore

  @MainActor
  init() {
    do {
      let modelContainer = try ModelContainer.moruContainer()
      let dependencies = DependencyContainer.local(modelContext: modelContainer.mainContext)

      self.modelContainer = modelContainer
      self.dependencies = dependencies
      self._sessionStore = State(
        initialValue: SessionStore(localProfileRepository: dependencies.localProfileRepository)
      )
    } catch {
      fatalError("Failed to initialize Moru storage: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      AppRouter(
        dependencies: dependencies,
        sessionStore: sessionStore
      )
      .modelContainer(modelContainer)
    }
  }
}
