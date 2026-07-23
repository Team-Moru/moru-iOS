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
  private let weatherRepository: (any HomeWeatherRepository)?
  private let weatherService: (any HomeWeatherService)?
  private let routineSettingContentFactory: @MainActor () -> AnyView
  private let routineCreationContentFactory: @MainActor () -> AnyView

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol,
    weatherRepository: (any HomeWeatherRepository)? = nil,
    weatherService: (any HomeWeatherService)? = nil,
    routineSettingContentFactory: @escaping @MainActor () -> AnyView,
    routineCreationContentFactory: (@MainActor () -> AnyView)? = nil
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.weatherRepository = weatherRepository
    self.weatherService = weatherService
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
          weatherRepository: weatherRepository,
          weatherService: weatherService
        ),
        onStartRoutine: onStartRoutine,
        refreshToken: refreshToken,
        routineSettingContent: routineSettingContentFactory(),
        routineCreationContent: routineCreationContentFactory()
      )
    )
  }
}
