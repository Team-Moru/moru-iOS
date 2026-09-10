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
  private let routineSettingContentFactory: @MainActor () -> AnyView
  private let routineCreationContentFactory: @MainActor () -> AnyView

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol,
    enrichHomeRoutinesUseCase:
      (any EnrichHomeRoutinesUseCaseProtocol)? = nil,
    weatherRepository: (any HomeWeatherRepository)? = nil,
    weatherService: (any HomeWeatherService)? = nil,
    sessionIdentityProvider:
      (any CurrentAccountSessionIdentityProviding)? = nil,
    routineSettingContentFactory: @escaping @MainActor () -> AnyView,
    routineCreationContentFactory: (@MainActor () -> AnyView)? = nil
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.enrichHomeRoutinesUseCase = enrichHomeRoutinesUseCase
    self.weatherRepository = weatherRepository
    self.weatherService = weatherService
    self.sessionIdentityProvider = sessionIdentityProvider
    self.routineSettingContentFactory = routineSettingContentFactory
    self.routineCreationContentFactory =
      routineCreationContentFactory ?? routineSettingContentFactory
  }

  func make(
    onStartRoutine: @escaping RoutineLaunchHandler,
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
        routineSettingContent: routineSettingContentFactory(),
        routineCreationContent: routineCreationContentFactory()
      )
      .id(sessionIdentityProvider?.currentAccountSessionIdentity?.sessionID)
    )
  }
}
