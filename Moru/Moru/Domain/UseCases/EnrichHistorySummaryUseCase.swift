//
//  EnrichHistorySummaryUseCase.swift
//  Moru
//

import Foundation

@MainActor
protocol HistorySummaryEnriching: AnyObject {
  func enrich(_ localOverview: HistoryOverview) async throws -> HistoryOverview
}

@MainActor
final class AccountHistorySummaryEnricher: HistorySummaryEnriching {
  private let remoteService: any AccountHistoryRemoteServing
  private let signedInMemberProvider: any SignedInMemberProviding

  init(
    remoteService: any AccountHistoryRemoteServing,
    signedInMemberProvider: any SignedInMemberProviding
  ) {
    self.remoteService = remoteService
    self.signedInMemberProvider = signedInMemberProvider
  }

  func enrich(
    _ localOverview: HistoryOverview
  ) async throws -> HistoryOverview {
    guard let memberID = signedInMemberProvider.signedInMemberID,
          let requestedMonth = requestedMonth(for: localOverview) else {
      return localOverview
    }

    let serverSummary = try await remoteService.fetchSummary(
      year: requestedMonth.year,
      month: requestedMonth.month,
      memberID: memberID
    )
    let executionCount = try await fetchAccountExecutionCount(
      serverSummary.weekly,
      localWeek: localOverview.week,
      calendar: requestedMonth.calendar,
      memberID: memberID
    )
    try Task.checkCancellation()

    guard signedInMemberProvider.signedInMemberID == memberID else {
      return localOverview
    }

    return merge(
      serverSummary,
      into: localOverview,
      serverCalendar: requestedMonth.calendar,
      accountExecutionCount: executionCount
    )
  }

  private func requestedMonth(
    for overview: HistoryOverview
  ) -> (year: Int, month: Int, calendar: Calendar)? {
    var serverCalendar = Calendar(identifier: .gregorian)
    serverCalendar.timeZone = overview.calendar.timeZone
    let components = serverCalendar.dateComponents(
      [.year, .month],
      from: overview.monthlyHeatmap.monthStartDate
    )

    guard let year = components.year,
          let month = components.month else {
      return nil
    }

    return (year, month, serverCalendar)
  }

  private func merge(
    _ server: ServerHistorySummary,
    into local: HistoryOverview,
    serverCalendar: Calendar,
    accountExecutionCount: Int?
  ) -> HistoryOverview {
    let mergedWeek = mergeWeek(
      server.weekly,
      into: local.week,
      executionCount: accountExecutionCount
    )
    let mergedHeatmap = mergeMonth(
      server.monthlyDays,
      into: local.monthlyHeatmap,
      serverCalendar: serverCalendar
    )
    let mergedWakeMetrics = mergeWakePattern(
      server.wakePattern,
      into: local.wakeMetrics
    )
    let didUseAccountSummary =
      mergedWeek != local.week
      || mergedHeatmap != local.monthlyHeatmap
      || mergedWakeMetrics != local.wakeMetrics

    guard didUseAccountSummary else {
      return local
    }

    return HistoryOverview(
      calendar: local.calendar,
      recentDays: local.recentDays,
      week: mergedWeek,
      wakeMetrics: mergedWakeMetrics,
      monthlyHeatmap: mergedHeatmap,
      streak: local.streak,
      summarySource: .account
    )
  }

  private func mergeWakePattern(
    _ server: ServerHistoryWakePattern?,
    into local: HistoryWakeMetrics
  ) -> HistoryWakeMetrics {
    guard local == .unavailable,
          let server else {
      return local
    }

    return .account(
      HistoryAccountWakeMetrics(
        averageWakeMinute: server.averageWakeMinute,
        wakeTimeDifferenceMinutes:
          server.wakeTimeDifferenceMinutes,
        regularityScore: server.regularityScore,
        standardDeviationMinutes:
          server.standardDeviationMinutes,
        regularityLabel: server.regularityLabel
      )
    )
  }

  private func mergeWeek(
    _ server: ServerHistoryWeeklySummary,
    into local: HistoryWeekReport,
    executionCount: Int?
  ) -> HistoryWeekReport {
    guard local.totalRunCount == 0,
          local.dailyCompletionRates.count
            == ServerHistoryWeekday.allCases.count,
          server.dailyCompletions.contains(where: {
            $0.completionRate != nil
          })
            || server.completionRate > 0
            || server.totalDurationSeconds > 0
            || !server.routineStats.isEmpty else {
      return local
    }

    var completionByWeekday:
      [ServerHistoryWeekday: ServerHistoryWeekdayCompletion] = [:]
    for completion in server.dailyCompletions {
      guard completionByWeekday[completion.weekday] == nil else {
        return local
      }
      completionByWeekday[completion.weekday] = completion
    }
    guard completionByWeekday.count
            == ServerHistoryWeekday.allCases.count else {
      return local
    }

    let dailyCompletions = ServerHistoryWeekday.allCases.enumerated().map {
      offset,
      weekday in
      let serverCompletion = completionByWeekday[weekday]
      return HistoryDailyCompletion(
        date: local.dailyCompletionRates[offset].date,
        completionRate: serverCompletion?.completionRate ?? 0,
        hasData: serverCompletion?.completionRate != nil
      )
    }

    return HistoryWeekReport(
      weekStartDate: local.weekStartDate,
      weekEndDate: local.weekEndDate,
      completedRunCount: local.completedRunCount,
      totalRunCount: local.totalRunCount,
      completionRate: server.completionRate,
      dailyCompletionRates: dailyCompletions,
      completionRateChangePercentagePoints:
        server.completionRateChangePercentagePoints,
      totalDurationSeconds: server.totalDurationSeconds,
      executionCount: executionCount,
      routineStats: server.routineStats.map {
        HistoryWeeklyRoutineStat(
          routineID: $0.routineID,
          title: $0.title,
          completionRate: $0.completionRate
        )
      },
      summarySource: .account
    )
  }

  private func fetchAccountExecutionCount(
    _ server: ServerHistoryWeeklySummary,
    localWeek: HistoryWeekReport,
    calendar: Calendar,
    memberID: Int64
  ) async throws -> Int? {
    guard localWeek.totalRunCount == 0,
          localWeek.dailyCompletionRates.count
            == ServerHistoryWeekday.allCases.count else {
      return nil
    }

    var completionByWeekday:
      [ServerHistoryWeekday: ServerHistoryWeekdayCompletion] = [:]
    for completion in server.dailyCompletions {
      guard completionByWeekday[completion.weekday] == nil else {
        return nil
      }
      completionByWeekday[completion.weekday] = completion
    }
    guard completionByWeekday.count
            == ServerHistoryWeekday.allCases.count else {
      return nil
    }

    let requestedDates = ServerHistoryWeekday.allCases.enumerated().compactMap {
      offset,
      weekday -> DateComponents? in
      guard completionByWeekday[weekday]?.completionRate != nil else {
        return nil
      }

      return calendar.dateComponents(
        [.year, .month, .day],
        from: localWeek.dailyCompletionRates[offset].date
      )
    }
    guard !requestedDates.isEmpty else {
      return nil
    }

    do {
      return try await withThrowingTaskGroup(of: Int.self) { group in
        for components in requestedDates {
          guard let year = components.year,
                let month = components.month,
                let day = components.day else {
            return nil
          }

          group.addTask { [remoteService] in
            let report = try await remoteService.fetchDaily(
              year: year,
              month: month,
              day: day,
              memberID: memberID
            )
            return report.routines.count
          }
        }

        var count = 0
        for try await dailyCount in group {
          count += dailyCount
        }
        return count
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch AccountHistoryRemoteError.accountAuthorizationChanged {
      throw AccountHistoryRemoteError.accountAuthorizationChanged
    } catch {
      return nil
    }
  }

  private func mergeMonth(
    _ serverDays: [ServerHistoryMonthlyDay],
    into local: HistoryMonthlyHeatmap,
    serverCalendar: Calendar
  ) -> HistoryMonthlyHeatmap {
    let remoteRatesByDay = Dictionary(
      uniqueKeysWithValues: serverDays.map {
        ($0.day, $0.completionRate)
      }
    )

    let days = local.days.map { localDay in
      guard localDay.completionRate == nil,
            let date = localDay.date,
            let day = serverCalendar.dateComponents(
              [.day],
              from: date
            ).day,
            let remoteRate = remoteRatesByDay[day] else {
        return localDay
      }

      return HistoryHeatmapDay(
        id: localDay.id,
        date: date,
        completionRate: remoteRate,
        summarySource: .account
      )
    }

    return HistoryMonthlyHeatmap(
      monthStartDate: local.monthStartDate,
      days: days
    )
  }

}
