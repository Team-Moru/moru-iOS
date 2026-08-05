//
//  HistoryAccountDailyViewModel.swift
//  Moru
//

import Foundation
import Observation

@MainActor
enum HistoryAccountDailyViewState: Equatable {
  case loading
  case content(ServerHistoryDailySummary)
  case failed(message: String)
}

@MainActor
@Observable
final class HistoryAccountDailyViewModel {
  let date: Date
  let calendar: Calendar

  private let loader: any AccountHistoryDailyReportLoading
  private var loadGeneration = 0

  var state: HistoryAccountDailyViewState = .loading

  init(
    date: Date,
    calendar: Calendar,
    loader: any AccountHistoryDailyReportLoading
  ) {
    self.date = date
    self.calendar = calendar
    self.loader = loader
  }

  func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    state = .loading

    do {
      let report = try await loader.load(
        for: date,
        calendar: calendar
      )
      try Task.checkCancellation()
      guard generation == loadGeneration else {
        return
      }

      if let report {
        state = .content(report)
      } else {
        state = .failed(message: HistoryCopy.accountDailyUnavailable)
      }
    } catch is CancellationError {
      return
    } catch {
      guard generation == loadGeneration else {
        return
      }
      state = .failed(message: HistoryCopy.accountDailyLoadFailed)
    }
  }

  func retryButtonDidTap() async {
    await load()
  }
}
