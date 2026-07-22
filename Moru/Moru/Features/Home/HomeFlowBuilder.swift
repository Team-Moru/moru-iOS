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
  private let routineSettingContentFactory: @MainActor () -> AnyView

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol,
    routineSettingContentFactory: @escaping @MainActor () -> AnyView
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.routineSettingContentFactory = routineSettingContentFactory
  }

  func make(
    onStartRoutine: @escaping RoutineLaunchHandler,
    refreshToken: Int
  ) -> AnyView {
    AnyView(
      HomeView(
        viewModel: HomeViewModel(loadHomeRoutinesUseCase: loadHomeRoutinesUseCase),
        onStartRoutine: onStartRoutine,
        refreshToken: refreshToken,
        routineSettingContent: routineSettingContentFactory()
      )
    )
  }
}
