//
//  HistoryServerEnrichmentTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

final class HistoryServerEnrichmentTests: XCTestCase {
  @MainActor
  func testRemoteWeekIsUsedOnlyWithoutLocalWeekRuns() async throws {
    let local = makeOverview(
      recentDays: [],
      weekRunCount: 0,
      weekCompletionRate: 0,
      monthlyRates: [nil, nil]
    )
    let remote = makeServerSummary(
      weeklyRate: 0.75,
      dailyRates: [1, 0, nil, nil, nil, nil, nil],
      totalDurationSeconds: 1_200,
      routineStats: [
        ServerHistoryRoutineStat(
          routineID: 17,
          title: "물 마시기",
          completionRate: 0.8
        ),
      ],
      monthlyDays: []
    )
    let service = RecordingAccountHistoryRemoteService(result: .success(remote))
    let memberProvider = MutableSignedInMemberProvider(memberID: 41)
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: memberProvider
    )

    let result = try await enricher.enrich(local)

    XCTAssertEqual(result.summarySource, .account)
    XCTAssertEqual(result.week.summarySource, .account)
    XCTAssertEqual(result.week.completionRate, 0.75)
    XCTAssertEqual(result.week.dailyCompletionRates.map(\.completionRate), [
      1, 0, 0, 0, 0, 0, 0,
    ])
    XCTAssertEqual(result.week.dailyCompletionRates.map(\.hasData), [
      true, true, false, false, false, false, false,
    ])
    XCTAssertEqual(result.week.totalRunCount, 0)
    XCTAssertEqual(result.week.completedRunCount, 0)
    XCTAssertEqual(result.week.totalDurationSeconds, 1_200)
    XCTAssertEqual(result.weeklyDurationTitle, HistoryCopy.averageDuration)
    XCTAssertEqual(result.weeklyDurationText, "10:00")
    XCTAssertEqual(
      result.week.routineStats,
      [
        HistoryWeeklyRoutineStat(
          routineID: 17,
          title: "물 마시기",
          completionRate: 0.8
        ),
      ]
    )
    XCTAssertTrue(result.recentDays.isEmpty)
    let requestedMemberIDs = await service.requestedMemberIDs
    XCTAssertEqual(requestedMemberIDs, [41])
  }

  @MainActor
  func testAccountAverageDurationRequiresAnExecutionCount() async throws {
    let local = makeOverview(
      recentDays: [],
      weekRunCount: 0,
      weekCompletionRate: 0,
      monthlyRates: [nil, nil]
    )
    let remote = makeServerSummary(
      weeklyRate: 0,
      dailyRates: Array(repeating: nil, count: 7),
      totalDurationSeconds: 1_000
    )
    let enricher = AccountHistorySummaryEnricher(
      remoteService: RecordingAccountHistoryRemoteService(
        result: .success(remote)
      ),
      signedInMemberProvider: MutableSignedInMemberProvider(memberID: 41)
    )

    let result = try await enricher.enrich(local)

    XCTAssertEqual(result.week.summarySource, .account)
    XCTAssertEqual(result.weeklyDurationTitle, HistoryCopy.averageDuration)
    XCTAssertEqual(result.weeklyDurationText, "--:--")
  }

  @MainActor
  func testAccountAverageDurationUsesEveryDailyExecution() async throws {
    let local = makeOverview(
      recentDays: [],
      weekRunCount: 0,
      weekCompletionRate: 0,
      monthlyRates: [nil, nil]
    )
    let remote = makeServerSummary(
      weeklyRate: 0.75,
      dailyRates: [1, 0.5, nil, nil, nil, nil, nil],
      totalDurationSeconds: 900
    )
    let service = RecordingAccountHistoryRemoteService(
      result: .success(remote),
      dailyReportsByDay: [
        13: makeServerDailySummary(day: 13, routineCount: 2),
        14: makeServerDailySummary(day: 14, routineCount: 1),
      ]
    )
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: MutableSignedInMemberProvider(memberID: 41)
    )

    let result = try await enricher.enrich(local)

    XCTAssertEqual(result.week.executionCount, 3)
    XCTAssertEqual(result.weeklyDurationTitle, HistoryCopy.averageDuration)
    XCTAssertEqual(result.weeklyDurationText, "05:00")
    let requestedDays = await service.requestedDailyDays.sorted()
    XCTAssertEqual(requestedDays, [13, 14])
  }

  @MainActor
  func testLocalWeekMonthAndStreakStayAuthoritativeWhileServerFillsMonthGaps()
    async throws {
    let local = makeOverview(
      recentDays: [makeDaySummary()],
      weekRunCount: 1,
      weekCompletionRate: 0.25,
      monthlyRates: [0.25, nil],
      streak: RoutineStreak(
        currentDays: 2,
        bestDays: 4,
        completedWeekdays: [.monday]
      )
    )
    let remote = makeServerSummary(
      weeklyRate: 0.9,
      dailyRates: Array(repeating: 0.9, count: 7),
      monthlyDays: [
        ServerHistoryMonthlyDay(
          year: 2026,
          month: 7,
          day: 1,
          completionRate: 0.9
        ),
        ServerHistoryMonthlyDay(
          year: 2026,
          month: 7,
          day: 2,
          completionRate: 0.6
        ),
      ]
    )
    let enricher = AccountHistorySummaryEnricher(
      remoteService: RecordingAccountHistoryRemoteService(
        result: .success(remote)
      ),
      signedInMemberProvider: MutableSignedInMemberProvider(memberID: 7)
    )

    let result = try await enricher.enrich(local)

    XCTAssertEqual(result.summarySource, .account)
    XCTAssertEqual(result.week, local.week)
    XCTAssertEqual(
      result.monthlyHeatmap.days.compactMap(\.completionRate),
      [0.25, 0.6]
    )
    XCTAssertEqual(result.streak, local.streak)
    XCTAssertEqual(result.recentDays, local.recentDays)
    XCTAssertEqual(result.wakeMetrics, local.wakeMetrics)
  }

  @MainActor
  func testSignedOutHistorySkipsServerRequest() async throws {
    let local = makeOverview()
    let service = RecordingAccountHistoryRemoteService(
      result: .failure
    )
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: MutableSignedInMemberProvider(memberID: nil)
    )

    let result = try await enricher.enrich(local)

    XCTAssertEqual(result, local)
    let requestedMemberIDs = await service.requestedMemberIDs
    XCTAssertTrue(requestedMemberIDs.isEmpty)
  }

  @MainActor
  func testAccountChangeWhileRequestIsInFlightDiscardsServerSummary() async throws {
    let local = makeOverview()
    let service = DeferredAccountHistoryRemoteService()
    let memberProvider = MutableSignedInMemberProvider(memberID: 10)
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: memberProvider
    )
    let task = Task {
      try await enricher.enrich(local)
    }

    await service.waitUntilRequested()
    memberProvider.signedInMemberID = 11
    await service.resume(returning: makeServerSummary())

    let result = try await task.value
    XCTAssertEqual(result, local)
  }

  @MainActor
  func testAccountChangeDuringDailyCountDiscardsServerSummary() async throws {
    let local = makeOverview()
    let summary = makeServerSummary(
      weeklyRate: 1,
      dailyRates: [1, nil, nil, nil, nil, nil, nil],
      totalDurationSeconds: 300
    )
    let service = DeferredDailyAccountHistoryRemoteService(summary: summary)
    let memberProvider = MutableSignedInMemberProvider(memberID: 10)
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: memberProvider
    )
    let task = Task {
      try await enricher.enrich(local)
    }

    await service.waitUntilDailyRequested()
    memberProvider.signedInMemberID = 11
    await service.resumeDaily(
      returning: makeServerDailySummary(day: 13, routineCount: 1)
    )

    let result = try await task.value
    XCTAssertEqual(result, local)
  }

  @MainActor
  func testCancellingDailyCountCancelsHistoryEnrichment() async {
    let local = makeOverview()
    let summary = makeServerSummary(
      weeklyRate: 1,
      dailyRates: [1, nil, nil, nil, nil, nil, nil],
      totalDurationSeconds: 300
    )
    let service = CancellableDailyAccountHistoryRemoteService(summary: summary)
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: MutableSignedInMemberProvider(memberID: 10)
    )
    let task = Task {
      try await enricher.enrich(local)
    }

    await service.waitUntilDailyRequested()
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation to propagate from the daily count.")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, received \(error).")
    }
  }

  @MainActor
  func testViewModelPublishesLocalHistoryBeforeRemoteEnrichmentCompletes() async {
    let local = makeOverview(recentDays: [makeDaySummary()])
    let remote = HistoryOverview(
      calendar: local.calendar,
      recentDays: local.recentDays,
      week: local.week,
      wakeMetrics: local.wakeMetrics,
      monthlyHeatmap: local.monthlyHeatmap,
      streak: RoutineStreak(
        currentDays: 5,
        bestDays: 8,
        completedWeekdays: [.monday]
      ),
      summarySource: .account
    )
    let enricher = DeferredHistorySummaryEnricher()
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: StaticHistoryLoadUseCase(overview: local),
      summaryEnricher: enricher
    )
    let loadTask = Task {
      await viewModel.load()
    }

    await enricher.waitUntilRequested()

    guard case .content(let immediateOverview) = viewModel.state else {
      XCTFail("Local history should be visible while the server request is pending.")
      return
    }
    XCTAssertEqual(immediateOverview, local)

    enricher.resume(returning: remote)
    await loadTask.value

    guard case .content(let enrichedOverview) = viewModel.state else {
      XCTFail("The server summary should enrich the existing content.")
      return
    }
    XCTAssertEqual(enrichedOverview, remote)
  }

  @MainActor
  func testViewModelKeepsLoadingUntilEmptyLocalHistoryIsEnriched() async {
    let local = makeOverview()
    let remote = overviewWithAccountStreak(3, basedOn: local)
    let enricher = DeferredHistorySummaryEnricher()
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: StaticHistoryLoadUseCase(overview: local),
      summaryEnricher: enricher
    )
    let loadTask = Task {
      await viewModel.load()
    }

    await enricher.waitUntilRequested()
    XCTAssertEqual(viewModel.state, .loading)

    enricher.resume(returning: remote)
    await loadTask.value

    XCTAssertEqual(viewModel.state, .content(remote))
  }

  @MainActor
  func testViewModelDistinguishesRemoteFailureFromEmptyHistory() async {
    let local = makeOverview()
    let enricher = DeferredHistorySummaryEnricher()
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: StaticHistoryLoadUseCase(overview: local),
      summaryEnricher: enricher
    )
    let loadTask = Task {
      await viewModel.load()
    }

    await enricher.waitUntilRequested()
    enricher.resume(throwing: HistoryServerEnrichmentTestError.unexpectedRequest)
    await loadTask.value

    XCTAssertEqual(
      viewModel.state,
      .failed(message: "기록을 불러오지 못했어요.")
    )
  }

  @MainActor
  func testViewModelPublishesEmptyOnlyAfterRemoteReturnsNoHistory() async {
    let local = makeOverview()
    let enricher = DeferredHistorySummaryEnricher()
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: StaticHistoryLoadUseCase(overview: local),
      summaryEnricher: enricher
    )
    let loadTask = Task {
      await viewModel.load()
    }

    await enricher.waitUntilRequested()
    enricher.resume(returning: local)
    await loadTask.value

    XCTAssertEqual(viewModel.state, .empty)
  }

  @MainActor
  func testOlderRemoteLoadCannotOverwriteNewerHistoryState() async {
    let local = makeOverview(recentDays: [makeDaySummary()])
    let firstRemote = overviewWithAccountStreak(1, basedOn: local)
    let secondRemote = overviewWithAccountStreak(9, basedOn: local)
    let enricher = SequencedDeferredHistorySummaryEnricher()
    let viewModel = HistoryViewModel(
      loadHistoryUseCase: StaticHistoryLoadUseCase(overview: local),
      summaryEnricher: enricher
    )
    let firstLoad = Task {
      await viewModel.load()
    }
    await enricher.waitForRequestCount(1)
    let secondLoad = Task {
      await viewModel.load()
    }
    await enricher.waitForRequestCount(2)

    enricher.resumeRequest(at: 1, returning: secondRemote)
    await secondLoad.value
    enricher.resumeRequest(at: 0, returning: firstRemote)
    await firstLoad.value

    guard case .content(let overview) = viewModel.state else {
      XCTFail("The latest load should remain visible.")
      return
    }
    XCTAssertEqual(overview, secondRemote)
  }
}

@MainActor
private final class MutableSignedInMemberProvider: SignedInMemberProviding {
  var signedInMemberID: Int64?

  init(memberID: Int64?) {
    signedInMemberID = memberID
  }
}

private actor RecordingAccountHistoryRemoteService:
  AccountHistoryRemoteServing {
  private(set) var requestedMemberIDs: [Int64] = []
  private(set) var requestedDailyDays: [Int] = []
  private let result: HistoryRemoteStubResult
  private let dailyReportsByDay: [Int: ServerHistoryDailySummary]

  init(
    result: HistoryRemoteStubResult,
    dailyReportsByDay: [Int: ServerHistoryDailySummary] = [:]
  ) {
    self.result = result
    self.dailyReportsByDay = dailyReportsByDay
  }

  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary {
    requestedMemberIDs.append(memberID)
    switch result {
    case .success(let summary):
      return summary
    case .failure:
      throw HistoryServerEnrichmentTestError.unexpectedRequest
    }
  }

  func fetchDaily(
    year: Int,
    month: Int,
    day: Int,
    memberID: Int64
  ) async throws -> ServerHistoryDailySummary {
    requestedDailyDays.append(day)
    guard let report = dailyReportsByDay[day] else {
      throw HistoryServerEnrichmentTestError.unexpectedRequest
    }
    return report
  }
}

private actor DeferredAccountHistoryRemoteService:
  AccountHistoryRemoteServing {
  private var continuation:
    CheckedContinuation<ServerHistorySummary, Error>?
  private var didRequest = false

  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary {
    didRequest = true
    return try await withCheckedThrowingContinuation {
      continuation = $0
    }
  }

  func fetchDaily(
    year: Int,
    month: Int,
    day: Int,
    memberID: Int64
  ) async throws -> ServerHistoryDailySummary {
    throw HistoryServerEnrichmentTestError.unexpectedRequest
  }

  func waitUntilRequested() async {
    while !didRequest {
      await Task.yield()
    }
  }

  func resume(returning summary: ServerHistorySummary) {
    continuation?.resume(returning: summary)
    continuation = nil
  }
}

private actor DeferredDailyAccountHistoryRemoteService:
  AccountHistoryRemoteServing {
  private let summary: ServerHistorySummary
  private var dailyContinuation:
    CheckedContinuation<ServerHistoryDailySummary, Error>?
  private var didRequestDaily = false

  init(summary: ServerHistorySummary) {
    self.summary = summary
  }

  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary {
    summary
  }

  func fetchDaily(
    year: Int,
    month: Int,
    day: Int,
    memberID: Int64
  ) async throws -> ServerHistoryDailySummary {
    didRequestDaily = true
    return try await withCheckedThrowingContinuation {
      dailyContinuation = $0
    }
  }

  func waitUntilDailyRequested() async {
    while !didRequestDaily {
      await Task.yield()
    }
  }

  func resumeDaily(returning report: ServerHistoryDailySummary) {
    dailyContinuation?.resume(returning: report)
    dailyContinuation = nil
  }
}

private actor CancellableDailyAccountHistoryRemoteService:
  AccountHistoryRemoteServing {
  private let summary: ServerHistorySummary
  private var didRequestDaily = false

  init(summary: ServerHistorySummary) {
    self.summary = summary
  }

  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary {
    summary
  }

  func fetchDaily(
    year: Int,
    month: Int,
    day: Int,
    memberID: Int64
  ) async throws -> ServerHistoryDailySummary {
    didRequestDaily = true
    try await Task.sleep(for: .seconds(30))
    return makeServerDailySummary(day: day, routineCount: 1)
  }

  func waitUntilDailyRequested() async {
    while !didRequestDaily {
      await Task.yield()
    }
  }
}

@MainActor
private final class StaticHistoryLoadUseCase: LoadHistoryUseCaseProtocol {
  private let overview: HistoryOverview

  init(overview: HistoryOverview) {
    self.overview = overview
  }

  func load() throws -> HistoryOverview {
    overview
  }
}

@MainActor
private final class DeferredHistorySummaryEnricher:
  HistorySummaryEnriching {
  private var continuation:
    CheckedContinuation<HistoryOverview, Error>?
  private var didRequest = false

  func enrich(
    _ localOverview: HistoryOverview
  ) async throws -> HistoryOverview {
    didRequest = true
    return try await withCheckedThrowingContinuation {
      continuation = $0
    }
  }

  func waitUntilRequested() async {
    while !didRequest {
      await Task.yield()
    }
  }

  func resume(returning overview: HistoryOverview) {
    continuation?.resume(returning: overview)
    continuation = nil
  }

  func resume(throwing error: any Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

@MainActor
private final class SequencedDeferredHistorySummaryEnricher:
  HistorySummaryEnriching {
  private var continuations: [
    CheckedContinuation<HistoryOverview, Error>?
  ] = []

  func enrich(
    _ localOverview: HistoryOverview
  ) async throws -> HistoryOverview {
    try await withCheckedThrowingContinuation {
      continuations.append($0)
    }
  }

  func waitForRequestCount(_ count: Int) async {
    while continuations.count < count {
      await Task.yield()
    }
  }

  func resumeRequest(
    at index: Int,
    returning overview: HistoryOverview
  ) {
    continuations[index]?.resume(returning: overview)
    continuations[index] = nil
  }
}

private enum HistoryRemoteStubResult: Sendable {
  case success(ServerHistorySummary)
  case failure
}

private enum HistoryServerEnrichmentTestError: Error, Sendable {
  case unexpectedRequest
}

private func makeServerSummary(
  weeklyRate: Double = 0,
  dailyRates: [Double?] = Array(repeating: nil, count: 7),
  totalDurationSeconds: Int = 600,
  routineStats: [ServerHistoryRoutineStat] = [],
  monthlyDays: [ServerHistoryMonthlyDay] = []
) -> ServerHistorySummary {
  ServerHistorySummary(
    weekly: ServerHistoryWeeklySummary(
      completionRate: weeklyRate,
      completionRateChangePercentagePoints: 10,
      totalDurationSeconds: totalDurationSeconds,
      dailyCompletions: zip(
        ServerHistoryWeekday.allCases,
        dailyRates
      ).map {
        ServerHistoryWeekdayCompletion(
          weekday: $0.0,
          completionRate: $0.1
        )
      },
      routineStats: routineStats
    ),
    monthlyDays: monthlyDays
  )
}

private func makeServerDailySummary(
  day: Int,
  routineCount: Int
) -> ServerHistoryDailySummary {
  ServerHistoryDailySummary(
    year: 2026,
    month: 7,
    day: day,
    completionRate: 1,
    totalDurationSeconds: routineCount * 300,
    actualWakeMinute: nil,
    currentStreak: 0,
    routines: (0..<routineCount).map { index in
      ServerHistoryDailyRoutine(
        routineID: Int64((day * 10) + index),
        title: "루틴 \(index + 1)",
        type: .check,
        durationSeconds: 300,
        isCompleted: true,
        memberInput: nil
      )
    }
  )
}

private func makeOverview(
  recentDays: [HistoryDaySummary] = [],
  weekRunCount: Int = 0,
  weekCompletionRate: Double = 0,
  monthlyRates: [Double?] = [nil, nil],
  streak: RoutineStreak = .empty
) -> HistoryOverview {
  let calendar = historyTestCalendar
  let weekStart = historyTestDate(day: 13)
  let monthlyDays = monthlyRates.enumerated().map { offset, rate in
    let date = historyTestDate(day: offset + 1)
    return HistoryHeatmapDay(
      id: "2026-07-\(String(format: "%02d", offset + 1))",
      date: date,
      completionRate: rate
    )
  }

  return HistoryOverview(
    calendar: calendar,
    recentDays: recentDays,
    week: HistoryWeekReport(
      weekStartDate: weekStart,
      weekEndDate: calendar.date(
        byAdding: .day,
        value: 7,
        to: weekStart
      )!,
      completedRunCount: weekRunCount,
      totalRunCount: weekRunCount,
      completionRate: weekCompletionRate,
      dailyCompletionRates: (0..<7).map { offset in
        HistoryDailyCompletion(
          date: calendar.date(
            byAdding: .day,
            value: offset,
            to: weekStart
          )!,
          completionRate: weekCompletionRate,
          hasData: weekRunCount > 0
        )
      }
    ),
    wakeMetrics: .unavailable,
    monthlyHeatmap: HistoryMonthlyHeatmap(
      monthStartDate: historyTestDate(day: 1),
      days: monthlyDays
    ),
    streak: streak
  )
}

private func makeDaySummary() -> HistoryDaySummary {
  HistoryDaySummary(
    date: historyTestDate(day: 14),
    completedRunCount: 1,
    totalRunCount: 1,
    completionRate: 1,
    runs: []
  )
}

@MainActor
private func overviewWithAccountStreak(
  _ currentDays: Int,
  basedOn local: HistoryOverview
) -> HistoryOverview {
  HistoryOverview(
    calendar: local.calendar,
    recentDays: local.recentDays,
    week: local.week,
    wakeMetrics: local.wakeMetrics,
    monthlyHeatmap: local.monthlyHeatmap,
    streak: RoutineStreak(
      currentDays: currentDays,
      bestDays: currentDays,
      completedWeekdays: []
    ),
    summarySource: .account
  )
}

private var historyTestCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}

private func historyTestDate(day: Int) -> Date {
  historyTestCalendar.date(
    from: DateComponents(
      year: 2026,
      month: 7,
      day: day
    )
  )!
}
