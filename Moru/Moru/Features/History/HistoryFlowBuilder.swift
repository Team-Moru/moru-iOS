//
//  HistoryFlowBuilder.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

@MainActor
protocol HistoryFlowBuilding: AnyObject {
  /// - Parameter reloadToken: 값이 바뀌면 이력 데이터를 다시 불러온다(정체성은 유지).
  func make(
    destination: Binding<HistoryDestination?>,
    reloadToken: Int
  ) -> AnyView
}

@MainActor
final class DefaultHistoryFlowBuilder: HistoryFlowBuilding {
  private let loadHistoryUseCase: any LoadHistoryUseCaseProtocol
  private let summaryEnricher: (any HistorySummaryEnriching)?
  private let accountDailyReportLoader:
    (any AccountHistoryDailyReportLoading)?
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?

  init(
    loadHistoryUseCase: any LoadHistoryUseCaseProtocol,
    summaryEnricher: (any HistorySummaryEnriching)? = nil,
    accountDailyReportLoader:
      (any AccountHistoryDailyReportLoading)? = nil,
    signedInMemberProvider: (any SignedInMemberProviding)? = nil
  ) {
    self.loadHistoryUseCase = loadHistoryUseCase
    self.summaryEnricher = summaryEnricher
    self.accountDailyReportLoader = accountDailyReportLoader
    self.signedInMemberProvider = signedInMemberProvider
  }

  func make(
    destination: Binding<HistoryDestination?>,
    reloadToken: Int
  ) -> AnyView {
    AnyView(
      HistoryView(
        viewModel: HistoryViewModel(
          loadHistoryUseCase: loadHistoryUseCase,
          summaryEnricher: summaryEnricher
        ),
        accountDailyReportLoader: accountDailyReportLoader,
        destination: destination,
        reloadToken: reloadToken
      )
      // 계정이 바뀌면 이력 화면을 새로 만든다. 빌더가 아니라 make 시점의 회원을 읽는다.
      .id(signedInMemberProvider?.signedInMemberID)
    )
  }
}
