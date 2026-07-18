//
//  HistoryRunReportingTests.swift
//  MoruTests
//

import Foundation
import SwiftData
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
      overview.week.dailyCompletionRates.dropFirst().allSatisfy { $0.completionRate == 0 }
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
  func testWakeMetricsUseOnlyFinalTerminalSnoozeObservations() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let rootObservedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let snoozeTerminalObservedAt = makeDate(2026, 7, 14, 7, 10, calendar: calendar)
    let validEvidence = mergeEvidence([
      makeTerminalEvidenceChain(
        rootOccurrenceID: "seven-o-clock-snooze-one",
        terminalMinute: 430,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: snoozeTerminalObservedAt,
        dayKey: "2026-07-14"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "seven-o-clock-snooze-two",
        terminalMinute: 430,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: snoozeTerminalObservedAt,
        dayKey: "2026-07-14"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "seven-o-clock-snooze-three",
        terminalMinute: 430,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: snoozeTerminalObservedAt,
        dayKey: "2026-07-14"
      ),
    ])
    let expectedMetrics: HistoryWakeMetrics = .calculated(
      observationCount: 3,
      averageWakeMinute: 430,
      averageDeviationMinutes: 0,
      consistencyScore: 100
    )
    let metrics = try makeUseCase(
      runs: [],
      evidence: validEvidence,
      resetGeneration: 7,
      calendar: calendar,
      now: now
    ).load().wakeMetrics

    XCTAssertEqual(metrics, expectedMetrics)
  }

  @MainActor
  func testWakeMetricsAcceptMultiHopSnoozeLineage() throws {
    let calendar = makeCalendar()
    let rootObservedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let terminalObservedAt = makeDate(2026, 7, 14, 7, 15, calendar: calendar)
    let evidence = mergeEvidence([
      makeTerminalEvidenceChain(
        rootOccurrenceID: "multi-hop-one",
        terminalMinute: 435,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: terminalObservedAt,
        dayKey: "2026-07-14",
        intermediateSnoozeCount: 2
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "multi-hop-two",
        terminalMinute: 435,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: terminalObservedAt,
        dayKey: "2026-07-14",
        intermediateSnoozeCount: 2
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "multi-hop-three",
        terminalMinute: 435,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: terminalObservedAt,
        dayKey: "2026-07-14",
        intermediateSnoozeCount: 2
      ),
    ])

    let metrics = try makeUseCase(
      runs: [],
      evidence: evidence,
      resetGeneration: 7,
      calendar: calendar,
      now: terminalObservedAt
    ).load().wakeMetrics

    XCTAssertEqual(
      metrics,
      .calculated(
        observationCount: 3,
        averageWakeMinute: 435,
        averageDeviationMinutes: 0,
        consistencyScore: 100
      )
    )
  }

  @MainActor
  func testWakeMetricsRejectCrossRecordTerminalEvidenceInconsistencies() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let rootObservedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let terminalObservedAt = makeDate(2026, 7, 14, 7, 10, calendar: calendar)
    let validEvidence = makeTerminalEvidence(minutes: [430, 430, 430], anchor: now)
    let expectedMetrics: HistoryWakeMetrics = .calculated(
      observationCount: 3,
      averageWakeMinute: 430,
      averageDeviationMinutes: 0,
      consistencyScore: 100
    )
    let invalidCases: [(name: String, mutation: TerminalEvidenceMutation)] = [
      ("open root state", .openRootState),
      ("lineage-conflict root state", .lineageConflictRootState),
      ("missing terminal reference", .missingTerminalReference),
      ("duplicate terminal observation", .duplicateTerminalObservation),
      ("mismatched earliest occurrence", .mismatchedEarliestObservedOccurrence),
      ("mismatched earliest timestamp", .mismatchedEarliestObservedAt),
      ("mismatched terminal root occurrence", .mismatchedTerminalRootOccurrence),
      ("cyclic terminal lineage", .cyclicLineage),
      ("duplicate intermediate observation", .duplicateIntermediateObservation),
      ("same-root branch observation", .sameRootBranch),
      ("reversed intermediate chronology", .reversedIntermediateChronology),
      ("mismatched root occurrence", .mismatchedRootOccurrence),
      ("mismatched root routine", .mismatchedRootRoutine),
      ("mismatched terminal routine", .mismatchedRoutine),
      ("mismatched root schedule", .mismatchedRootSchedule),
      ("mismatched terminal schedule", .mismatchedSchedule),
      ("mismatched root parent", .mismatchedRootParent),
      ("mismatched terminal parent", .mismatchedParent),
      ("mismatched terminal timestamp", .mismatchedTerminalTimestamp),
      ("mismatched latest occurrence", .mismatchedLatestOccurrence),
      ("mismatched latest timestamp", .mismatchedLatestTimestamp),
      ("mismatched root reset generation", .mismatchedRootResetGeneration),
      ("mismatched terminal reset generation", .mismatchedTerminalResetGeneration),
      ("mismatched root-state generation", .mismatchedRootStateGeneration),
      ("duplicate root-state record", .duplicateRootStateRecord),
      ("inconsistent root-state record", .inconsistentRootStateRecord),
      ("unrelated chain evidence", .unrelatedChainEvidence),
    ]

    for (offset, invalidCase) in invalidCases.enumerated() {
      let invalidEvidence = makeTerminalEvidenceChain(
        rootOccurrenceID: "invalid-\(offset)",
        terminalMinute: 440,
        rootObservedAt: rootObservedAt,
        terminalObservedAt: terminalObservedAt.addingTimeInterval(Double(offset + 1)),
        dayKey: "2026-07-14",
        mutation: invalidCase.mutation
      )
      let metrics = try makeUseCase(
        runs: [],
        evidence: mergeEvidence([validEvidence, invalidEvidence]),
        resetGeneration: 7,
        calendar: calendar,
        now: now
      ).load().wakeMetrics

      XCTAssertEqual(metrics, expectedMetrics, invalidCase.name)
    }
  }

  @MainActor
  func testWakeMetricsUseInsufficientModelStateForFewerThanThreeObservations() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let metrics = try makeUseCase(
      runs: [],
      evidence: makeTerminalEvidence(minutes: [430, 430], anchor: now),
      resetGeneration: 7,
      calendar: calendar,
      now: now
    ).load().wakeMetrics

    XCTAssertEqual(metrics, .insufficient(observationCount: 2))
    XCTAssertEqual(metrics.observationCount, 2)
    XCTAssertNil(metrics.averageWakeMinute)
    XCTAssertNil(metrics.averageDeviationMinutes)
    XCTAssertNil(metrics.consistencyScore)
  }

  @MainActor
  func testWakeMetricsAreUnavailableWhenCurrentGenerationIsNilOrZero() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    let resetGenerations: [UInt64?] = [nil, 0]

    for resetGeneration in resetGenerations {
      let metrics = try makeUseCase(
        runs: [],
        evidence: makeTerminalEvidence(minutes: [430, 430, 430], anchor: now),
        resetGeneration: resetGeneration,
        calendar: calendar,
        now: now
      ).load().wakeMetrics

      XCTAssertEqual(metrics, .unavailable)
    }
  }

  @MainActor
  func testWakeMetricsUseCircularMeanDeterministicTiesAndScoreBoundaries() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)

    let midnightMetrics = try loadWakeMetrics(
      minutes: [1_439, 0, 1],
      calendar: calendar,
      now: now
    )
    XCTAssertEqual(midnightMetrics.averageWakeMinute, 0)
    XCTAssertEqual(midnightMetrics.averageDeviationMinutes, 1)
    XCTAssertEqual(midnightMetrics.consistencyScore, 99)

    let tieMetrics = try loadWakeMetrics(
      minutes: [720, 0, 720, 0],
      calendar: calendar,
      now: now
    )
    XCTAssertEqual(tieMetrics.averageWakeMinute, 720)
    XCTAssertEqual(tieMetrics.averageDeviationMinutes, 360)
    XCTAssertEqual(tieMetrics.consistencyScore, 0)
    let sameTimestampTieMetrics = try makeUseCase(
      runs: [],
      evidence: mergeEvidence([
        makeTerminalEvidenceChain(
          rootOccurrenceID: "tie-z",
          terminalMinute: 720,
          rootObservedAt: now.addingTimeInterval(-600),
          terminalObservedAt: now,
          dayKey: "2026-07-14"
        ),
        makeTerminalEvidenceChain(
          rootOccurrenceID: "tie-a",
          terminalMinute: 0,
          rootObservedAt: now.addingTimeInterval(-600),
          terminalObservedAt: now,
          dayKey: "2026-07-14"
        ),
        makeTerminalEvidenceChain(
          rootOccurrenceID: "tie-y",
          terminalMinute: 720,
          rootObservedAt: now.addingTimeInterval(-600),
          terminalObservedAt: now,
          dayKey: "2026-07-14"
        ),
        makeTerminalEvidenceChain(
          rootOccurrenceID: "tie-b",
          terminalMinute: 0,
          rootObservedAt: now.addingTimeInterval(-600),
          terminalObservedAt: now,
          dayKey: "2026-07-14"
        ),
      ]),
      resetGeneration: 7,
      calendar: calendar,
      now: now
    ).load().wakeMetrics
    XCTAssertEqual(sameTimestampTieMetrics.averageWakeMinute, 0)
    XCTAssertEqual(sameTimestampTieMetrics.averageDeviationMinutes, 360)
    XCTAssertEqual(sameTimestampTieMetrics.consistencyScore, 0)

    let roundedMetrics = try loadWakeMetrics(
      minutes: [430, 430, 431, 431],
      calendar: calendar,
      now: now
    )
    XCTAssertEqual(roundedMetrics.averageWakeMinute, 431)
    XCTAssertEqual(roundedMetrics.averageDeviationMinutes, 1)
    XCTAssertEqual(roundedMetrics.consistencyScore, 99)

    for (deviation, expectedScore) in [(6, 90), (15, 75), (30, 50), (31, 48)] {
      let metrics = try loadWakeMetrics(
        minutes: [420 - deviation, 420 + deviation, 420 - deviation, 420 + deviation],
        calendar: calendar,
        now: now
      )

      XCTAssertEqual(metrics.averageWakeMinute, 420)
      XCTAssertEqual(metrics.averageDeviationMinutes, deviation)
      XCTAssertEqual(metrics.consistencyScore, expectedScore)
    }
  }

  @MainActor
  func testWakeMetricsUseStoredGregorianDayAndMinuteAcrossCalendarTravel() throws {
    let utcCalendar = makeCalendar()
    let now = makeDate(2026, 7, 28, 12, 0, calendar: utcCalendar)
    let oldActionDate = makeDate(2025, 1, 1, 0, 0, calendar: utcCalendar)
    let evidence = mergeEvidence([
      makeTerminalEvidenceChain(
        rootOccurrenceID: "travel-one",
        terminalMinute: 430,
        rootObservedAt: oldActionDate,
        terminalObservedAt: oldActionDate.addingTimeInterval(600),
        dayKey: "2026-07-01"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "travel-two",
        terminalMinute: 430,
        rootObservedAt: oldActionDate.addingTimeInterval(1_200),
        terminalObservedAt: oldActionDate.addingTimeInterval(1_800),
        dayKey: "2026-07-14"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "travel-three",
        terminalMinute: 430,
        rootObservedAt: oldActionDate.addingTimeInterval(2_400),
        terminalObservedAt: oldActionDate.addingTimeInterval(3_000),
        dayKey: "2026-07-28"
      ),
    ])
    let seoulCalendar = makeCalendar(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
    let losAngelesCalendar = makeCalendar(
      timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    )

    let seoulMetrics = try makeUseCase(
      runs: [],
      evidence: evidence,
      resetGeneration: 7,
      calendar: seoulCalendar,
      now: now
    ).load().wakeMetrics
    let losAngelesMetrics = try makeUseCase(
      runs: [],
      evidence: evidence,
      resetGeneration: 7,
      calendar: losAngelesCalendar,
      now: now
    ).load().wakeMetrics

    XCTAssertEqual(seoulMetrics, losAngelesMetrics)
    XCTAssertEqual(seoulMetrics.observationCount, 3)
    XCTAssertEqual(seoulMetrics.averageWakeMinute, 430)
    XCTAssertEqual(seoulMetrics.averageDeviationMinutes, 0)
    XCTAssertEqual(seoulMetrics.consistencyScore, 100)
  }

  @MainActor
  func testWakeMetricsUseExactTwentyEightDayStoredDayBoundaries() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 28, 12, 0, calendar: calendar)
    let evidence = mergeEvidence([
      makeTerminalEvidenceChain(
        rootOccurrenceID: "before-window",
        terminalMinute: 430,
        rootObservedAt: now.addingTimeInterval(-600),
        terminalObservedAt: now,
        dayKey: "2026-06-30"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "window-start",
        terminalMinute: 430,
        rootObservedAt: now.addingTimeInterval(-600),
        terminalObservedAt: now.addingTimeInterval(60),
        dayKey: "2026-07-01"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "today-one",
        terminalMinute: 430,
        rootObservedAt: now.addingTimeInterval(-600),
        terminalObservedAt: now.addingTimeInterval(120),
        dayKey: "2026-07-28"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "today-two",
        terminalMinute: 430,
        rootObservedAt: now.addingTimeInterval(-600),
        terminalObservedAt: now.addingTimeInterval(180),
        dayKey: "2026-07-28"
      ),
      makeTerminalEvidenceChain(
        rootOccurrenceID: "after-window",
        terminalMinute: 430,
        rootObservedAt: now.addingTimeInterval(-600),
        terminalObservedAt: now.addingTimeInterval(240),
        dayKey: "2026-07-29"
      ),
    ])
    let metrics = try makeUseCase(
      runs: [],
      evidence: evidence,
      resetGeneration: 7,
      calendar: calendar,
      now: now
    ).load().wakeMetrics

    XCTAssertEqual(metrics.observationCount, 3)
    XCTAssertEqual(metrics.averageWakeMinute, 430)
    XCTAssertEqual(metrics.averageDeviationMinutes, 0)
    XCTAssertEqual(metrics.consistencyScore, 100)
  }

  @MainActor
  func testMonthlyHeatmapUsesMondayFillersAndOnlyFinalCompletedRuns() throws {
    let calendar = makeCalendar()
    let now = makeDate(2026, 7, 14, 12, 0, calendar: calendar)
    func july(_ day: Int, _ hour: Int = 7) -> Date {
      makeDate(2026, 7, day, hour, 0, calendar: calendar)
    }
    let runs = [
      makeRunWithCompletionRate(startedAt: july(1), completedStepCount: 0, totalStepCount: 1),
      makeRunWithCompletionRate(startedAt: july(2), completedStepCount: 1, totalStepCount: 5),
      makeRunWithCompletionRate(startedAt: july(3), completedStepCount: 1, totalStepCount: 4),
      makeRunWithCompletionRate(startedAt: july(4), completedStepCount: 1, totalStepCount: 2),
      makeRunWithCompletionRate(startedAt: july(5), completedStepCount: 1, totalStepCount: 2),
      makeRunWithCompletionRate(startedAt: july(5, 8), completedStepCount: 3, totalStepCount: 3),
      makeRunWithCompletionRate(
        startedAt: july(5, 9),
        completedStepCount: 1,
        totalStepCount: 1,
        endedEarly: true
      ),
      makeRunWithCompletionRate(
        startedAt: july(5, 10),
        completedStepCount: 0,
        totalStepCount: 1,
        isFinalized: false
      ),
      makeRunWithCompletionRate(
        startedAt: july(5, 11),
        completedStepCount: 0,
        totalStepCount: 1,
        completedAt: july(15)
      ),
      makeRunWithCompletionRate(startedAt: july(15), completedStepCount: 1, totalStepCount: 1),
    ]
    let heatmap = try makeUseCase(
      runs: runs,
      calendar: calendar,
      now: now
    ).load().monthlyHeatmap

    XCTAssertEqual(heatmap.monthStartDate, july(1, 0))
    XCTAssertEqual(heatmap.days.count, 16)
    XCTAssertEqual(heatmap.days.prefix(2).map(\.id), ["filler-0", "filler-1"])
    XCTAssertTrue(heatmap.days.prefix(2).allSatisfy { $0.date == nil && $0.bucket == .noData })
    XCTAssertEqual(heatmap.days[2].date, july(1, 0))
    XCTAssertTrue(heatmap.days.compactMap(\.date).allSatisfy { $0 <= now })
    XCTAssertFalse(heatmap.days.contains { $0.date == july(15, 0) })

    func day(_ value: Int) throws -> HistoryHeatmapDay {
      try XCTUnwrap(heatmap.days.first { $0.date == july(value, 0) })
    }

    XCTAssertNil(try day(1).completionRate)
    XCTAssertEqual(try day(1).bucket, .noData)
    XCTAssertNil(try day(2).completionRate)
    XCTAssertEqual(try day(2).bucket, .noData)
    XCTAssertNil(try day(3).completionRate)
    XCTAssertEqual(try day(3).bucket, .noData)
    XCTAssertNil(try day(4).completionRate)
    XCTAssertEqual(try day(4).bucket, .noData)
    XCTAssertEqual(try day(5).completionRate, 1)
    XCTAssertEqual(try day(5).bucket, .complete)
    XCTAssertNil(try day(6).completionRate)
    XCTAssertEqual(try day(6).bucket, .noData)
  }

  @MainActor
  func testHeatmapPresentationHidesMondayAlignmentFillersFromAccessibility() {
    let presentation = HistoryHeatmapCellPresentation(
      day: HistoryHeatmapDay(id: "filler-0", date: nil, completionRate: nil),
      calendar: makeCalendar()
    )

    XCTAssertTrue(presentation.isAccessibilityHidden)
    XCTAssertNil(presentation.accessibilityLabel)
  }

  @MainActor
  func testHeatmapPresentationLabelsDatedNoDataCellWithItsFullDate() {
    let calendar = makeCalendar()
    let presentation = HistoryHeatmapCellPresentation(
      day: HistoryHeatmapDay(
        id: "2026-07-14",
        date: makeDate(2026, 7, 14, 0, 0, calendar: calendar),
        completionRate: nil
      ),
      calendar: calendar
    )

    XCTAssertFalse(presentation.isAccessibilityHidden)
    XCTAssertEqual(presentation.accessibilityLabel, "2026년 7월 14일, 기록 없음")
  }

  @MainActor
  func testHeatmapPresentationLabelsRatedCellWithItsFullDateAndPercentage() {
    let calendar = makeCalendar()
    let presentation = HistoryHeatmapCellPresentation(
      day: HistoryHeatmapDay(
        id: "2026-07-14",
        date: makeDate(2026, 7, 14, 0, 0, calendar: calendar),
        completionRate: 0.625
      ),
      calendar: calendar
    )

    XCTAssertFalse(presentation.isAccessibilityHidden)
    XCTAssertEqual(presentation.accessibilityLabel, "2026년 7월 14일, 완료율 63퍼센트")
  }

  @MainActor
  func testSwiftDataHistoryEvidenceRepositoryAssemblesValidTerminalEvidence() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    insertPersistedTerminalEvidence(into: context)
    try context.save()

    let evidence = try SwiftDataHistoryEvidenceRepository(modelContext: context).fetchEvidence()

    XCTAssertEqual(
      evidence.observations.map(\.occurrenceID),
      ["root-observation", "terminal-observation"]
    )
    XCTAssertEqual(evidence.rootChainStates.count, 1)
    XCTAssertEqual(evidence.rootChainStates[0].terminalOccurrenceID, "terminal-observation")
    XCTAssertEqual(evidence.rootChainStates[0].state, .terminal)
  }

  @MainActor
  func testSwiftDataHistoryEvidenceRepositoryRejectsMissingTerminalObservation() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    insertPersistedTerminalEvidence(into: context, includeTerminal: false)
    try context.save()

    XCTAssertThrowsError(
      try SwiftDataHistoryEvidenceRepository(modelContext: context).fetchEvidence()
    ) {
      XCTAssertEqual($0 as? PersistenceV2MappingError, .terminalObservationMissing)
    }
  }

  @MainActor
  func testSwiftDataHistoryEvidenceRepositoryRejectsMismatchedTerminalObservation() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    insertPersistedTerminalEvidence(
      into: context,
      terminalRootOccurrenceID: "different-root-occurrence"
    )
    try context.save()

    XCTAssertThrowsError(
      try SwiftDataHistoryEvidenceRepository(modelContext: context).fetchEvidence()
    ) {
      XCTAssertEqual($0 as? PersistenceV2MappingError, .terminalObservationMismatch)
    }
  }

  @MainActor
  func testSwiftDataHistoryEvidenceRepositoryRejectsDuplicateTerminalObservation() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    insertPersistedTerminalEvidence(into: context, duplicateTerminal: true)

    XCTAssertThrowsError(
      try SwiftDataHistoryEvidenceRepository(modelContext: context).fetchEvidence()
    ) {
      XCTAssertEqual($0 as? PersistenceV2MappingError, .terminalObservationMissing)
    }
  }

  @MainActor
  func testHistoryRethrowsRepositoryErrors() {
    let calendar = makeCalendar()
    let repository = HistoryRunRepositoryStub(error: HistoryRepositoryTestError.unavailable)
    let useCase = LoadHistoryUseCase(
      routineRunRepository: repository,
      historyEvidenceRepository: HistoryEvidenceRepositoryStub(evidence: .empty),
      currentResetGeneration: { nil },
      calendar: calendar,
      now: { self.makeDate(2026, 7, 14, 12, 0, calendar: calendar) }
    )

    XCTAssertThrowsError(try useCase.load()) { error in
      XCTAssertEqual(error as? HistoryRepositoryTestError, .unavailable)
    }
  }

  @MainActor
  private func makeUseCase(
    runs: [RoutineRun],
    evidence: HistoryEvidence = .empty,
    resetGeneration: UInt64? = nil,
    calendar: Calendar,
    now: Date
  ) -> LoadHistoryUseCase {
    LoadHistoryUseCase(
      routineRunRepository: HistoryRunRepositoryStub(runs: runs),
      historyEvidenceRepository: HistoryEvidenceRepositoryStub(evidence: evidence),
      currentResetGeneration: { resetGeneration },
      calendar: calendar,
      now: { now }
    )
  }

  @MainActor
  private func loadWakeMetrics(
    minutes: [Int],
    calendar: Calendar,
    now: Date
  ) throws -> HistoryWakeMetrics {
    try makeUseCase(
      runs: [],
      evidence: makeTerminalEvidence(minutes: minutes, anchor: now),
      resetGeneration: 7,
      calendar: calendar,
      now: now
    ).load().wakeMetrics
  }

  @MainActor
  private func makeTerminalEvidence(
    minutes: [Int],
    dayKey: String = "2026-07-14",
    anchor: Date
  ) -> HistoryEvidence {
    mergeEvidence(
      minutes.enumerated().map { offset, minute in
        makeTerminalEvidenceChain(
          rootOccurrenceID: "valid-\(offset)-\(minute)",
          terminalMinute: minute,
          rootObservedAt: anchor.addingTimeInterval(Double(offset * 60 - 600)),
          terminalObservedAt: anchor.addingTimeInterval(Double(offset * 60)),
          dayKey: dayKey
        )
      }
    )
  }

  @MainActor
  private func makeTerminalEvidenceChain(
    rootOccurrenceID: String,
    terminalMinute: Int,
    rootObservedAt: Date,
    terminalObservedAt: Date,
    dayKey: String,
    intermediateSnoozeCount: Int = 0,
    mutation: TerminalEvidenceMutation? = nil
  ) -> HistoryEvidence {
    let rootObservationID = "\(rootOccurrenceID)-root"
    let terminalObservationID = "\(rootOccurrenceID)-snooze"
    let unrelatedObservationID = "\(rootOccurrenceID)-unrelated"
    let routineID = UUID()
    let scheduleID = UUID()
    let rootState: AlarmRootChainState
    switch mutation {
    case .openRootState:
      rootState = .open
    case .lineageConflictRootState:
      rootState = .lineageConflict
    default:
      rootState = .terminal
    }

    let requiresIntermediate: Bool
    switch mutation {
    case .cyclicLineage,
         .duplicateIntermediateObservation,
         .sameRootBranch,
         .reversedIntermediateChronology:
      requiresIntermediate = true
    default:
      requiresIntermediate = false
    }
    let intermediateCount = max(intermediateSnoozeCount, requiresIntermediate ? 1 : 0)
    let intermediateObservationIDs = (0..<intermediateCount).map {
      "\(rootOccurrenceID)-snooze-\($0)"
    }
    let rootStateGeneration: UInt64 = mutation == .mismatchedRootStateGeneration ? 8 : 7
    let rootObservationGeneration: UInt64 = mutation == .mismatchedRootResetGeneration
      ? 8
      : rootStateGeneration
    let terminalObservationGeneration: UInt64 = mutation == .mismatchedTerminalResetGeneration
      ? 8
      : rootStateGeneration
    let rootObservationRootOccurrenceID = mutation == .mismatchedRootOccurrence
      ? "\(rootOccurrenceID)-other-root"
      : rootOccurrenceID
    let terminalObservationRootOccurrenceID = mutation == .mismatchedTerminalRootOccurrence
      ? "\(rootOccurrenceID)-other-root"
      : rootOccurrenceID
    let rootRoutineID = mutation == .mismatchedRootRoutine ? UUID() : routineID
    let rootScheduleID = mutation == .mismatchedRootSchedule ? UUID() : scheduleID
    let rootParentOccurrenceID = mutation == .mismatchedRootParent
      ? "\(rootOccurrenceID)-unexpected-parent"
      : nil
    let terminalRoutineID = mutation == .mismatchedRoutine ? UUID() : routineID
    let terminalScheduleID = mutation == .mismatchedSchedule ? UUID() : scheduleID
    let terminalParentOccurrenceID: String?
    switch mutation {
    case .mismatchedParent:
      terminalParentOccurrenceID = "\(rootOccurrenceID)-missing-parent"
    case .unrelatedChainEvidence:
      terminalParentOccurrenceID = unrelatedObservationID
    default:
      terminalParentOccurrenceID = intermediateObservationIDs.last ?? rootObservationID
    }

    let terminalAt = mutation == .mismatchedTerminalTimestamp
      ? terminalObservedAt.addingTimeInterval(1)
      : terminalObservedAt
    let latestObservedOccurrenceID = mutation == .mismatchedLatestOccurrence
      ? rootObservationID
      : terminalObservationID
    let latestObservedAt = mutation == .mismatchedLatestTimestamp
      ? terminalAt.addingTimeInterval(1)
      : latestObservedOccurrenceID == terminalObservationID ? terminalAt : rootObservedAt
    let earliestObservedOccurrenceID = mutation == .mismatchedEarliestObservedOccurrence
      ? terminalObservationID
      : rootObservationID
    let earliestObservedAt = mutation == .mismatchedEarliestObservedAt
      ? rootObservedAt.addingTimeInterval(1)
      : rootObservedAt
    let includesTerminalReference = mutation != .missingTerminalReference
    let rootObservation = makeAlarmObservation(
      occurrenceID: rootObservationID,
      rootOccurrenceID: rootObservationRootOccurrenceID,
      parentOccurrenceID: rootParentOccurrenceID,
      routineID: rootRoutineID,
      scheduleID: rootScheduleID,
      actionObservedAt: rootObservedAt,
      dayKey: dayKey,
      localMinute: 420,
      resetGeneration: rootObservationGeneration
    )
    let intermediateObservations = intermediateObservationIDs.enumerated().map {
      index,
      occurrenceID in
      let interval = terminalObservedAt.timeIntervalSince(rootObservedAt)
      let actionObservedAt = mutation == .reversedIntermediateChronology
        && index == intermediateObservationIDs.count - 1
        ? terminalObservedAt.addingTimeInterval(1)
        : rootObservedAt.addingTimeInterval(
          interval * Double(index + 1) / Double(intermediateObservationIDs.count + 1)
        )
      let parentOccurrenceID = mutation == .cyclicLineage && index == 0
        ? terminalObservationID
        : index == 0 ? rootObservationID : intermediateObservationIDs[index - 1]

      return makeAlarmObservation(
        occurrenceID: occurrenceID,
        rootOccurrenceID: rootOccurrenceID,
        parentOccurrenceID: parentOccurrenceID,
        routineID: routineID,
        scheduleID: scheduleID,
        actionObservedAt: actionObservedAt,
        dayKey: dayKey,
        localMinute: terminalMinute,
        resetGeneration: rootStateGeneration
      )
    }
    let terminalObservation = makeAlarmObservation(
      occurrenceID: terminalObservationID,
      rootOccurrenceID: terminalObservationRootOccurrenceID,
      parentOccurrenceID: terminalParentOccurrenceID,
      routineID: terminalRoutineID,
      scheduleID: terminalScheduleID,
      actionObservedAt: terminalObservedAt,
      dayKey: dayKey,
      localMinute: terminalMinute,
      resetGeneration: terminalObservationGeneration
    )
    var observations = [rootObservation] + intermediateObservations + [terminalObservation]

    if mutation == .duplicateTerminalObservation {
      observations.append(
        makeAlarmObservation(
          occurrenceID: terminalObservationID,
          rootOccurrenceID: terminalObservationRootOccurrenceID,
          parentOccurrenceID: terminalParentOccurrenceID,
          routineID: terminalRoutineID,
          scheduleID: terminalScheduleID,
          actionObservedAt: terminalObservedAt,
          dayKey: dayKey,
          localMinute: terminalMinute,
          resetGeneration: terminalObservationGeneration
        )
      )
    }

    if mutation == .duplicateIntermediateObservation,
       let intermediateObservation = intermediateObservations.first {
      observations.append(intermediateObservation)
    }

    if mutation == .sameRootBranch {
      observations.append(
        makeAlarmObservation(
          occurrenceID: "\(rootOccurrenceID)-branch",
          rootOccurrenceID: rootOccurrenceID,
          parentOccurrenceID: rootObservationID,
          routineID: routineID,
          scheduleID: scheduleID,
          actionObservedAt: rootObservedAt.addingTimeInterval(1),
          dayKey: dayKey,
          localMinute: terminalMinute,
          resetGeneration: rootStateGeneration
        )
      )
    }

    if mutation == .unrelatedChainEvidence {
      observations.append(
        makeAlarmObservation(
          occurrenceID: unrelatedObservationID,
          rootOccurrenceID: "\(rootOccurrenceID)-unrelated-root",
          parentOccurrenceID: nil,
          routineID: routineID,
          scheduleID: scheduleID,
          actionObservedAt: rootObservedAt,
          dayKey: dayKey,
          localMinute: 420,
          resetGeneration: rootStateGeneration
        )
      )
    }

    let rootStateSnapshot = AlarmRootChainStateSnapshot(
      id: UUID(),
      rootOccurrenceID: rootOccurrenceID,
      routineID: routineID,
      scheduleID: scheduleID,
      resetGeneration: rootStateGeneration,
      rootFingerprint: "root-\(rootOccurrenceID)",
      earliestObservedOccurrenceID: earliestObservedOccurrenceID,
      earliestObservedAt: earliestObservedAt,
      latestObservedOccurrenceID: latestObservedOccurrenceID,
      latestObservedAt: latestObservedAt,
      terminalOccurrenceID: includesTerminalReference ? terminalObservationID : nil,
      terminalAt: includesTerminalReference ? terminalAt : nil,
      state: rootState,
      updatedAt: terminalObservedAt
    )
    var rootChainStates = [rootStateSnapshot]

    if mutation == .duplicateRootStateRecord {
      rootChainStates.append(rootStateSnapshot)
    }

    if mutation == .inconsistentRootStateRecord {
      rootChainStates.append(
        AlarmRootChainStateSnapshot(
          id: UUID(),
          rootOccurrenceID: rootOccurrenceID,
          routineID: UUID(),
          scheduleID: scheduleID,
          resetGeneration: rootStateGeneration,
          rootFingerprint: "root-\(rootOccurrenceID)",
          earliestObservedOccurrenceID: earliestObservedOccurrenceID,
          earliestObservedAt: earliestObservedAt,
          latestObservedOccurrenceID: latestObservedOccurrenceID,
          latestObservedAt: latestObservedAt,
          terminalOccurrenceID: includesTerminalReference ? terminalObservationID : nil,
          terminalAt: includesTerminalReference ? terminalAt : nil,
          state: rootState,
          updatedAt: terminalObservedAt
        )
      )
    }

    return HistoryEvidence(observations: observations, rootChainStates: rootChainStates)
  }

  @MainActor
  private func insertPersistedTerminalEvidence(
    into context: ModelContext,
    terminalRootOccurrenceID: String = "root-occurrence",
    includeTerminal: Bool = true,
    duplicateTerminal: Bool = false
  ) {
    let calendar = makeCalendar()
    let rootOccurrenceID = "root-occurrence"
    let rootObservationID = "root-observation"
    let terminalObservationID = "terminal-observation"
    let rootObservedAt = makeDate(2026, 7, 14, 7, 0, calendar: calendar)
    let terminalObservedAt = makeDate(2026, 7, 14, 7, 10, calendar: calendar)
    let routineID = UUID()
    let scheduleID = UUID()
    let resetGeneration: UInt64 = 7

    context.insert(
      makePersistedHistoryObservation(
        occurrenceID: rootObservationID,
        rootOccurrenceID: rootOccurrenceID,
        parentOccurrenceID: nil,
        routineID: routineID,
        scheduleID: scheduleID,
        actionObservedAt: rootObservedAt,
        localMinute: 420,
        resetGeneration: resetGeneration
      )
    )

    if includeTerminal {
      let terminalObservation = makePersistedHistoryObservation(
        occurrenceID: terminalObservationID,
        rootOccurrenceID: terminalRootOccurrenceID,
        parentOccurrenceID: rootObservationID,
        routineID: routineID,
        scheduleID: scheduleID,
        actionObservedAt: terminalObservedAt,
        localMinute: 430,
        resetGeneration: resetGeneration
      )
      context.insert(terminalObservation)

      if duplicateTerminal {
        context.insert(
          makePersistedHistoryObservation(
            occurrenceID: terminalObservationID,
            rootOccurrenceID: terminalRootOccurrenceID,
            parentOccurrenceID: rootObservationID,
            routineID: routineID,
            scheduleID: scheduleID,
            actionObservedAt: terminalObservedAt,
            localMinute: 430,
            resetGeneration: resetGeneration
          )
        )
      }
    }

    context.insert(
      PersistedAlarmRootChainState(
        id: UUID(),
        rootOccurrenceID: rootOccurrenceID,
        routineID: routineID,
        scheduleID: scheduleID,
        resetGeneration: resetGeneration,
        rootFingerprint: String(repeating: "a", count: 64),
        earliestObservedOccurrenceID: rootObservationID,
        earliestObservedAt: rootObservedAt,
        latestObservedOccurrenceID: terminalObservationID,
        latestObservedAt: terminalObservedAt,
        terminalOccurrenceID: terminalObservationID,
        terminalAt: terminalObservedAt,
        stateRawValue: AlarmRootChainState.terminal.rawValue,
        updatedAt: terminalObservedAt
      )
    )
  }

  @MainActor
  private func makePersistedHistoryObservation(
    occurrenceID: String,
    rootOccurrenceID: String,
    parentOccurrenceID: String?,
    routineID: UUID,
    scheduleID: UUID,
    actionObservedAt: Date,
    localMinute: Int,
    resetGeneration: UInt64
  ) -> PersistedScheduledAlarmStartObservation {
    PersistedScheduledAlarmStartObservation(
      id: UUID(),
      occurrenceID: occurrenceID,
      rootOccurrenceID: rootOccurrenceID,
      parentOccurrenceID: parentOccurrenceID,
      routineID: routineID,
      scheduleID: scheduleID,
      actionObservedAt: actionObservedAt,
      scheduledFireAt: actionObservedAt,
      resetGeneration: resetGeneration,
      sourceRawValue: ScheduledAlarmObservationSource.alarmKitOccurrenceActionV1.rawValue,
      immutableFingerprint: String(repeating: "a", count: 64),
      timeZoneIdentifier: "Asia/Seoul",
      utcOffsetSeconds: 32_400,
      localGregorianDayKey: "2026-07-14",
      localGregorianDayOrdinal: 195,
      localMinute: localMinute,
      receivedAt: actionObservedAt
    )
  }

  @MainActor
  private func makeAlarmObservation(
    occurrenceID: String,
    rootOccurrenceID: String,
    parentOccurrenceID: String?,
    routineID: UUID,
    scheduleID: UUID,
    actionObservedAt: Date,
    dayKey: String,
    localMinute: Int,
    resetGeneration: UInt64
  ) -> ScheduledAlarmStartObservationSnapshot {
    ScheduledAlarmStartObservationSnapshot(
      id: UUID(),
      occurrenceID: occurrenceID,
      rootOccurrenceID: rootOccurrenceID,
      parentOccurrenceID: parentOccurrenceID,
      routineID: routineID,
      scheduleID: scheduleID,
      actionObservedAt: actionObservedAt,
      scheduledFireAt: actionObservedAt,
      resetGeneration: resetGeneration,
      source: .alarmKitOccurrenceActionV1,
      immutableFingerprint: "fingerprint-\(occurrenceID)",
      timeZoneIdentifier: "Asia/Seoul",
      utcOffsetSeconds: 32_400,
      localGregorianDayKey: dayKey,
      localGregorianDayOrdinal: 0,
      localMinute: localMinute,
      receivedAt: actionObservedAt
    )
  }

  @MainActor
  private func mergeEvidence(_ evidence: [HistoryEvidence]) -> HistoryEvidence {
    HistoryEvidence(
      observations: evidence.flatMap(\.observations),
      rootChainStates: evidence.flatMap(\.rootChainStates)
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
  private func makeRunWithCompletionRate(
    startedAt: Date,
    completedStepCount: Int,
    totalStepCount: Int,
    endedEarly: Bool = false,
    isFinalized: Bool = true,
    completedAt: Date? = nil
  ) -> RoutineRun {
    let snapshots = (0..<totalStepCount).map {
      makeSnapshot(title: "스텝 \($0)", order: $0)
    }

    return makeRun(
      startedAt: startedAt,
      plannedSteps: snapshots,
      results: snapshots.prefix(completedStepCount).map { makeCompletedResult(for: $0) },
      endedEarly: endedEarly,
      isFinalized: isFinalized,
      completedAt: completedAt
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
    isFinalized: Bool = true,
    completedAt: Date? = nil
  ) -> RoutineRun {
    RoutineRun(
      id: id,
      routineID: routineID,
      routineName: routineName,
      startedAt: startedAt,
      completedAt: completedAt ?? (isFinalized ? startedAt.addingTimeInterval(60) : nil),
      results: results,
      plannedSteps: plannedSteps,
      endedEarly: endedEarly
    )
  }
}
private enum TerminalEvidenceMutation: Equatable {
  case openRootState
  case lineageConflictRootState
  case missingTerminalReference
  case duplicateTerminalObservation
  case mismatchedEarliestObservedOccurrence
  case mismatchedEarliestObservedAt
  case mismatchedTerminalRootOccurrence
  case cyclicLineage
  case duplicateIntermediateObservation
  case sameRootBranch
  case reversedIntermediateChronology
  case mismatchedRootOccurrence
  case mismatchedRootRoutine
  case mismatchedRootSchedule
  case mismatchedRootParent
  case mismatchedRoutine
  case mismatchedSchedule
  case mismatchedParent
  case mismatchedTerminalTimestamp
  case mismatchedLatestOccurrence
  case mismatchedLatestTimestamp
  case mismatchedRootResetGeneration
  case mismatchedTerminalResetGeneration
  case mismatchedRootStateGeneration
  case duplicateRootStateRecord
  case inconsistentRootStateRecord
  case unrelatedChainEvidence
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

private final class HistoryEvidenceRepositoryStub: HistoryEvidenceRepository {
  private let evidence: HistoryEvidence

  init(evidence: HistoryEvidence) {
    self.evidence = evidence
  }

  @MainActor
  func fetchEvidence() throws -> HistoryEvidence {
    evidence
  }
}
