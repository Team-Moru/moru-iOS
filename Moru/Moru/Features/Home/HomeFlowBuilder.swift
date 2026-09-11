//
//  HomeFlowBuilder.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

@MainActor
protocol HomeFlowBuilding: AnyObject {
  func make(
    onStartRoutine: @escaping RoutineLaunchHandler,
    onOpenRoutineSettings: @escaping (UUID?) -> Void,
    refreshToken: Int
  ) -> AnyView
}

@MainActor
final class DefaultHomeFlowBuilder: HomeFlowBuilding {
  private let loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol
  private let enrichHomeRoutinesUseCase:
    (any EnrichHomeRoutinesUseCaseProtocol)?
  private let weatherRepository: (any HomeWeatherRepository)?
  private let weatherService: (any HomeWeatherService)?
  private weak var sessionIdentityProvider:
    (any CurrentAccountSessionIdentityProviding)?
  private let routineCreationContentFactory: @MainActor () -> AnyView

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol,
    enrichHomeRoutinesUseCase:
      (any EnrichHomeRoutinesUseCaseProtocol)? = nil,
    weatherRepository: (any HomeWeatherRepository)? = nil,
    weatherService: (any HomeWeatherService)? = nil,
    sessionIdentityProvider:
      (any CurrentAccountSessionIdentityProviding)? = nil,
    routineCreationContentFactory: @escaping @MainActor () -> AnyView
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.enrichHomeRoutinesUseCase = enrichHomeRoutinesUseCase
    self.weatherRepository = weatherRepository
    self.weatherService = weatherService
    self.sessionIdentityProvider = sessionIdentityProvider
    self.routineCreationContentFactory = routineCreationContentFactory
  }

  func make(
    onStartRoutine: @escaping RoutineLaunchHandler,
    onOpenRoutineSettings: @escaping (UUID?) -> Void,
    refreshToken: Int
  ) -> AnyView {
    AnyView(
      HomeView(
        viewModel: HomeViewModel(
          loadHomeRoutinesUseCase: loadHomeRoutinesUseCase,
          enrichHomeRoutinesUseCase: enrichHomeRoutinesUseCase,
          weatherRepository: weatherRepository,
          weatherService: weatherService
        ),
        onStartRoutine: onStartRoutine,
        refreshToken: refreshToken,
        onOpenRoutineSettings: onOpenRoutineSettings,
        routineCreationContent: routineCreationContentFactory()
      )
      .id(sessionIdentityProvider?.currentAccountSessionIdentity?.sessionID)
    )
  }
}
