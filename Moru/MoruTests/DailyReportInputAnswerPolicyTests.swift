//
//  DailyReportInputAnswerPolicyTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

@MainActor
final class DailyReportInputAnswerPolicyTests: XCTestCase {
  func testLocalReportShowsOnlyCompletedInputResultsWithAnAnswer() {
    let completedAt = Date(timeIntervalSince1970: 100)
    let results = [
      localResult(
        stepType: .input,
        completedAt: completedAt,
        transcript: "  오늘의 다짐  "
      ),
      localResult(
        stepType: .input,
        completedAt: completedAt,
        inputText: "  직접 입력한 기록  "
      ),
      localResult(
        stepType: .input,
        completedAt: completedAt,
        transcript: " \n "
      ),
      localResult(
        stepType: .input,
        completedAt: completedAt,
        skipped: true,
        transcript: "건너뛴 입력"
      ),
      localResult(
        stepType: .confirm,
        completedAt: completedAt,
        transcript: "완료했어요"
      ),
      localResult(
        stepType: .timer,
        completedAt: completedAt,
        inputText: "타이머 결과"
      ),
    ]

    let answers = results.compactMap {
      DailyReportInputAnswerPolicy.answer(for: $0)
    }

    XCTAssertEqual(answers, ["오늘의 다짐", "직접 입력한 기록"])
  }

  func testServerReportShowsOnlyCompletedInputResultsWithAnAnswer() {
    let routines = [
      serverRoutine(
        type: .input,
        isCompleted: true,
        memberInput: "  서버 입력 결과  "
      ),
      serverRoutine(
        type: .input,
        isCompleted: true,
        memberInput: "\n"
      ),
      serverRoutine(
        type: .input,
        isCompleted: false,
        memberInput: "미완료 입력"
      ),
      serverRoutine(
        type: .check,
        isCompleted: true,
        memberInput: "완료했어요"
      ),
      serverRoutine(
        type: .timer,
        isCompleted: true,
        memberInput: "타이머 결과"
      ),
    ]

    let answers = routines.compactMap {
      DailyReportInputAnswerPolicy.answer(for: $0)
    }

    XCTAssertEqual(answers, ["서버 입력 결과"])
  }

  private func localResult(
    stepType: RoutineStepType,
    completedAt: Date?,
    skipped: Bool = false,
    inputText: String? = nil,
    transcript: String? = nil
  ) -> RoutineStepResult {
    RoutineStepResult(
      stepID: UUID(),
      stepTitle: "테스트 항목",
      stepType: stepType,
      completedAt: completedAt,
      skipped: skipped,
      inputText: inputText,
      transcript: transcript
    )
  }

  private func serverRoutine(
    type: ServerHistoryDailyRoutineType,
    isCompleted: Bool,
    memberInput: String?
  ) -> ServerHistoryDailyRoutine {
    ServerHistoryDailyRoutine(
      routineID: 1,
      title: "테스트 루틴",
      type: type,
      durationSeconds: 60,
      isCompleted: isCompleted,
      memberInput: memberInput
    )
  }
}
