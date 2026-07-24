//
//  HistoryOverviewFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

@MainActor
final class HistoryOverviewFigmaVisualTests: XCTestCase {
  func testHistoryOverviewStatesRenderDeterministicallyAtReferenceVariants() throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_HISTORY_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-d3-\(phase)"
    )

    for state in HistoryOverviewCaptureState.allCases {
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
    for state: HistoryOverviewCaptureState
  ) -> some View {
    let viewModel = HistoryViewModel(loadHistoryUseCase: HistoryCaptureUseCase())
    viewModel.state = viewState(for: state)

    return MainTabView(
      home: AnyView(EmptyView()),
      routineSetting: RoutineSettingView(dependencies: .mock()),
      history: AnyView(
        HistoryView(
          viewModel: viewModel,
          automaticallyLoads: false
        )
      ),
      selection: .constant(.record),
      historyReloadToken: 0
    )
  }

  private func viewState(
    for state: HistoryOverviewCaptureState
  ) -> HistoryViewState {
    switch state {
    case .loading:
      return .loading
    case .empty:
      return .empty
    case .failure:
      return .failed(message: "기록을 불러오지 못했어요.")
    case .regular, .partialData, .trial, .noStreak, .longKorean:
      return .content(overview(for: state))
    }
  }

  private func overview(
    for state: HistoryOverviewCaptureState
  ) -> HistoryOverview {
    let calendar = captureCalendar
    let monthStart = date(2026, 4, 1, calendar: calendar)
    let routineName: String

    if state == .longKorean {
      routineName = "마음과 몸을 천천히 깨우며 하루를 단단하게 준비하는 긴 아침 루틴"
    } else {
      routineName = "활력 루틴"
    }

    let recentDays = makeRecentDays(
      routineName: routineName,
      calendar: calendar,
      count: state == .partialData || state == .trial ? 1 : 5
    )
    let dailyCompletionRates = makeDailyCompletionRates(
      calendar: calendar,
      sparse: state == .partialData || state == .trial
    )

    return HistoryOverview(
      calendar: calendar,
      recentDays: recentDays,
      week: HistoryWeekReport(
        weekStartDate: date(2026, 4, 6, calendar: calendar),
        weekEndDate: date(2026, 4, 13, calendar: calendar),
        completedRunCount: state == .partialData || state == .trial ? 1 : 5,
        totalRunCount: 7,
        completionRate: state == .partialData || state == .trial ? 0.14 : 0.71,
        dailyCompletionRates: dailyCompletionRates,
        completionRateChangePercentagePoints: nil
      ),
      wakeMetrics: wakeMetrics(for: state),
      monthlyHeatmap: HistoryMonthlyHeatmap(
        monthStartDate: monthStart,
        days: makeHeatmapDays(
          monthStart: monthStart,
          calendar: calendar,
          sparse: state == .partialData || state == .trial
        )
      ),
      streak: streak(for: state)
    )
  }

  private var captureCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ko_KR")
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }

  private func wakeMetrics(
    for state: HistoryOverviewCaptureState
  ) -> HistoryWakeMetrics {
    switch state {
    case .partialData:
      return .insufficient(observationCount: 2)
    case .trial:
      return .insufficient(observationCount: 1)
    case .noStreak:
      return .unavailable
    case .regular, .longKorean:
      return .calculated(
        observationCount: 12,
        averageWakeMinute: 7 * 60 + 8,
        averageDeviationMinutes: 18,
        regularity: .consistent
      )
    case .loading, .empty, .failure:
      return .unavailable
    }
  }

  private func streak(
    for state: HistoryOverviewCaptureState
  ) -> RoutineStreak {
    switch state {
    case .trial:
      return .empty
    case .noStreak:
      return RoutineStreak(
        currentDays: 0,
        bestDays: 18,
        completedWeekdays: []
      )
    case .partialData:
      return RoutineStreak(
        currentDays: 1,
        bestDays: 4,
        completedWeekdays: [.monday]
      )
    case .regular, .longKorean:
      return RoutineStreak(
        currentDays: 4,
        bestDays: 18,
        completedWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
      )
    case .loading, .empty, .failure:
      return .empty
    }
  }

  private func makeRecentDays(
    routineName: String,
    calendar: Calendar,
    count: Int
  ) -> [HistoryDaySummary] {
    (0..<count).map { index in
      let runDate = date(2026, 4, 10 - index, hour: 7, minute: 8, calendar: calendar)
      let step = HistoryStepResult(
        stepID: UUID(
          uuidString: String(
            format: "10000000-0000-0000-0000-%012d",
            index + 1
          )
        )!,
        stepTitle: "물 한 잔 마시기",
        isCompleted: true,
        isSkipped: false,
        transcript: nil
      )
      let run = HistoryRun(
        id: UUID(
          uuidString: String(
            format: "20000000-0000-0000-0000-%012d",
            index + 1
          )
        )!,
        routineName: routineName,
        startedAt: runDate,
        completedAt: runDate.addingTimeInterval(900),
        status: .completed,
        completionRate: 1,
        stepResults: [step]
      )

      return HistoryDaySummary(
        date: runDate,
        completedRunCount: 1,
        totalRunCount: 1,
        completionRate: 1,
        runs: [run]
      )
    }
  }

  private func makeDailyCompletionRates(
    calendar: Calendar,
    sparse: Bool
  ) -> [HistoryDailyCompletion] {
    (0..<7).map { index in
      HistoryDailyCompletion(
        date: date(2026, 4, 6 + index, calendar: calendar),
        completionRate: sparse
          ? (index == 0 ? 1 : 0)
          : (index < 5 ? 1 : 0)
      )
    }
  }

  private func makeHeatmapDays(
    monthStart: Date,
    calendar: Calendar,
    sparse: Bool
  ) -> [HistoryHeatmapDay] {
    let leadingFillers = 3
    return (0..<(leadingFillers + 30)).map { index in
      guard index >= leadingFillers,
            let date = calendar.date(
              byAdding: .day,
              value: index - leadingFillers,
              to: monthStart
            ) else {
        return HistoryHeatmapDay(
          id: "filler-\(index)",
          date: nil,
          completionRate: nil
        )
      }

      let day = index - leadingFillers + 1
      let rate: Double?
      if sparse {
        rate = day == 1 ? 1 : nil
      } else if day > 10 {
        rate = nil
      } else {
        rate = [0.25, 0.5, 0.75, 1][(day - 1) % 4]
      }

      return HistoryHeatmapDay(
        id: "day-\(day)",
        date: date,
        completionRate: rate
      )
    }
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

private enum HistoryOverviewCaptureState: String, CaseIterable {
  case regular
  case loading
  case empty
  case failure
  case partialData = "partial-data"
  case trial
  case noStreak = "no-streak"
  case longKorean = "long-korean"
}

@MainActor
private final class HistoryCaptureUseCase: LoadHistoryUseCaseProtocol {
  func load() throws -> HistoryOverview {
    throw HistoryCaptureError.unexpectedLoad
  }
}

private enum HistoryCaptureError: Error {
  case unexpectedLoad
}
