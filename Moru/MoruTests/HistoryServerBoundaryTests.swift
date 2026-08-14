//
//  HistoryServerBoundaryTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

final class HistoryServerBoundaryTests: XCTestCase {
  @MainActor
  func testDeviceWakeMetricsWinUnlessTheyAreUnavailable()
    async throws {
    let localWake = HistoryWakeMetrics.calculated(
      observationCount: 4,
      averageWakeMinute: (7 * 60) + 15,
      standardDeviationMinutes: 9,
      regularityScore: 93,
      regularity: .veryConsistent
    )
    let local = boundaryOverview(wakeMetrics: localWake)
    let service = BoundaryHistoryRemoteService(
      summary: boundaryServerSummary(
        wakePattern: boundaryWakePattern()
      )
    )
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: BoundaryMemberProvider(memberID: 17)
    )

    let result = try await enricher.enrich(local)

    XCTAssertEqual(result, local)
    XCTAssertEqual(result.wakeMetrics, localWake)
    XCTAssertEqual(result.summarySource, .device)

    let unavailableLocal = boundaryOverview(wakeMetrics: .unavailable)
    let fallbackService = BoundaryHistoryRemoteService(
      summary: boundaryServerSummary(
        wakePattern: boundaryWakePattern()
      )
    )
    let fallbackEnricher = AccountHistorySummaryEnricher(
      remoteService: fallbackService,
      signedInMemberProvider: BoundaryMemberProvider(memberID: 17)
    )

    let fallbackResult = try await fallbackEnricher.enrich(
      unavailableLocal
    )

    XCTAssertEqual(
      fallbackResult.wakeMetrics,
      .account(
        HistoryAccountWakeMetrics(
          averageWakeMinute: (6 * 60) + 58,
          wakeTimeDifferenceMinutes: -11,
          regularityScore: 82,
          standardDeviationMinutes: 14,
          regularityLabel: "규칙적이에요"
        )
      )
    )
    guard case .account(let accountMetrics) = fallbackResult.wakeMetrics else {
      return XCTFail("Expected account wake metrics.")
    }
    XCTAssertEqual(accountMetrics.resolvedRegularityScore, 88)
    XCTAssertEqual(accountMetrics.resolvedRegularityLabel, "꽤 규칙적이에요")
    XCTAssertEqual(fallbackResult.summarySource, .account)
  }

  @MainActor
  func testAccountWakeMetricsFallbackToServerValuesWithoutDeviation() {
    let metrics = HistoryAccountWakeMetrics(
      averageWakeMinute: nil,
      wakeTimeDifferenceMinutes: nil,
      regularityScore: 77,
      standardDeviationMinutes: nil,
      regularityLabel: "서버 규칙성"
    )

    XCTAssertEqual(metrics.resolvedRegularityScore, 77)
    XCTAssertEqual(metrics.resolvedRegularityLabel, "서버 규칙성")
  }

  @MainActor
  func testRemoteMonthlyGapIsMarkedAsAccountSource()
    async throws {
    let local = boundaryOverview(
      wakeMetrics: .unavailable,
      monthlyRate: nil
    )
    let service = BoundaryHistoryRemoteService(
      summary: boundaryServerSummary(
        monthlyDays: [
          ServerHistoryMonthlyDay(
            year: 2026,
            month: 7,
            day: 1,
            completionRate: 0
          ),
        ]
      )
    )
    let enricher = AccountHistorySummaryEnricher(
      remoteService: service,
      signedInMemberProvider: BoundaryMemberProvider(memberID: 17)
    )

    let result = try await enricher.enrich(local)
    let day = try XCTUnwrap(result.monthlyHeatmap.days.first)

    XCTAssertEqual(day.completionRate, 0)
    XCTAssertEqual(day.summarySource, .account)
    XCTAssertEqual(result.summarySource, .account)
  }

  @MainActor
  func testDailyLoaderSkipsSignedOutAndDiscardsChangedAccount()
    async throws {
    let service = BoundaryHistoryRemoteService(
      summary: boundaryServerSummary(),
      daily: boundaryDailySummary()
    )
    let loader = LoadAccountHistoryDailyReportUseCase(
      remoteService: service,
      signedInMemberProvider: BoundaryMemberProvider(memberID: nil)
    )

    let result = try await loader.load(
      for: boundaryDate(day: 3),
      calendar: boundaryCalendar()
    )

    XCTAssertNil(result)
    let signedOutRequests = await service.dailyRequests
    XCTAssertTrue(signedOutRequests.isEmpty)

    let deferredService = BoundaryDeferredHistoryRemoteService()
    let memberProvider = BoundaryMemberProvider(memberID: 17)
    let accountLoader = LoadAccountHistoryDailyReportUseCase(
      remoteService: deferredService,
      signedInMemberProvider: memberProvider
    )
    let accountLoad = Task {
      try await accountLoader.load(
        for: boundaryDate(day: 3),
        calendar: boundaryCalendar()
      )
    }

    await deferredService.waitUntilDailyRequested()
    memberProvider.signedInMemberID = 18
    await deferredService.resumeDaily(
      returning: boundaryDailySummary()
    )

    let changedAccountResult = try await accountLoad.value
    XCTAssertNil(changedAccountResult)
  }

  @MainActor
  func testZeroCompletionDailyReportIsContentNotEmptyOrFailure() async {
    let report = boundaryDailySummary(completionRate: 0)
    let loader = BoundarySequencedDailyLoader(
      outcomes: [.success(report)]
    )
    let viewModel = HistoryAccountDailyViewModel(
      date: boundaryDate(day: 3),
      calendar: boundaryCalendar(),
      loader: loader
    )

    await viewModel.load()

    XCTAssertEqual(viewModel.state, .content(report))
  }

  @MainActor
  func testDailyViewModelRetryReplacesFailureWithContent() async {
    let report = boundaryDailySummary()
    let loader = BoundarySequencedDailyLoader(
      outcomes: [
        .failure(.loadFailed),
        .success(report),
      ]
    )
    let viewModel = HistoryAccountDailyViewModel(
      date: boundaryDate(day: 3),
      calendar: boundaryCalendar(),
      loader: loader
    )

    await viewModel.load()
    XCTAssertEqual(
      viewModel.state,
      .failed(message: HistoryCopy.accountDailyLoadFailed)
    )

    await viewModel.retryButtonDidTap()
    XCTAssertEqual(viewModel.state, .content(report))
  }

  @MainActor
  func testOlderDailyLoadCannotOverwriteLatestContent() async {
    let firstReport = boundaryDailySummary(
      completionRate: 0.2,
      currentStreak: 2
    )
    let secondReport = boundaryDailySummary(
      completionRate: 0.9,
      currentStreak: 9
    )
    let loader = BoundaryDeferredDailyLoader()
    let viewModel = HistoryAccountDailyViewModel(
      date: boundaryDate(day: 3),
      calendar: boundaryCalendar(),
      loader: loader
    )
    let firstLoad = Task {
      await viewModel.load()
    }
    await loader.waitForRequestCount(1)
    let secondLoad = Task {
      await viewModel.load()
    }
    await loader.waitForRequestCount(2)

    loader.resumeRequest(at: 1, returning: secondReport)
    await secondLoad.value
    loader.resumeRequest(at: 0, returning: firstReport)
    await firstLoad.value

    XCTAssertEqual(viewModel.state, .content(secondReport))
  }

  @MainActor
  func testCancelledDailyLoadCannotPublishReturnedContent() async {
    let loader = BoundaryDeferredDailyLoader()
    let viewModel = HistoryAccountDailyViewModel(
      date: boundaryDate(day: 3),
      calendar: boundaryCalendar(),
      loader: loader
    )
    let task = Task {
      await viewModel.load()
    }
    await loader.waitForRequestCount(1)

    task.cancel()
    loader.resumeRequest(
      at: 0,
      returning: boundaryDailySummary()
    )
    await task.value

    XCTAssertEqual(viewModel.state, .loading)
  }

  @MainActor
  func testDailyMappingPreservesDuplicateRoutineIDsAndResponseOrder()
    async throws {
    let duplicateIDService = DefaultAccountHistoryRemoteService(
      apiClient: BoundaryHistoryAPIClient(
        daily: boundaryDailyDTO(
          routines: [
            boundaryDailyRoutineDTO(
              routineId: 7,
              durationSecond: 10
            ),
            boundaryDailyRoutineDTO(
              routineId: 7,
              durationSecond: 20
            ),
          ]
        )
      )
    )
    let report = try await duplicateIDService.fetchDaily(
      year: 2026,
      month: 7,
      day: 3,
      memberID: 17
    )

    XCTAssertEqual(report.routines.map(\.routineID), [7, 7])
    XCTAssertEqual(report.routines.map(\.durationSeconds), [10, 20])
  }

  func testMalformedOptionalWakePatternDoesNotDiscardRequiredSummary()
    async throws {
    let invalidResponses = [
      boundaryWakeDTO(avgWakeTime: "7:08"),
      boundaryWakeDTO(avgWakeTime: "24:00"),
      boundaryWakeDTO(
        wakeTimeDiffMin: Int(Int32.max) + 1
      ),
      boundaryWakeDTO(regularityScore: -1),
      boundaryWakeDTO(regularityScore: 101),
      boundaryWakeDTO(stdDevMin: -1),
      boundaryWakeDTO(stdDevMin: Int(Int32.max) + 1),
    ]

    for response in invalidResponses {
      let service = DefaultAccountHistoryRemoteService(
        apiClient: BoundaryHistoryAPIClient(wake: response)
      )

      let summary = try await service.fetchSummary(
        year: 2026,
        month: 7,
        memberID: 17
      )

      XCTAssertNil(summary.wakePattern)
    }
  }

  @MainActor
  func testDailyMappingRejectsMalformedTimesAndRanges() async {
    let invalidDailyResponses = [
      boundaryDailyDTO(actualWakeTime: "7:08"),
      boundaryDailyDTO(actualWakeTime: "24:00"),
      boundaryDailyDTO(completionRate: -1),
      boundaryDailyDTO(completionRate: 101),
      boundaryDailyDTO(totalDurationSecond: -1),
      boundaryDailyDTO(currentStreak: -1),
      boundaryDailyDTO(
        routines: [
          boundaryDailyRoutineDTO(durationSecond: -1),
        ]
      ),
    ]

    for response in invalidDailyResponses {
      let service = DefaultAccountHistoryRemoteService(
        apiClient: BoundaryHistoryAPIClient(daily: response)
      )

      await assertInvalidHistoryResponse {
        _ = try await service.fetchDaily(
          year: 2026,
          month: 7,
          day: 3,
          memberID: 17
        )
      }
    }
  }

  @MainActor
  private func assertInvalidHistoryResponse(
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected AccountHistoryRemoteError.invalidResponse.")
    } catch let error as AccountHistoryRemoteError {
      XCTAssertEqual(error, .invalidResponse)
    } catch {
      XCTFail("Expected AccountHistoryRemoteError, got \(error).")
    }
  }
}

@MainActor
private final class BoundaryMemberProvider: SignedInMemberProviding {
  var signedInMemberID: Int64?

  init(memberID: Int64?) {
    signedInMemberID = memberID
  }
}

private actor BoundaryHistoryRemoteService:
  AccountHistoryRemoteServing {
  struct DailyRequest: Equatable {
    let year: Int
    let month: Int
    let day: Int
    let memberID: Int64
  }

  private let summary: ServerHistorySummary
  private let daily: ServerHistoryDailySummary
  private(set) var dailyRequests: [DailyRequest] = []

  init(
    summary: ServerHistorySummary,
    daily: ServerHistoryDailySummary = boundaryDailySummary()
  ) {
    self.summary = summary
    self.daily = daily
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
    dailyRequests.append(
      DailyRequest(
        year: year,
        month: month,
        day: day,
        memberID: memberID
      )
    )
    return daily
  }
}

private actor BoundaryDeferredHistoryRemoteService:
  AccountHistoryRemoteServing {
  private var dailyContinuation:
    CheckedContinuation<ServerHistoryDailySummary, Error>?
  private var didRequestDaily = false

  func fetchSummary(
    year: Int,
    month: Int,
    memberID: Int64
  ) async throws -> ServerHistorySummary {
    boundaryServerSummary()
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

@MainActor
private final class BoundarySequencedDailyLoader:
  AccountHistoryDailyReportLoading {
  private var outcomes:
    [Result<ServerHistoryDailySummary?, BoundaryDailyLoaderError>]

  init(
    outcomes: [
      Result<ServerHistoryDailySummary?, BoundaryDailyLoaderError>
    ]
  ) {
    self.outcomes = outcomes
  }

  func load(
    for date: Date,
    calendar: Calendar
  ) async throws -> ServerHistoryDailySummary? {
    guard !outcomes.isEmpty else {
      throw BoundaryDailyLoaderError.loadFailed
    }
    return try outcomes.removeFirst().get()
  }
}

@MainActor
private final class BoundaryDeferredDailyLoader:
  AccountHistoryDailyReportLoading {
  private var continuations: [
    CheckedContinuation<ServerHistoryDailySummary?, Error>?
  ] = []

  func load(
    for date: Date,
    calendar: Calendar
  ) async throws -> ServerHistoryDailySummary? {
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
    returning report: ServerHistoryDailySummary?
  ) {
    continuations[index]?.resume(returning: report)
    continuations[index] = nil
  }
}

private enum BoundaryDailyLoaderError: Error {
  case loadFailed
}

nonisolated private final class BoundaryHistoryAPIClient:
  AccountBoundAPIClient,
  @unchecked Sendable {
  private let wake: HistoryWakePatternResponseDTO
  private let daily: HistoryDailyResponseDTO

  init(
    wake: HistoryWakePatternResponseDTO = boundaryWakeDTO(),
    daily: HistoryDailyResponseDTO = boundaryDailyDTO()
  ) {
    self.wake = wake
    self.daily = daily
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type
  ) async throws -> Payload {
    throw APIError.invalidRequest("Expected an account-bound request.")
  }

  func request<Target: MoruTargetType, Payload: Decodable & Sendable>(
    _ target: Target,
    as payloadType: Payload.Type,
    authorizedForMemberID memberID: Int64
  ) async throws -> Payload {
    guard let target = target as? HistoryTarget else {
      throw APIError.invalidRequest("Unexpected target.")
    }

    let response: any Sendable
    switch target {
    case .weekly:
      response = boundaryWeeklyDTO()
    case .monthly:
      response = [HistoryMonthlyDayDTO]()
    case .daily:
      response = daily
    case .wakePattern:
      response = wake
    }

    guard let payload = response as? Payload else {
      throw APIError.decoding("Unexpected payload type.")
    }
    return payload
  }

  func requestVoid<Target: MoruTargetType>(
    _ target: Target
  ) async throws {
    throw APIError.invalidRequest("Unexpected void request.")
  }

  func requestData<Target: MoruTargetType>(
    _ target: Target
  ) async throws -> Data {
    throw APIError.invalidRequest("Unexpected data request.")
  }
}

private func boundaryServerSummary(
  monthlyDays: [ServerHistoryMonthlyDay] = [],
  wakePattern: ServerHistoryWakePattern? = nil
) -> ServerHistorySummary {
  ServerHistorySummary(
    weekly: ServerHistoryWeeklySummary(
      completionRate: 0,
      completionRateChangePercentagePoints: 0,
      totalDurationSeconds: 0,
      dailyCompletions: ServerHistoryWeekday.allCases.map {
        ServerHistoryWeekdayCompletion(
          weekday: $0,
          completionRate: nil
        )
      },
      routineStats: []
    ),
    monthlyDays: monthlyDays,
    wakePattern: wakePattern
  )
}

private func boundaryWakePattern() -> ServerHistoryWakePattern {
  ServerHistoryWakePattern(
    averageWakeMinute: (6 * 60) + 58,
    wakeTimeDifferenceMinutes: -11,
    regularityScore: 82,
    standardDeviationMinutes: 14,
    regularityLabel: "규칙적이에요"
  )
}

private func boundaryOverview(
  wakeMetrics: HistoryWakeMetrics,
  monthlyRate: Double? = nil
) -> HistoryOverview {
  let calendar = boundaryCalendar()
  let monthStart = boundaryDate(day: 1)
  let weekStart = boundaryDate(day: 6)
  let weekEnd = calendar.date(
    byAdding: .day,
    value: 7,
    to: weekStart
  )!

  return HistoryOverview(
    calendar: calendar,
    recentDays: [],
    week: HistoryWeekReport(
      weekStartDate: weekStart,
      weekEndDate: weekEnd,
      completedRunCount: 0,
      totalRunCount: 1,
      completionRate: 0,
      dailyCompletionRates: (0..<7).map { offset in
        HistoryDailyCompletion(
          date: calendar.date(
            byAdding: .day,
            value: offset,
            to: weekStart
          )!,
          completionRate: 0,
          hasData: false
        )
      }
    ),
    wakeMetrics: wakeMetrics,
    monthlyHeatmap: HistoryMonthlyHeatmap(
      monthStartDate: monthStart,
      days: [
        HistoryHeatmapDay(
          id: "2026-07-01",
          date: monthStart,
          completionRate: monthlyRate
        ),
      ]
    )
  )
}

private func boundaryDailySummary(
  completionRate: Double = 0.6,
  currentStreak: Int = 7
) -> ServerHistoryDailySummary {
  ServerHistoryDailySummary(
    year: 2026,
    month: 7,
    day: 3,
    completionRate: completionRate,
    totalDurationSeconds: 120,
    actualWakeMinute: (7 * 60) + 8,
    currentStreak: currentStreak,
    routines: [
      ServerHistoryDailyRoutine(
        routineID: 1,
        title: "물 마시기",
        type: .check,
        durationSeconds: 20,
        isCompleted: true,
        memberInput: nil
      ),
    ]
  )
}

private func boundaryWeeklyDTO() -> HistoryWeeklyResponseDTO {
  HistoryWeeklyResponseDTO(
    completionRate: 0,
    completionRateDiff: 0,
    totalDurationSecond: 0,
    weeklyCompletionRate: ServerHistoryWeekday.allCases.map {
      HistoryWeekdayCompletionDTO(
        day: $0.rawValue,
        completionRate: nil
      )
    },
    routineStats: []
  )
}

private func boundaryWakeDTO(
  avgWakeTime: String? = "07:08",
  wakeTimeDiffMin: Int? = -12,
  regularityScore: Int? = 73,
  stdDevMin: Int? = 18,
  regularityLabel: String = "꽤 규칙적이에요"
) -> HistoryWakePatternResponseDTO {
  HistoryWakePatternResponseDTO(
    avgWakeTime: avgWakeTime,
    wakeTimeDiffMin: wakeTimeDiffMin,
    regularityScore: regularityScore,
    stdDevMin: stdDevMin,
    regularityLabel: regularityLabel
  )
}

private func boundaryDailyDTO(
  executedDate: String = "2026-07-03",
  completionRate: Int = 60,
  totalDurationSecond: Int = 120,
  actualWakeTime: String? = "07:08",
  currentStreak: Int64 = 7,
  routines: [HistoryDailyRoutineDTO] = [
    boundaryDailyRoutineDTO(),
  ]
) -> HistoryDailyResponseDTO {
  HistoryDailyResponseDTO(
    executedDate: executedDate,
    completionRate: completionRate,
    totalDurationSecond: totalDurationSecond,
    actualWakeTime: actualWakeTime,
    currentStreak: currentStreak,
    routines: routines
  )
}

private func boundaryDailyRoutineDTO(
  routineId: Int64 = 1,
  durationSecond: Int = 20
) -> HistoryDailyRoutineDTO {
  HistoryDailyRoutineDTO(
    routineId: routineId,
    title: "물 마시기",
    type: "CHECK",
    durationSecond: durationSecond,
    isCompleted: true,
    memberInput: nil
  )
}

private func boundaryCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}

private func boundaryDate(day: Int) -> Date {
  boundaryCalendar().date(
    from: DateComponents(
      year: 2026,
      month: 7,
      day: day,
      hour: 12
    )
  )!
}
