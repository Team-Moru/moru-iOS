//
//  RemoteHistoryDataSource.swift
//  Moru
//

import Foundation

nonisolated final class DefaultAccountHistoryRemoteService:
  AccountHistoryRemoteServing {
  private static let validYearRange = 2000...9999
  private static let validMonthRange = 1...12

  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary {
    guard memberID > 0,
          Self.validYearRange.contains(year),
          Self.validMonthRange.contains(month) else {
      throw AccountHistoryRemoteError.invalidRequest
    }

    do {
      async let weeklyResponse = apiClient.request(
        HistoryTarget.weekly,
        as: HistoryWeeklyResponseDTO.self,
        authorizedForMemberID: memberID
      )
      async let monthlyResponse = apiClient.request(
        HistoryTarget.monthly(year: year, month: month),
        as: [HistoryMonthlyDayDTO].self,
        authorizedForMemberID: memberID
      )
      let (weekly, monthly) = try await (
        weeklyResponse,
        monthlyResponse
      )
      try _Concurrency.Task<Never, Never>.checkCancellation()

      return ServerHistorySummary(
        weekly: try weekly.makeDomainModel(),
        monthlyDays: try monthly.makeDomainModels(
          requestedYear: year,
          requestedMonth: month
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.cancelled {
      throw CancellationError()
    } catch is AccountAuthorizationContextError {
      throw AccountHistoryRemoteError.accountAuthorizationChanged
    }
  }
}

nonisolated private extension HistoryWeeklyResponseDTO {
  func makeDomainModel() throws -> ServerHistoryWeeklySummary {
    guard Self.isValidPercentage(completionRate),
          (-100...100).contains(completionRateDiff),
          totalDurationSecond >= 0,
          weeklyCompletionRate.count
            == ServerHistoryWeekday.allCases.count else {
      throw AccountHistoryRemoteError.invalidResponse
    }

    var completionsByWeekday:
      [ServerHistoryWeekday: ServerHistoryWeekdayCompletion] = [:]

    for completion in weeklyCompletionRate {
      guard let weekday = ServerHistoryWeekday(rawValue: completion.day),
            completionsByWeekday[weekday] == nil,
            completion.completionRate.map(Self.isValidPercentage) ?? true else {
        throw AccountHistoryRemoteError.invalidResponse
      }

      completionsByWeekday[weekday] = ServerHistoryWeekdayCompletion(
        weekday: weekday,
        completionRate: completion.completionRate.map(Self.normalizedRate)
      )
    }

    guard completionsByWeekday.count
            == ServerHistoryWeekday.allCases.count else {
      throw AccountHistoryRemoteError.invalidResponse
    }

    var seenRoutineIDs: Set<Int64> = []
    let mappedRoutineStats = try routineStats.map { stat in
      let normalizedTitle = stat.title.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard stat.routineId > 0,
            seenRoutineIDs.insert(stat.routineId).inserted,
            !normalizedTitle.isEmpty,
            Self.isValidPercentage(stat.completionRate) else {
        throw AccountHistoryRemoteError.invalidResponse
      }

      return ServerHistoryRoutineStat(
        routineID: stat.routineId,
        title: normalizedTitle,
        completionRate: Self.normalizedRate(stat.completionRate)
      )
    }

    return ServerHistoryWeeklySummary(
      completionRate: Self.normalizedRate(completionRate),
      completionRateChangePercentagePoints: completionRateDiff,
      totalDurationSeconds: totalDurationSecond,
      dailyCompletions: try ServerHistoryWeekday.allCases.map { weekday in
        guard let completion = completionsByWeekday[weekday] else {
          throw AccountHistoryRemoteError.invalidResponse
        }
        return completion
      },
      routineStats: mappedRoutineStats
    )
  }

  static func isValidPercentage(_ percentage: Int) -> Bool {
    (0...100).contains(percentage)
  }

  static func normalizedRate(_ percentage: Int) -> Double {
    Double(percentage) / 100
  }
}

nonisolated private extension Array where Element == HistoryMonthlyDayDTO {
  func makeDomainModels(
    requestedYear: Int,
    requestedMonth: Int
  ) throws -> [ServerHistoryMonthlyDay] {
    var seenDays: Set<Int> = []

    return try map { execution in
      guard let date = ServerHistoryDateParser.parse(execution.executedDate),
            date.year == requestedYear,
            date.month == requestedMonth,
            seenDays.insert(date.day).inserted,
            (0...100).contains(execution.completionRate) else {
        throw AccountHistoryRemoteError.invalidResponse
      }

      return ServerHistoryMonthlyDay(
        year: date.year,
        month: date.month,
        day: date.day,
        completionRate: Double(execution.completionRate) / 100
      )
    }
    .sorted { $0.day < $1.day }
  }
}

nonisolated private enum ServerHistoryDateParser {
  struct Components {
    let year: Int
    let month: Int
    let day: Int
  }

  static func parse(_ value: String) -> Components? {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
          parts[0].count == 4,
          parts[1].count == 2,
          parts[2].count == 2,
          parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2]),
          (1...12).contains(month),
          (1...daysInMonth(year: year, month: month)).contains(day) else {
      return nil
    }

    return Components(year: year, month: month, day: day)
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2:
      isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11:
      30
    default:
      31
    }
  }

  private static func isLeapYear(_ year: Int) -> Bool {
    year.isMultiple(of: 400)
      || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
  }
}
