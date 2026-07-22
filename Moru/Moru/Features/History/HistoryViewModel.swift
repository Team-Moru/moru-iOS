//
//  HistoryViewModel.swift
//  Moru
//
//  Created by Codex on 7/14/26.
//

import Observation

@MainActor
enum HistoryViewState {
  case loading
  case content(HistoryOverview)
  case empty
  case failed(message: String)
}

@MainActor
@Observable
final class HistoryViewModel {
  private let loadHistoryUseCase: any LoadHistoryUseCaseProtocol

  var state: HistoryViewState = .loading

  init(loadHistoryUseCase: any LoadHistoryUseCaseProtocol) {
    self.loadHistoryUseCase = loadHistoryUseCase
  }

  func load() {
    state = .loading

    do {
      let overview = try loadHistoryUseCase.load()
      state = overview.recentDays.isEmpty ? .empty : .content(overview)
    } catch {
      state = .failed(message: "기록을 불러오지 못했어요.")
    }
  }

  func retryButtonDidTap() {
    load()
  }
}
