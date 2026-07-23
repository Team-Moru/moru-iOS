//
//  RoutineStreakCalculatorTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

final class RoutineStreakCalculatorTests: XCTestCase {
  @MainActor
  func testCurrentStreakUsesTodayOrYesterdayAndBestStreakStopsAtMissingDates() {
    let calendar = makeCalendar()
    let currentDate = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let runs = [
      completedRun(at: makeDate(2026, 7, 8, 7, 0, calendar: calendar)),
      completedRun(at: makeDate(2026, 7, 9, 7, 0, calendar: calendar)),
      completedRun(at: makeDate(2026, 7, 10, 7, 0, calendar: calendar)),
      completedRun(at: makeDate(2026, 7, 13, 7, 0, calendar: calendar)),
      completedRun(at: makeDate(2026, 7, 14, 7, 0, calendar: calendar)),
    ]

    let streak = RoutineStreakCalculator(calendar: calendar).calculate(
      from: runs,
      asOf: currentDate
    )

    XCTAssertEqual(streak.currentDays, 2)
    XCTAssertEqual(streak.bestDays, 3)
    XCTAssertEqual(streak.completedWeekdays, [.monday, .tuesday])

    let nextDate = makeDate(2026, 7, 15, 12, 0, calendar: calendar)
    let yesterdayAnchoredStreak = RoutineStreakCalculator(calendar: calendar).calculate(
      from: runs,
      asOf: nextDate
    )

    XCTAssertEqual(yesterdayAnchoredStreak.currentDays, 2)
    XCTAssertEqual(yesterdayAnchoredStreak.bestDays, 3)
  }

  @MainActor
  func testMultipleCompletedRunsOnSameDayCountAsOneDay() {
    let calendar = makeCalendar()
    let currentDate = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let runs = [
      completedRun(at: makeDate(2026, 7, 13, 7, 0, calendar: calendar)),
      completedRun(at: makeDate(2026, 7, 14, 7, 0, calendar: calendar)),
      completedRun(at: makeDate(2026, 7, 14, 9, 0, calendar: calendar)),
    ]

    let streak = RoutineStreakCalculator(calendar: calendar).calculate(
      from: runs,
      asOf: currentDate
    )

    XCTAssertEqual(streak.currentDays, 2)
    XCTAssertEqual(streak.bestDays, 2)
  }

  @MainActor
  func testCompletionDateOwnsTheDayAcrossMidnight() {
    let calendar = makeCalendar()
    let startedAt = makeDate(2026, 7, 13, 23, 59, calendar: calendar)
    let completedAt = makeDate(2026, 7, 14, 0, 1, calendar: calendar)
    let currentDate = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let run = completedRun(startedAt: startedAt, completedAt: completedAt)

    let streak = RoutineStreakCalculator(calendar: calendar).calculate(
      from: [run],
      asOf: currentDate
    )

    XCTAssertEqual(streak.currentDays, 1)
    XCTAssertEqual(streak.bestDays, 1)
    XCTAssertEqual(streak.completedWeekdays, [.tuesday])
  }

  @MainActor
  func testPartialEndedEarlyNonterminalAndFutureRunsDoNotIncreaseStreak() {
    let calendar = makeCalendar()
    let currentDate = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let today = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let future = makeDate(2026, 7, 14, 13, 0, calendar: calendar)
    let partial = partialRun(at: today)
    var endedEarly = completedRun(at: today)
    endedEarly.endedEarly = true
    var nonterminal = completedRun(at: today)
    nonterminal.completedAt = nil

    let streak = RoutineStreakCalculator(calendar: calendar).calculate(
      from: [
        partial,
        endedEarly,
        nonterminal,
        completedRun(at: future),
      ],
      asOf: currentDate
    )

    XCTAssertEqual(streak, .empty)
  }

  @MainActor
  func testRegularFinalizerRecalculatesStreakAfterSaving() throws {
    let calendar = makeCalendar()
    let yesterday = makeDate(2026, 7, 13, 7, 0, calendar: calendar)
    let today = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let repository = MockRoutineRunRepository(runs: [completedRun(at: yesterday)])
    let routine = makeRoutine()
    let result = completedResult(for: routine.steps[0], at: today)
    let finalizer = DefaultRegularRoutineFinalizer(
      saveRoutineRunUseCase: SaveRoutineRunUseCase(
        routineRunRepository: repository
      ),
      routineRunRepository: repository,
      calendar: calendar
    )

    let summary = try finalizer.finalize(
      SaveRoutineRunRequest(
        runID: UUID(),
        routine: routine,
        startedAt: today.addingTimeInterval(-60),
        completedAt: today,
        results: [result],
        endedEarly: false
      )
    )

    XCTAssertNotNil(summary.persistedRunID)
    XCTAssertEqual(
      summary.streak,
      RoutineStreak(
        currentDays: 2,
        bestDays: 2,
        completedWeekdays: [.monday, .tuesday]
      )
    )
    XCTAssertEqual(try repository.fetchRuns().count, 2)
  }

  @MainActor
  func testTrialSummaryHasNoStreak() throws {
    let routine = makeRoutine()
    let completedAt = Date(timeIntervalSince1970: 2)
    let summary = try makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: Date(timeIntervalSince1970: 1),
      completedAt: completedAt,
      results: [completedResult(for: routine.steps[0], at: completedAt)],
      endedEarly: false
    ).get()

    XCTAssertNil(summary.streak)
  }

  private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
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
  private func makeRoutine() -> Routine {
    Routine(
      name: "아침 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "물 마시기", order: 0),
      ]
    )
  }

  @MainActor
  private func completedRun(at date: Date) -> RoutineRun {
    completedRun(startedAt: date, completedAt: date)
  }

  @MainActor
  private func completedRun(startedAt: Date, completedAt: Date) -> RoutineRun {
    let routine = makeRoutine()

    return RoutineRun(
      routine: routine,
      startedAt: startedAt,
      completedAt: completedAt,
      results: [completedResult(for: routine.steps[0], at: completedAt)]
    )
  }

  @MainActor
  private func partialRun(at date: Date) -> RoutineRun {
    let routine = Routine(
      name: "부분 완료 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "첫 단계", order: 0),
        RoutineStep(type: .confirm, title: "둘째 단계", order: 1),
      ]
    )

    return RoutineRun(
      routine: routine,
      startedAt: date,
      completedAt: date,
      results: [completedResult(for: routine.steps[0], at: date)]
    )
  }

  @MainActor
  private func completedResult(
    for step: RoutineStep,
    at date: Date
  ) -> RoutineStepResult {
    RoutineStepResult(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      completedAt: date
    )
  }
}
