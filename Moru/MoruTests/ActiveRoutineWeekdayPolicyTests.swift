//
//  ActiveRoutineWeekdayPolicyTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

/// 활성 루틴 요일 불변식은 두 곳에서 쓰인다. UseCase는 저장 전에 "누구와 겹치나"를
/// 묻고, 리포지토리는 저장 트랜잭션 안에서 "겹치는 게 있나"를 묻는다.
///
/// 예전에는 두 곳이 규칙을 각자 구현해서, 한쪽만 고치면 **UI는 통과시키는데 저장이
/// throw하는** 상태가 될 수 있었다. 사용자에게는 저장 버튼이 그냥 안 먹는 것으로
/// 보인다. 이제 판단 기준이 하나이므로, 그 하나를 여기서 고정한다.
@MainActor
final class ActiveRoutineWeekdayPolicyTests: XCTestCase {
  func testOverlappingActiveRoutinesAreReportedAsConflicts() {
    let monday = makeRoutine(weekdays: [.monday, .tuesday])
    let wednesday = makeRoutine(weekdays: [.wednesday])

    let conflicts = ActiveRoutineWeekdayPolicy.conflictingRoutineIDs(
      occupying: [.tuesday],
      excluding: nil,
      among: [monday, wednesday]
    )

    XCTAssertEqual(conflicts, [monday.id])
  }

  func testEditingARoutineDoesNotConflictWithItself() {
    let routine = makeRoutine(weekdays: [.monday])

    let conflicts = ActiveRoutineWeekdayPolicy.conflictingRoutineIDs(
      occupying: [.monday],
      excluding: routine.id,
      among: [routine]
    )

    XCTAssertTrue(conflicts.isEmpty)
  }

  /// 비활성 루틴과 알람 없는 루틴은 아무 요일도 차지하지 않는다. 둘을 충돌로
  /// 치면 사용자가 꺼 둔 루틴 때문에 새 루틴을 못 켜게 된다.
  func testInactiveAndAlarmlessRoutinesOccupyNothing() {
    let inactive = makeRoutine(weekdays: [.monday], isActive: false)
    let alarmless = makeRoutine(weekdays: [], hasSchedule: false)

    let conflicts = ActiveRoutineWeekdayPolicy.conflictingRoutineIDs(
      occupying: [.monday],
      excluding: nil,
      among: [inactive, alarmless]
    )

    XCTAssertTrue(conflicts.isEmpty)
    XCTAssertNoThrow(try ActiveRoutineWeekdayPolicy.validate([inactive, alarmless]))
  }

  func testValidateRejectsTwoActiveRoutinesSharingAWeekday() {
    let first = makeRoutine(weekdays: [.monday, .friday])
    let second = makeRoutine(weekdays: [.friday])

    XCTAssertThrowsError(
      try ActiveRoutineWeekdayPolicy.validate([first, second])
    ) { error in
      XCTAssertEqual(
        error as? RepositoryContractError,
        .overlappingActiveRoutineWeekdays
      )
    }
  }

  func testValidateAcceptsDisjointActiveRoutines() {
    XCTAssertNoThrow(
      try ActiveRoutineWeekdayPolicy.validate([
        makeRoutine(weekdays: [.monday, .tuesday]),
        makeRoutine(weekdays: [.wednesday, .thursday]),
      ])
    )
  }

  /// 두 질문이 같은 답을 낸다. 하나가 "겹치는 게 없다"고 하면 다른 하나도
  /// 저장을 통과시켜야 한다. 이게 어긋나면 저장 버튼이 말없이 실패한다.
  func testBothQuestionsAgreeOnTheSameSituation() {
    let existing = makeRoutine(weekdays: [.monday, .wednesday])
    let candidateWeekdays: [Set<Weekday>] = [
      [.monday],                 // 겹침
      [.wednesday, .friday],     // 일부 겹침
      [.tuesday, .thursday],     // 겹치지 않음
      [],                        // 요일 없음
    ]

    for weekdays in candidateWeekdays {
      let incoming = makeRoutine(weekdays: Array(weekdays))
      let conflicts = ActiveRoutineWeekdayPolicy.conflictingRoutineIDs(
        occupying: weekdays,
        excluding: incoming.id,
        among: [existing]
      )
      let savedTogether = [existing, incoming]

      if conflicts.isEmpty {
        XCTAssertNoThrow(
          try ActiveRoutineWeekdayPolicy.validate(savedTogether),
          "충돌이 없다고 했으면 저장도 통과해야 한다: \(weekdays)"
        )
      } else {
        XCTAssertThrowsError(
          try ActiveRoutineWeekdayPolicy.validate(savedTogether),
          "충돌이 있다고 했으면 저장은 막혀야 한다: \(weekdays)"
        )
      }
    }
  }

  private func makeRoutine(
    weekdays: [Weekday],
    isActive: Bool = true,
    hasSchedule: Bool = true
  ) -> Routine {
    Routine(
      name: "루틴",
      steps: [],
      alarmSchedule: hasSchedule
        ? AlarmSchedule(hour: 7, minute: 0, weekdays: weekdays)
        : nil,
      isActive: isActive
    )
  }
}
