//
//  HistoryRunReportingTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Moru

final class HistoryRunReportingTests: XCTestCase {
  @MainActor
  func testHistoryClassifiesCompletedPartialAndEndedEarlyRuns() throws {
    let calendar = makeCalendar()
    let startedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let completedStep = makeSnapshot(title: "완료")
    let partialStep = makeSnapshot(title: "미완료", order: 1)
    let completedRun = makeRun(
      routineName: "완료 루틴",
      startedAt: startedAt,
      plannedSteps: [completedStep],
      results: [makeCompletedResult(for: completedStep)]
    )
    let partialRun = makeRun(
      routineName: "부분 루틴",
      startedAt: startedAt.addingTimeInterval(1),
      plannedSteps: [completedStep, partialStep],
      results: [makeCompletedResult(for: completedStep)]
    )
    let endedEarlyRun = makeRun(
      routineName: "중단 루틴",
      startedAt: startedAt.addingTimeInterval(2),
      plannedSteps: [completedStep],
      results: [makeCompletedResult(for: completedStep)],
      endedEarly: true
    )
    let useCase = makeUseCase(
      runs: [partialRun, endedEarlyRun, completedRun],
      calendar: calendar,
      now: startedAt
    )

    let overview = try useCase.load()
    let statuses = Dictionary(
      uniqueKeysWithValues: overview.recentDays[0].runs.map { ($0.id, $0.status) }
    )

    XCTAssertEqual(statuses[completedRun.id], .completed)
    XCTAssertEqual(statuses[partialRun.id], .partial)
    XCTAssertEqual(statuses[endedEarlyRun.id], .endedEarly)
    XCTAssertEqual(overview.recentDays[0].completedRunCount, 1)
    XCTAssertEqual(overview.recentDays[0].completionRate, 5.0 / 6.0)
    XCTAssertEqual(overview.week.completionRate, 5.0 / 6.0)
  }
  @MainActor
  func testHistoryDisplayLabelsReflectRunAndStepResults() {
    XCTAssertEqual(HistoryRunStatus.completed.displayText, "완료")
    XCTAssertEqual(HistoryRunStatus.partial.displayText, "일부 완료")
    XCTAssertEqual(HistoryRunStatus.endedEarly.displayText, "중단됨")

    let completed = HistoryStepResult(
      stepID: UUID(),
      stepTitle: "완료 스텝",
      isCompleted: true,
      isSkipped: false,
      transcript: nil
    )
    let skipped = HistoryStepResult(
      stepID: UUID(),
      stepTitle: "건너뛴 스텝",
      isCompleted: false,
      isSkipped: true,
      transcript: nil
    )
    let incomplete = HistoryStepResult(
      stepID: UUID(),
      stepTitle: "미완료 스텝",
      isCompleted: false,
      isSkipped: false,
      transcript: nil
    )

    XCTAssertEqual(completed.displayText, "완료")
    XCTAssertEqual(skipped.displayText, "건너뜀")
    XCTAssertEqual(incomplete.displayText, "미완료")
  }

  @MainActor
  func testHistoryUsesRunSnapshotsAfterRoutineDeletion() throws {
    let calendar = makeCalendar()
    let startedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let snapshot = makeSnapshot(title: "삭제된 루틴의 스텝")
    let run = makeRun(
      routineName: "삭제된 루틴",
      startedAt: startedAt,
      plannedSteps: [snapshot],
      results: [makeCompletedResult(for: snapshot, transcript: "완료했어요")]
    )
    let useCase = makeUseCase(runs: [run], calendar: calendar, now: startedAt)

    let historyRun = try useCase.load().recentDays[0].runs[0]

    XCTAssertEqual(historyRun.routineName, "삭제된 루틴")
    XCTAssertEqual(historyRun.stepResults.map(\.stepTitle), ["삭제된 루틴의 스텝"])
    XCTAssertEqual(historyRun.stepResults.first?.transcript, "완료했어요")
  }

  @MainActor
  func testEmptyHistoryProducesAnEmptyOverviewAndWeek() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let useCase = makeUseCase(runs: [], calendar: calendar, now: now)

    let overview = try useCase.load()

    XCTAssertTrue(overview.recentDays.isEmpty)
    XCTAssertEqual(
      overview.week.weekStartDate,
      makeDate(2026, 7, 13, 0, 0, calendar: calendar)
    )
    XCTAssertEqual(
      overview.week.weekEndDate,
      makeDate(2026, 7, 20, 0, 0, calendar: calendar)
    )
    XCTAssertEqual(overview.week.totalRunCount, 0)
    XCTAssertEqual(overview.week.completedRunCount, 0)
    XCTAssertEqual(overview.week.completionRate, 0)
    XCTAssertEqual(overview.week.dailyCompletionRates.count, 7)
    XCTAssertTrue(overview.week.dailyCompletionRates.allSatisfy { $0.completionRate == 0 })
    XCTAssertEqual(overview.wakeMetrics, .unavailable)
    XCTAssertEqual(
      overview.monthlyHeatmap.monthStartDate,
      makeDate(2026, 7, 1, 0, 0, calendar: calendar)
    )
    XCTAssertEqual(overview.monthlyHeatmap.days.filter { $0.date != nil }.count, 31)
    XCTAssertTrue(
      overview.monthlyHeatmap.days.allSatisfy { $0.completionRate == nil }
    )
    XCTAssertEqual(Array(overview.monthlyHeatmap.days.prefix(2)).map(\.date), [nil, nil])
    XCTAssertEqual(
      overview.monthlyHeatmap.days[2].date,
      makeDate(2026, 7, 1, 0, 0, calendar: calendar)
    )
  }

  @MainActor
  func testWakeMetricsRequireThreeDifferentDaysOfCompletedRuns() throws {
    let calendar = makeCalendar()
    let firstRun = makeRun(
      startedAt: makeDate(2026, 7, 13, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let laterSameDayRun = makeRun(
      startedAt: makeDate(2026, 7, 13, 9, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let secondDayRun = makeRun(
      startedAt: makeDate(2026, 7, 14, 7, 10, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let expiredRun = makeRun(
      startedAt: makeDate(2026, 6, 16, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let futureRun = makeRun(
      startedAt: makeDate(2026, 7, 15, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let overview = try makeUseCase(
      runs: [
        expiredRun,
        laterSameDayRun,
        futureRun,
        secondDayRun,
        firstRun,
      ],
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    ).load()

    XCTAssertEqual(overview.wakeMetrics, .insufficient(observationCount: 2))
  }

  @MainActor
  func testWakeMetricsUseCircularMeanAcrossMidnight() throws {
    let calendar = makeCalendar()
    let runs = [
      makeRun(
        startedAt: makeDate(2026, 7, 12, 23, 50, calendar: calendar),
        plannedSteps: [makeSnapshot()]
      ),
      makeRun(
        startedAt: makeDate(2026, 7, 13, 0, 0, calendar: calendar),
        plannedSteps: [makeSnapshot()]
      ),
      makeRun(
        startedAt: makeDate(2026, 7, 14, 0, 10, calendar: calendar),
        plannedSteps: [makeSnapshot()]
      ),
    ]
    let overview = try makeUseCase(
      runs: runs,
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    ).load()

    XCTAssertEqual(
      overview.wakeMetrics,
      .calculated(
        observationCount: 3,
        averageWakeMinute: 0,
        averageDeviationMinutes: 7,
        regularity: .veryConsistent
      )
    )
  }

  @MainActor
  func testStartTimeRegularityOwnsBoundaryScoresAndCopy() {
    let expectations: [
      (deviation: Int, regularity: HistoryStartTimeRegularity, score: Int, copy: String)
    ] = [
      (10, .veryConsistent, 96, "매우 규칙적이에요"),
      (11, .consistent, 87, "꽤 규칙적이에요"),
      (20, .consistent, 87, "꽤 규칙적이에요"),
      (21, .variable, 68, "조금 불규칙해요"),
      (40, .variable, 68, "조금 불규칙해요"),
      (41, .highlyVariable, 42, "많이 불규칙해요"),
    ]

    for expectation in expectations {
      let regularity = HistoryStartTimeRegularity(
        averageDeviationMinutes: expectation.deviation
      )

      XCTAssertEqual(regularity, expectation.regularity)
      XCTAssertEqual(regularity.score, expectation.score)
      XCTAssertEqual(regularity.shortText, expectation.copy)
    }
  }

  @MainActor
  func testWakeMetricsClassifyAverageStartTimeDeviation() throws {
    let calendar = makeCalendar()
    let runs = [7, 8, 9].map { hour in
      makeRun(
        startedAt: makeDate(2026, 7, hour + 5, hour, 0, calendar: calendar),
        plannedSteps: [makeSnapshot()]
      )
    }
    let overview = try makeUseCase(
      runs: runs,
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    ).load()

    XCTAssertEqual(
      overview.wakeMetrics,
      .calculated(
        observationCount: 3,
        averageWakeMinute: 8 * 60,
        averageDeviationMinutes: 40,
        regularity: .variable
      )
    )
  }

  @MainActor
  func testMonthlyHeatmapUsesDocumentedCompletionBuckets() throws {
    let calendar = makeCalendar()
    let steps = (0..<4).map { makeSnapshot(order: $0) }
    let completedResults = steps.map { makeCompletedResult(for: $0) }
    let runs = [
      makeRun(
        startedAt: makeDate(2026, 7, 1, 7, 0, calendar: calendar),
        plannedSteps: steps
      ),
      makeRun(
        startedAt: makeDate(2026, 7, 2, 7, 0, calendar: calendar),
        plannedSteps: steps,
        results: Array(completedResults.prefix(1))
      ),
      makeRun(
        startedAt: makeDate(2026, 7, 3, 7, 0, calendar: calendar),
        plannedSteps: steps,
        results: Array(completedResults.prefix(3))
      ),
      makeRun(
        startedAt: makeDate(2026, 7, 4, 7, 0, calendar: calendar),
        plannedSteps: steps,
        results: completedResults
      ),
    ]
    let heatmap = try makeUseCase(
      runs: runs,
      calendar: calendar,
      now: makeDate(2026, 7, 31, 12, 0, calendar: calendar)
    ).load().monthlyHeatmap
    let datedDays = heatmap.days.compactMap { day -> (Date, HistoryHeatmapBucket)? in
      guard let date = day.date else {
        return nil
      }

      return (date, day.bucket)
    }
    let buckets = Dictionary(uniqueKeysWithValues: datedDays)

    XCTAssertEqual(
      buckets[makeDate(2026, 7, 1, 0, 0, calendar: calendar)],
      .zero
    )
    XCTAssertEqual(
      buckets[makeDate(2026, 7, 2, 0, 0, calendar: calendar)],
      .low
    )
    XCTAssertEqual(
      buckets[makeDate(2026, 7, 3, 0, 0, calendar: calendar)],
      .high
    )
    XCTAssertEqual(
      buckets[makeDate(2026, 7, 4, 0, 0, calendar: calendar)],
      .complete
    )
    XCTAssertEqual(
      buckets[makeDate(2026, 7, 5, 0, 0, calendar: calendar)],
      .noData
    )
  }

  @MainActor
  func testRunDetailDestinationResolvesExactlyOneMatchingRun() throws {
    let calendar = makeCalendar()
    let runID = UUID()
    let run = makeRun(
      id: runID,
      startedAt: makeDate(2026, 7, 14, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let overview = try makeUseCase(
      runs: [run],
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    ).load()
    let resolution = HistoryRunDetailDestinationResolver.resolve(
      destination: .runDetail(runID),
      in: overview
    )

    guard case .selected(let presentation) = resolution else {
      XCTFail("A unique stored run should resolve to its detail.")
      return
    }

    XCTAssertEqual(presentation.run.id, runID)
    XCTAssertEqual(presentation.calendar, calendar)
  }

  @MainActor
  func testRunDetailDestinationRejectsMissingAndDuplicateRunIDs() throws {
    let calendar = makeCalendar()
    let duplicateID = UUID()
    let firstRun = makeRun(
      id: duplicateID,
      startedAt: makeDate(2026, 7, 13, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let secondRun = makeRun(
      id: duplicateID,
      startedAt: makeDate(2026, 7, 14, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let overview = try makeUseCase(
      runs: [firstRun, secondRun],
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    ).load()

    XCTAssertEqual(
      HistoryRunDetailDestinationResolver.resolve(
        destination: .runDetail(UUID()),
        in: overview
      ),
      .missing
    )
    XCTAssertEqual(
      HistoryRunDetailDestinationResolver.resolve(
        destination: .runDetail(duplicateID),
        in: overview
      ),
      .missing
    )
  }

  @MainActor
  func testHistoryMetricsRenderAtReferenceAccessibilitySizes() throws {
    let calendar = makeCalendar()
    let steps = (0..<4).map { makeSnapshot(order: $0) }
    let completedResults = steps.map { makeCompletedResult(for: $0) }
    let runs = (0..<6).map { offset in
      makeRun(
        startedAt: makeDate(
          2026,
          7,
          9 + offset,
          7,
          offset * 4,
          calendar: calendar
        ),
        plannedSteps: steps,
        results: Array(completedResults.prefix((offset % 4) + 1))
      )
    }
    let overview = try makeUseCase(
      runs: runs,
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    ).load()

    try renderHistoryMetrics(
      overview: overview,
      dynamicTypeSize: .medium,
      colorScheme: .light,
      filename: "moru-pr32-history-light-medium.png"
    )
    try renderHistoryMetrics(
      overview: overview,
      dynamicTypeSize: .accessibility3,
      colorScheme: .dark,
      filename: "moru-pr32-history-dark-ax3.png"
    )
  }

  @MainActor
  func testHistoryGroupsRunsAtCalendarDayBoundariesInInjectedTimeZone() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
    let calendar = makeCalendar(timeZone: timeZone)
    let lateRun = makeRun(
      startedAt: makeDate(2026, 7, 14, 23, 59, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let midnightRun = makeRun(
      startedAt: makeDate(2026, 7, 15, 0, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let useCase = makeUseCase(
      runs: [lateRun, midnightRun],
      calendar: calendar,
      now: makeDate(2026, 7, 15, 12, 0, calendar: calendar)
    )

    let overview = try useCase.load()

    XCTAssertEqual(
      overview.recentDays.map(\.date),
      [
        makeDate(2026, 7, 15, 0, 0, calendar: calendar),
        makeDate(2026, 7, 14, 0, 0, calendar: calendar),
      ]
    )
    XCTAssertEqual(overview.recentDays[0].runs.map(\.id), [midnightRun.id])
    XCTAssertEqual(overview.recentDays[1].runs.map(\.id), [lateRun.id])
  }

  @MainActor
  func testWeekStartsOnMondayAndExcludesPreviousSunday() throws {
    let calendar = makeCalendar()
    let sundayRun = makeRun(
      startedAt: makeDate(2026, 7, 12, 10, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let mondayStep = makeSnapshot()
    let mondayRun = makeRun(
      startedAt: makeDate(2026, 7, 13, 10, 0, calendar: calendar),
      plannedSteps: [mondayStep],
      results: [makeCompletedResult(for: mondayStep)]
    )
    let useCase = makeUseCase(
      runs: [sundayRun, mondayRun],
      calendar: calendar,
      now: makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    )

    let week = try useCase.load().week

    XCTAssertEqual(week.weekStartDate, makeDate(2026, 7, 13, 0, 0, calendar: calendar))
    XCTAssertEqual(week.weekEndDate, makeDate(2026, 7, 20, 0, 0, calendar: calendar))
    XCTAssertEqual(week.totalRunCount, 1)
    XCTAssertEqual(week.completedRunCount, 1)
    XCTAssertEqual(week.dailyCompletionRates.map(\.date), [
      makeDate(2026, 7, 13, 0, 0, calendar: calendar),
      makeDate(2026, 7, 14, 0, 0, calendar: calendar),
      makeDate(2026, 7, 15, 0, 0, calendar: calendar),
      makeDate(2026, 7, 16, 0, 0, calendar: calendar),
      makeDate(2026, 7, 17, 0, 0, calendar: calendar),
      makeDate(2026, 7, 18, 0, 0, calendar: calendar),
      makeDate(2026, 7, 19, 0, 0, calendar: calendar),
    ])
    XCTAssertEqual(week.dailyCompletionRates[0].completionRate, 1)
    XCTAssertTrue(week.dailyCompletionRates.dropFirst().allSatisfy { $0.completionRate == 0 })
  }
  @MainActor
  func testWeekExcludesNextMondayAtMidnightAcrossDST() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let calendar = makeCalendar(timeZone: timeZone)
    let sundayStep = makeSnapshot()
    let nextMondayStep = makeSnapshot()
    let sundayRun = makeRun(
      startedAt: makeDate(2026, 3, 8, 23, 59, calendar: calendar),
      plannedSteps: [sundayStep],
      results: [makeCompletedResult(for: sundayStep)]
    )
    let nextMondayRun = makeRun(
      startedAt: makeDate(2026, 3, 9, 0, 0, calendar: calendar),
      plannedSteps: [nextMondayStep],
      results: [makeCompletedResult(for: nextMondayStep)]
    )
    let overview = try makeUseCase(
      runs: [sundayRun, nextMondayRun],
      calendar: calendar,
      now: makeDate(2026, 3, 4, 12, 0, calendar: calendar)
    ).load()

    XCTAssertEqual(overview.calendar, calendar)
    XCTAssertEqual(overview.week.weekStartDate, makeDate(2026, 3, 2, 0, 0, calendar: calendar))
    XCTAssertEqual(overview.week.weekEndDate, makeDate(2026, 3, 9, 0, 0, calendar: calendar))
    XCTAssertEqual(overview.week.totalRunCount, 1)
    XCTAssertEqual(overview.week.completedRunCount, 1)
    XCTAssertEqual(overview.week.dailyCompletionRates[6].completionRate, 1)
  }

  @MainActor
  func testSkippedStepUsesRoutineRunResultsAndDoesNotCountAsCompletion() throws {
    let calendar = makeCalendar()
    let startedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let snapshot = makeSnapshot(title: "건너뛴 스텝")
    let skippedResult = RoutineStepResult(
      stepID: snapshot.stepID,
      stepTitle: snapshot.stepTitle,
      stepType: snapshot.stepType,
      completedAt: startedAt.addingTimeInterval(60),
      skipped: true
    )
    let run = makeRun(
      startedAt: startedAt,
      plannedSteps: [snapshot],
      results: [skippedResult]
    )
    let useCase = makeUseCase(runs: [run], calendar: calendar, now: startedAt)

    let historyRun = try useCase.load().recentDays[0].runs[0]

    XCTAssertEqual(historyRun.completionRate, 0)
    XCTAssertEqual(historyRun.status, .partial)
    XCTAssertFalse(historyRun.stepResults[0].isCompleted)
    XCTAssertTrue(historyRun.stepResults[0].isSkipped)
  }
  @MainActor
  func testHistoryExcludesNonterminalRunsAndRetainsFinalizedNaturalAndEndedEarlyRuns() throws {
    let calendar = makeCalendar()
    let naturalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
    let endedEarlyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
    let nonterminalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
    let monday = makeDate(2026, 7, 13, 0, 0, calendar: calendar)
    let naturalStep = makeSnapshot(title: "자연 완료")
    let endedEarlyCompletedStep = makeSnapshot(title: "중단 전 완료", order: 0)
    let endedEarlyIncompleteStep = makeSnapshot(title: "중단 미완료", order: 1)
    let nonterminalStep = makeSnapshot(title: "진행 중")
    let naturalRun = makeRun(
      id: naturalID,
      startedAt: monday.addingTimeInterval(9 * 60 * 60),
      plannedSteps: [naturalStep],
      results: [makeCompletedResult(for: naturalStep)]
    )
    let endedEarlyRun = makeRun(
      id: endedEarlyID,
      startedAt: monday.addingTimeInterval(10 * 60 * 60),
      plannedSteps: [endedEarlyCompletedStep, endedEarlyIncompleteStep],
      results: [makeCompletedResult(for: endedEarlyCompletedStep)],
      endedEarly: true
    )
    let nonterminalRun = makeRun(
      id: nonterminalID,
      startedAt: monday.addingTimeInterval(24 * 60 * 60),
      plannedSteps: [nonterminalStep],
      results: [makeCompletedResult(for: nonterminalStep)],
      isFinalized: false
    )
    let overview = try makeUseCase(
      runs: [nonterminalRun, naturalRun, endedEarlyRun],
      calendar: calendar,
      now: monday
    ).load()

    let day = try XCTUnwrap(overview.recentDays.first)

    XCTAssertEqual(overview.recentDays.map(\.date), [monday])
    XCTAssertEqual(day.runs.map(\.id), [endedEarlyID, naturalID])
    XCTAssertEqual(day.runs.map(\.status), [.endedEarly, .completed])
    XCTAssertFalse(day.runs.contains { $0.id == nonterminalID })
    XCTAssertEqual(day.totalRunCount, day.runs.count)
    XCTAssertEqual(day.totalRunCount, 2)
    XCTAssertEqual(day.completedRunCount, 1)
    XCTAssertEqual(day.completionRate, 0.75)
    XCTAssertEqual(overview.week.totalRunCount, 2)
    XCTAssertEqual(overview.week.completedRunCount, 1)
    XCTAssertEqual(overview.week.completionRate, 0.75)
    XCTAssertEqual(overview.week.dailyCompletionRates[0].completionRate, 0.75)
    XCTAssertTrue(
      overview.week.dailyCompletionRates
        .dropFirst()
        .allSatisfy { $0.completionRate == 0 }
    )
  }

  @MainActor
  func testHistoryCompletionRateIsDeterministicAcrossInputPermutations() throws {
    let calendar = makeCalendar()
    let thirdSteps = [
      makeSnapshot(title: "3분의 1 - 1", order: 0),
      makeSnapshot(title: "3분의 1 - 2", order: 1),
      makeSnapshot(title: "3분의 1 - 3", order: 2),
    ]
    let halfSteps = [
      makeSnapshot(title: "2분의 1 - 1", order: 0),
      makeSnapshot(title: "2분의 1 - 2", order: 1),
    ]
    let twoThirdsSteps = [
      makeSnapshot(title: "3분의 2 - 1", order: 0),
      makeSnapshot(title: "3분의 2 - 2", order: 1),
      makeSnapshot(title: "3분의 2 - 3", order: 2),
    ]
    let thirdRun = makeRun(
      startedAt: makeDate(2026, 7, 14, 9, 0, calendar: calendar),
      plannedSteps: thirdSteps,
      results: [makeCompletedResult(for: thirdSteps[0])]
    )
    let halfRun = makeRun(
      startedAt: makeDate(2026, 7, 14, 8, 0, calendar: calendar),
      plannedSteps: halfSteps,
      results: [makeCompletedResult(for: halfSteps[0])]
    )
    let twoThirdsRun = makeRun(
      startedAt: makeDate(2026, 7, 14, 7, 0, calendar: calendar),
      plannedSteps: twoThirdsSteps,
      results: [
        makeCompletedResult(for: twoThirdsSteps[0]),
        makeCompletedResult(for: twoThirdsSteps[1]),
      ]
    )
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)

    let firstOverview = try makeUseCase(
      runs: [halfRun, twoThirdsRun, thirdRun],
      calendar: calendar,
      now: now
    ).load()
    let permutedOverview = try makeUseCase(
      runs: [thirdRun, halfRun, twoThirdsRun],
      calendar: calendar,
      now: now
    ).load()

    XCTAssertEqual(firstOverview, permutedOverview)
    XCTAssertEqual(firstOverview.week.completionRate, 0.5)
  }

  @MainActor
  func testHistoryOrderingIsDeterministicForDaysAndRuns() throws {
    let calendar = makeCalendar()
    let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let laterRun = makeRun(
      startedAt: makeDate(2026, 7, 15, 9, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let firstRun = makeRun(
      id: firstID,
      startedAt: makeDate(2026, 7, 14, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let secondRun = makeRun(
      id: secondID,
      startedAt: makeDate(2026, 7, 14, 7, 0, calendar: calendar),
      plannedSteps: [makeSnapshot()]
    )
    let useCase = makeUseCase(
      runs: [secondRun, laterRun, firstRun],
      calendar: calendar,
      now: makeDate(2026, 7, 15, 12, 0, calendar: calendar)
    )

    let overview = try useCase.load()

    XCTAssertEqual(overview.recentDays.map(\.date), [
      makeDate(2026, 7, 15, 0, 0, calendar: calendar),
      makeDate(2026, 7, 14, 0, 0, calendar: calendar),
    ])
    XCTAssertEqual(overview.recentDays[1].runs.map(\.id), [firstID, secondID])
  }

  @MainActor
  func testHistoryRethrowsRepositoryErrors() {
    let calendar = makeCalendar()
    let repository = HistoryRunRepositoryStub(error: HistoryRepositoryTestError.unavailable)
    let useCase = LoadHistoryUseCase(
      routineRunRepository: repository,
      calendar: calendar,
      now: { self.makeDate(2026, 7, 14, 12, 0, calendar: calendar) }
    )

    XCTAssertThrowsError(try useCase.load()) { error in
      XCTAssertEqual(error as? HistoryRepositoryTestError, .unavailable)
    }
  }

  @MainActor
  func testLocalDependencyUsesStoredRunsAndStaysEmptyAfterReset() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let step = makeSnapshot()
    let run = makeRun(
      startedAt: makeDate(2026, 7, 14, 7, 0, calendar: calendar),
      plannedSteps: [step],
      results: [makeCompletedResult(for: step)]
    )
    let useCase = LoadHistoryUseCase(
      routineRunRepository: dependencies.routineRunRepository,
      calendar: calendar,
      now: { now }
    )

    XCTAssertTrue(
      dependencies.routineRunRepository is SwiftDataRoutineRunRepository
    )

    try dependencies.routineRunRepository.saveRun(run)
    XCTAssertEqual(try useCase.load().recentDays.flatMap(\.runs).map(\.id), [run.id])

    let resetRepository = try XCTUnwrap(dependencies.localDataResetRepository)
    try resetRepository.resetToFreshInstallState()

    let resetOverview = try useCase.load()
    XCTAssertTrue(resetOverview.recentDays.isEmpty)
    XCTAssertEqual(resetOverview.week.totalRunCount, 0)
    XCTAssertEqual(resetOverview.wakeMetrics, .unavailable)
    XCTAssertTrue(
      resetOverview.monthlyHeatmap.days.allSatisfy {
        $0.completionRate == nil
      }
    )
  }

  @MainActor
  private func makeUseCase(
    runs: [RoutineRun],
    calendar: Calendar,
    now: Date
  ) -> LoadHistoryUseCase {
    LoadHistoryUseCase(
      routineRunRepository: HistoryRunRepositoryStub(runs: runs),
      calendar: calendar,
      now: { now }
    )
  }

  private func makeCalendar(timeZone: TimeZone = .gmt) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
  }

  private func makeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
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

  @MainActor
  private func renderHistoryMetrics(
    overview: HistoryOverview,
    dynamicTypeSize: DynamicTypeSize,
    colorScheme: ColorScheme,
    filename: String
  ) throws {
    let content = ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: AppSpacing.xl) {
        HistoryWakeMetricsView(metrics: overview.wakeMetrics)
        HistoryMonthlyHeatmapView(
          heatmap: overview.monthlyHeatmap,
          calendar: overview.calendar
        )
      }
      .padding(AppSpacing.screenHorizontal)
    }
    .background(AppColor.babyBlue50)
    .environment(\.dynamicTypeSize, dynamicTypeSize)
    .environment(\.colorScheme, colorScheme)

    let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let hostingController = UIHostingController(rootView: content)
    let window = UIWindow(windowScene: windowScene)
    window.frame = bounds
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    hostingController.view.frame = bounds
    hostingController.view.layoutIfNeeded()

    let renderer = UIGraphicsImageRenderer(bounds: bounds)
    let image = renderer.image { _ in
      hostingController.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }
    window.isHidden = true

    let data = try XCTUnwrap(image.pngData())
    let url = URL(fileURLWithPath: "/private/tmp/\(filename)")
    try data.write(to: url, options: .atomic)

    XCTAssertGreaterThan(data.count, 1_000)
  }

  @MainActor
  private func makeSnapshot(
    id: UUID = UUID(),
    title: String = "스텝",
    order: Int = 0
  ) -> RoutineStepSnapshot {
    RoutineStepSnapshot(
      stepID: id,
      stepTitle: title,
      stepType: .confirm,
      stepOrder: order
    )
  }

  @MainActor
  private func makeCompletedResult(
    for snapshot: RoutineStepSnapshot,
    transcript: String? = nil
  ) -> RoutineStepResult {
    RoutineStepResult(
      stepID: snapshot.stepID,
      stepTitle: snapshot.stepTitle,
      stepType: snapshot.stepType,
      completedAt: Date(timeIntervalSince1970: 1),
      transcript: transcript
    )
  }

  @MainActor
  private func makeRun(
    id: UUID = UUID(),
    routineID: UUID = UUID(),
    routineName: String = "저장된 루틴",
    startedAt: Date,
    plannedSteps: [RoutineStepSnapshot],
    results: [RoutineStepResult] = [],
    endedEarly: Bool = false,
    isFinalized: Bool = true
  ) -> RoutineRun {
    RoutineRun(
      id: id,
      routineID: routineID,
      routineName: routineName,
      startedAt: startedAt,
      completedAt: isFinalized ? startedAt.addingTimeInterval(60) : nil,
      results: results,
      plannedSteps: plannedSteps,
      endedEarly: endedEarly
    )
  }
}

private enum HistoryRepositoryTestError: Error, Equatable {
  case unavailable
}

private final class HistoryRunRepositoryStub: RoutineRunRepository {
  private var runs: [RoutineRun]
  private let error: (any Error)?

  init(runs: [RoutineRun] = [], error: (any Error)? = nil) {
    self.runs = runs
    self.error = error
  }

  @MainActor
  func fetchRuns() throws -> [RoutineRun] {
    try fetchStoredRuns()
  }

  @MainActor
  func fetchRecentRuns(limit: Int) throws -> [RoutineRun] {
    Array(try fetchStoredRuns().prefix(limit))
  }

  @MainActor
  func fetchRuns(for routineID: UUID) throws -> [RoutineRun] {
    try fetchStoredRuns().filter { $0.routineID == routineID }
  }

  @MainActor
  func fetchRuns(from startDate: Date, to endDate: Date) throws -> [RoutineRun] {
    try fetchStoredRuns().filter { $0.startedAt >= startDate && $0.startedAt < endDate }
  }

  @MainActor
  func fetchRuns(
    for routineID: UUID,
    from startDate: Date,
    to endDate: Date
  ) throws -> [RoutineRun] {
    try fetchRuns(for: routineID)
      .filter { $0.startedAt >= startDate && $0.startedAt < endDate }
  }

  @MainActor
  func latestRun(for routineID: UUID) throws -> RoutineRun? {
    try fetchRuns(for: routineID).first
  }

  @MainActor
  func run(id: UUID) throws -> RoutineRun? {
    try fetchStoredRuns().first { $0.id == id }
  }

  @MainActor
  func saveRun(_ run: RoutineRun) throws {
    try throwErrorIfNeeded()

    if let index = runs.firstIndex(where: { $0.id == run.id }) {
      runs[index] = run
    } else {
      runs.append(run)
    }
  }

  @MainActor
  func deleteAllRuns() throws {
    try throwErrorIfNeeded()
    runs.removeAll()
  }

  @MainActor
  private func fetchStoredRuns() throws -> [RoutineRun] {
    try throwErrorIfNeeded()
    return runs
  }

  @MainActor
  private func throwErrorIfNeeded() throws {
    if let error {
      throw error
    }
  }
}
