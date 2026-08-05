//
//  HistoryViewModel.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Observation

@MainActor
enum HistoryViewState: Equatable {
  case loading
  case content(HistoryOverview)
  case empty
  case failed(message: String)
}

@MainActor
@Observable
final class HistoryViewModel {
  private let loadHistoryUseCase: any LoadHistoryUseCaseProtocol
  private let summaryEnricher: (any HistorySummaryEnriching)?
  private var loadGeneration = 0

  var state: HistoryViewState = .loading

  init(
    loadHistoryUseCase: any LoadHistoryUseCaseProtocol,
    summaryEnricher: (any HistorySummaryEnriching)? = nil
  ) {
    self.loadHistoryUseCase = loadHistoryUseCase
    self.summaryEnricher = summaryEnricher
  }

  func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    state = .loading

    do {
      let localOverview = try loadHistoryUseCase.load()
      guard generation == loadGeneration else {
        return
      }

      guard let summaryEnricher else {
        state = state(for: localOverview)
        return
      }

      if localOverview.hasDisplayableHistory {
        state = .content(localOverview)
      }

      do {
        let enrichedOverview = try await summaryEnricher.enrich(localOverview)
        try Task.checkCancellation()
        guard generation == loadGeneration else {
          return
        }
        state = state(for: enrichedOverview)
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else {
          return
        }
        state = localOverview.hasDisplayableHistory
          ? .content(localOverview)
          : .failed(message: "기록을 불러오지 못했어요.")
      }
    } catch {
      guard generation == loadGeneration else {
        return
      }
      state = .failed(message: "기록을 불러오지 못했어요.")
    }
  }

  func retryButtonDidTap() async {
    await load()
  }

  private func state(for overview: HistoryOverview) -> HistoryViewState {
    overview.hasDisplayableHistory ? .content(overview) : .empty
  }
}
