//
//  HistoryFlowBuilder.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

@MainActor
protocol HistoryFlowBuilding: AnyObject {
  func make(destination: Binding<HistoryDestination?>) -> AnyView
}

@MainActor
final class DefaultHistoryFlowBuilder: HistoryFlowBuilding {
  private let loadHistoryUseCase: any LoadHistoryUseCaseProtocol

  init(loadHistoryUseCase: any LoadHistoryUseCaseProtocol) {
    self.loadHistoryUseCase = loadHistoryUseCase
  }

  func make(destination: Binding<HistoryDestination?>) -> AnyView {
    AnyView(
      HistoryView(
        viewModel: HistoryViewModel(loadHistoryUseCase: loadHistoryUseCase),
        destination: destination
      )
    )
  }
}
