//
//  LoadAccountHistoryDailyReportUseCase.swift
//  Moru
//

import Foundation

@MainActor
protocol AccountHistoryDailyReportLoading: AnyObject {
  func load(
    for date: Date,
    calendar: Calendar
  ) async throws -> ServerHistoryDailySummary?
}

@MainActor
final class LoadAccountHistoryDailyReportUseCase:
  AccountHistoryDailyReportLoading {
  private let remoteService: any AccountHistoryRemoteServing
  private let signedInMemberProvider: any SignedInMemberProviding

  init(
    remoteService: any AccountHistoryRemoteServing,
    signedInMemberProvider: any SignedInMemberProviding
  ) {
    self.remoteService = remoteService
    self.signedInMemberProvider = signedInMemberProvider
  }

  func load(
    for date: Date,
    calendar: Calendar
  ) async throws -> ServerHistoryDailySummary? {
    guard let memberID = signedInMemberProvider.signedInMemberID else {
      return nil
    }

    var serverCalendar = Calendar(identifier: .gregorian)
    serverCalendar.timeZone = calendar.timeZone
    let components = serverCalendar.dateComponents(
      [.year, .month, .day],
      from: date
    )
    guard let year = components.year,
          let month = components.month,
          let day = components.day else {
      return nil
    }

    let report = try await remoteService.fetchDaily(
      year: year,
      month: month,
      day: day,
      memberID: memberID
    )
    try Task.checkCancellation()

    guard signedInMemberProvider.signedInMemberID == memberID else {
      return nil
    }

    return report
  }
}
