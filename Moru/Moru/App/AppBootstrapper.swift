//
//  AppBootstrapper.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation
import SwiftData

struct BootstrappedApp {
  let modelContainer: ModelContainer
  let dependencies: DependencyContainer
  let sessionStore: SessionStore
  let navigationCoordinator: AppNavigationCoordinator
  let onboardingBuilder: any OnboardingFlowBuilding
  let routinePlayerBuilder: any RoutinePlayerBuilding
}

struct AppBootstrapFailure: Equatable {
  let message: String
}

enum AppBootstrapState {
  case idle
  case loading
  case ready(BootstrappedApp)
  case failed(AppBootstrapFailure)
}

@MainActor
final class AppBootstrapper: ObservableObject {
  @Published private(set) var state: AppBootstrapState = .idle

  private let modelContainerFactory: () throws -> ModelContainer

  init(
    modelContainerFactory: @escaping () throws -> ModelContainer = {
      try ModelContainer.moruContainer()
    }
  ) {
    self.modelContainerFactory = modelContainerFactory
  }

  func start() {
    guard case .idle = state else {
      return
    }

    constructReadyGraph()
  }

  func retry() {
    guard case .failed = state else {
      return
    }

    constructReadyGraph()
  }

  private func constructReadyGraph() {
    state = .loading

    do {
      let modelContainer = try modelContainerFactory()
      let dependencies = DependencyContainer.local(modelContext: modelContainer.mainContext)
      let sessionStore = dependencies.makeSessionStore()
      let navigationCoordinator = AppNavigationCoordinator()
      let onboardingBuilder = dependencies.makeOnboardingBuilder()
      let routinePlayerBuilder = dependencies.makeRoutinePlayerBuilder()

      state = .ready(
        BootstrappedApp(
          modelContainer: modelContainer,
          dependencies: dependencies,
          sessionStore: sessionStore,
          navigationCoordinator: navigationCoordinator,
          onboardingBuilder: onboardingBuilder,
          routinePlayerBuilder: routinePlayerBuilder
        )
      )
    } catch {
      state = .failed(
        AppBootstrapFailure(
          message: "저장소를 초기화할 수 없어요. 다시 시도해 주세요."
        )
      )
    }
  }
}
