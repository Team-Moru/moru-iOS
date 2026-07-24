//
//  HistoryDetailFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/25/26.
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

@MainActor
final class HistoryDetailFigmaVisualTests: XCTestCase {
  func testHistoryFigmaCopyContract() {
    XCTAssertEqual(HistoryCopy.weeklyReportTitle, "주간 리포트")
    XCTAssertEqual(HistoryCopy.dailyReportTitle, "데일리 리포트")
    XCTAssertEqual(HistoryCopy.weekdayCompletionRate, "요일별 완수율")
    XCTAssertEqual(HistoryCopy.itemAnalysis, "항목별 분석")
    XCTAssertEqual(HistoryCopy.todayRecords, "오늘의 기록")
    XCTAssertEqual(HistoryCopy.itemResults, "항목별 결과")
    XCTAssertEqual(
      HistoryReportMetricTextOrder.weeklyCompact.resolved(for: .medium),
      .titleThenValue
    )
    XCTAssertEqual(
      HistoryReportMetricTextOrder.weeklyCompact.resolved(
        for: .accessibility3
      ),
      .valueThenTitle
    )
  }

  func testHistoryDetailStatesRenderDeterministicallyAtReferenceVariants() throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_HISTORY_DETAIL_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-p5-\(phase)"
    )

    for state in HistoryDetailCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let filename = "\(state.rawValue)-\(variant.rawValue).png"
        let first = try MoruVisualCaptureFixture.render(
          historyScreen(for: state),
          filename: filename,
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          historyScreen(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        XCTAssertEqual(first.pngData(), second.pngData())
      }
    }
  }

  private func historyScreen(
    for state: HistoryDetailCaptureState
  ) -> some View {
    MainTabView(
      home: AnyView(EmptyView()),
      routineSetting: RoutineSettingView(dependencies: .mock()),
      history: AnyView(
        NavigationStack {
          detailView(for: state)
        }
      ),
      selection: .constant(.record),
      historyReloadToken: 0
    )
  }

  @ViewBuilder
  private func detailView(
    for state: HistoryDetailCaptureState
  ) -> some View {
    switch state {
    case .weeklyRegular:
      HistoryWeeklyReportView(overview: overview(for: state))
    case .weeklyPartialData:
      HistoryWeeklyReportView(overview: overview(for: state))
    case .weeklyLongKorean:
      HistoryWeeklyReportView(overview: overview(for: state))
    case .dailyRegular:
      HistoryDailyDetailView(
        day: day(for: state),
        calendar: captureCalendar
      )
    case .dailyPartialData:
      HistoryDailyDetailView(
        day: day(for: state),
        calendar: captureCalendar
      )
    case .dailyLongKorean:
      HistoryDailyDetailView(
        day: day(for: state),
        calendar: captureCalendar
      )
    case .runRegular:
      HistoryRunDetailView(
        run: run(for: state),
        calendar: captureCalendar
      )
    case .runPartialData:
      HistoryRunDetailView(
        run: run(for: state),
        calendar: captureCalendar
      )
    case .runNoSteps:
      HistoryRunDetailView(
        run: run(for: state),
        calendar: captureCalendar
      )
    case .runLongKorean:
      HistoryRunDetailView(
        run: run(for: state),
        calendar: captureCalendar
      )
    case .missingDestination:
      HistoryDestinationMissingView(
        retryAction: {},
        backAction: {}
      )
    }
  }

  private func overview(
    for state: HistoryDetailCaptureState
  ) -> HistoryOverview {
    let calendar = captureCalendar
    let reportDay = day(for: state)
    let isPartial = state == .weeklyPartialData
    let dailyCompletionRates = (0..<7).map { index in
      HistoryDailyCompletion(
        date: date(2026, 4, 6 + index, calendar: calendar),
        completionRate: isPartial
          ? (index == 0 ? 0.5 : 0)
          : [0.93, 0.3, 0.7, 0.5, 0.64, 0.41, 0][index]
      )
    }

    return HistoryOverview(
      calendar: calendar,
      recentDays: [reportDay],
      week: HistoryWeekReport(
        weekStartDate: date(2026, 4, 6, calendar: calendar),
        weekEndDate: date(2026, 4, 13, calendar: calendar),
        completedRunCount: isPartial ? 1 : 5,
        totalRunCount: 6,
        completionRate: isPartial ? 0.17 : 0.83,
        dailyCompletionRates: dailyCompletionRates,
        completionRateChangePercentagePoints: isPartial ? nil : 8
      ),
      wakeMetrics: .calculated(
        observationCount: 7,
        averageWakeMinute: 7 * 60 + 23,
        averageDeviationMinutes: 18,
        regularity: .consistent
      ),
      monthlyHeatmap: HistoryMonthlyHeatmap(
        monthStartDate: date(2026, 4, 1, calendar: calendar),
        days: []
      ),
      streak: .empty
    )
  }

  private func day(
    for state: HistoryDetailCaptureState
  ) -> HistoryDaySummary {
    let run = run(for: state)
    return HistoryDaySummary(
      date: run.startedAt,
      completedRunCount: run.status == .completed ? 1 : 0,
      totalRunCount: 1,
      completionRate: run.completionRate,
      runs: [run]
    )
  }

  private func run(
    for state: HistoryDetailCaptureState
  ) -> HistoryRun {
    let calendar = captureCalendar
    let isPartial = state == .dailyPartialData || state == .runPartialData
      || state == .weeklyPartialData
    let isLong = state == .dailyLongKorean
      || state == .runLongKorean
      || state == .weeklyLongKorean
    let hasNoSteps = state == .runNoSteps
    let startedAt = date(
      2026,
      4,
      10,
      hour: 7,
      minute: 23,
      calendar: calendar
    )
    let results = hasNoSteps ? [] : stepResults(
      isPartial: isPartial,
      isLong: isLong
    )

    return HistoryRun(
      id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
      routineName: isLong
        ? "마음과 몸을 천천히 깨우며 하루를 단단하게 준비하는 긴 아침 루틴"
        : "활력 루틴",
      startedAt: startedAt,
      completedAt: isPartial
        ? nil
        : startedAt.addingTimeInterval(11 * 60 + 12),
      status: isPartial ? .partial : .completed,
      completionRate: isPartial ? 0.5 : 1,
      stepResults: results
    )
  }

  private func stepResults(
    isPartial: Bool,
    isLong: Bool
  ) -> [HistoryStepResult] {
    [
      HistoryStepResult(
        stepID: UUID(uuidString: "51000000-0000-0000-0000-000000000001")!,
        stepTitle: isLong
          ? "오늘 하루의 방향을 차분하게 정하고 긴 다짐을 소리 내어 확언하기"
          : "오늘의 다짐 확언하기",
        isCompleted: true,
        isSkipped: false,
        transcript: "오늘 하루도 최선을 다하자. 나는 잘 할 수 있어."
      ),
      HistoryStepResult(
        stepID: UUID(uuidString: "51000000-0000-0000-0000-000000000002")!,
        stepTitle: "감정과 생각을 기록하기",
        isCompleted: !isPartial,
        isSkipped: isPartial,
        transcript: isPartial
          ? nil
          : "아침에 일찍 일어나니까 하루가 훨씬 길게 느껴졌다. "
            + "조금 피곤하긴 했지만, 루틴을 끝내고 나서 뿌듯했다."
      ),
      HistoryStepResult(
        stepID: UUID(uuidString: "51000000-0000-0000-0000-000000000003")!,
        stepTitle: "물 한 잔 마시기",
        isCompleted: true,
        isSkipped: false,
        transcript: nil
      ),
    ]
  }

  private var captureCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ko_KR")
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    calendar: Calendar
  ) -> Date {
    calendar.date(
      from: DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
      )
    )!
  }
}

private enum HistoryDetailCaptureState: String, CaseIterable {
  case weeklyRegular = "weekly-regular"
  case weeklyPartialData = "weekly-partial-data"
  case weeklyLongKorean = "weekly-long-korean"
  case dailyRegular = "daily-regular"
  case dailyPartialData = "daily-partial-data"
  case dailyLongKorean = "daily-long-korean"
  case runRegular = "run-regular"
  case runPartialData = "run-partial-data"
  case runNoSteps = "run-no-steps"
  case runLongKorean = "run-long-korean"
  case missingDestination = "missing-destination"
}
