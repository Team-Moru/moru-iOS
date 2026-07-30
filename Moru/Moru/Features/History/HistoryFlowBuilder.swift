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
  private let summaryEnricher: (any HistorySummaryEnriching)?
  private let accountIdentity: Int64?

  init(
    loadHistoryUseCase: any LoadHistoryUseCaseProtocol,
    summaryEnricher: (any HistorySummaryEnriching)? = nil,
    accountIdentity: Int64? = nil
  ) {
    self.loadHistoryUseCase = loadHistoryUseCase
    self.summaryEnricher = summaryEnricher
    self.accountIdentity = accountIdentity
  }

  func make(destination: Binding<HistoryDestination?>) -> AnyView {
    AnyView(
      HistoryView(
        viewModel: HistoryViewModel(
          loadHistoryUseCase: loadHistoryUseCase,
          summaryEnricher: summaryEnricher
        ),
        destination: destination
      )
      .id(accountIdentity)
    )
  }
}
