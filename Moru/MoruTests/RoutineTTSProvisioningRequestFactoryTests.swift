//
//  RoutineTTSProvisioningRequestFactoryTests.swift
//  MoruTests
//

import XCTest

@testable import Moru

@MainActor
final class RoutineTTSProvisioningRequestFactoryTests: XCTestCase {
  func testMapsLocalRoutineInStepOrderWithoutCopyingLocalAlarm() throws {
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()
    let routine = Routine(
      name: "  아침 준비  ",
      summary: "  차분히 시작해요  ",
      steps: [
        RoutineStep(
          id: thirdID,
          type: .input,
          title: "  오늘 할 일 말하기  ",
          order: 2,
          estimatedSeconds: 90
        ),
        RoutineStep(
          id: firstID,
          type: .confirm,
          title: "  물 마시기  ",
          order: 0,
          estimatedSeconds: 30
        ),
        RoutineStep(
          id: secondID,
          type: .timer,
          title: "  스트레칭  ",
          order: 1,
          estimatedSeconds: 60
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 5,
        weekdays: [.monday, .friday],
        includeWeather: true
      )
    )

    let plan = try RoutineTTSProvisioningRequestFactory.makePlan(
      for: routine
    )

    XCTAssertEqual(plan.request.localRoutineID, routine.id)
    XCTAssertEqual(plan.request.title, "아침 준비")
    XCTAssertEqual(plan.request.description, "차분히 시작해요")
    XCTAssertNil(plan.request.alarmDaysRaw)
    XCTAssertNil(plan.request.alarmTimeRaw)
    XCTAssertFalse(plan.request.weatherNotificationEnabled)
    XCTAssertEqual(
      plan.request.routines.map(\.localStepID),
      [firstID, secondID, thirdID]
    )
    XCTAssertEqual(
      plan.request.routines.map(\.type),
      [.check, .timer, .input]
    )
    XCTAssertEqual(
      plan.request.routines.map(\.durationSeconds),
      [30, 60, 90]
    )
    XCTAssertEqual(plan.contentFingerprint.count, 64)
  }

  func testFingerprintTracksTTSContentButIgnoresLocalAlarm() throws {
    let stepID = UUID()
    let routineID = UUID()
    let base = makeRoutine(
      id: routineID,
      stepID: stepID,
      title: "물 마시기",
      durationSeconds: 30,
      alarmHour: 7
    )
    let alarmChanged = makeRoutine(
      id: routineID,
      stepID: stepID,
      title: "물 마시기",
      durationSeconds: 30,
      alarmHour: 9
    )
    let contentChanged = makeRoutine(
      id: routineID,
      stepID: stepID,
      title: "차 마시기",
      durationSeconds: 45,
      alarmHour: 7
    )

    let baseFingerprint = try RoutineTTSProvisioningRequestFactory
      .makePlan(for: base).contentFingerprint
    let alarmFingerprint = try RoutineTTSProvisioningRequestFactory
      .makePlan(for: alarmChanged).contentFingerprint
    let changedFingerprint = try RoutineTTSProvisioningRequestFactory
      .makePlan(for: contentChanged).contentFingerprint

    XCTAssertEqual(baseFingerprint, alarmFingerprint)
    XCTAssertNotEqual(baseFingerprint, changedFingerprint)
  }

  func testRejectsInvalidLocalContentBeforeAnyServerRequest() {
    assertError(.emptyRoutineTitle) {
      try RoutineTTSProvisioningRequestFactory.makePlan(
        for: Routine(name: " ", steps: [validStep()])
      )
    }
    assertError(.emptySteps) {
      try RoutineTTSProvisioningRequestFactory.makePlan(
        for: Routine(name: "루틴", steps: [])
      )
    }

    let duplicateID = UUID()
    assertError(.duplicateStepID(duplicateID)) {
      try RoutineTTSProvisioningRequestFactory.makePlan(
        for: Routine(
          name: "루틴",
          steps: [
            validStep(id: duplicateID, order: 0),
            validStep(id: duplicateID, order: 1),
          ]
        )
      )
    }
    assertError(.duplicateStepOrder(0)) {
      try RoutineTTSProvisioningRequestFactory.makePlan(
        for: Routine(
          name: "루틴",
          steps: [
            validStep(order: 0),
            validStep(order: 0),
          ]
        )
      )
    }

    let emptyTitleID = UUID()
    assertError(.emptyStepTitle(emptyTitleID)) {
      try RoutineTTSProvisioningRequestFactory.makePlan(
        for: Routine(
          name: "루틴",
          steps: [
            RoutineStep(
              id: emptyTitleID,
              type: .confirm,
              title: " ",
              order: 0,
              estimatedSeconds: 30
            ),
          ]
        )
      )
    }

    let missingDurationID = UUID()
    assertError(
      .invalidDuration(stepID: missingDurationID, seconds: nil)
    ) {
      try RoutineTTSProvisioningRequestFactory.makePlan(
        for: Routine(
          name: "루틴",
          steps: [
            RoutineStep(
              id: missingDurationID,
              type: .confirm,
              title: "물 마시기",
              order: 0,
              estimatedSeconds: nil
            ),
          ]
        )
      )
    }
  }

  private func makeRoutine(
    id: UUID,
    stepID: UUID,
    title: String,
    durationSeconds: Int,
    alarmHour: Int
  ) -> Routine {
    Routine(
      id: id,
      name: "아침",
      steps: [
        validStep(
          id: stepID,
          title: title,
          estimatedSeconds: durationSeconds
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: alarmHour,
        minute: 0,
        weekdays: [.monday]
      )
    )
  }

  private func validStep(
    id: UUID = UUID(),
    title: String = "물 마시기",
    order: Int = 0,
    estimatedSeconds: Int? = 30
  ) -> RoutineStep {
    RoutineStep(
      id: id,
      type: .confirm,
      title: title,
      order: order,
      estimatedSeconds: estimatedSeconds
    )
  }

  private func assertError(
    _ expected: RoutineTTSProvisioningRequestError,
    operation: () throws -> RoutineTTSProvisioningPlan
  ) {
    do {
      _ = try operation()
      XCTFail("Expected \(expected).")
    } catch let error as RoutineTTSProvisioningRequestError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected request error, got \(error)")
    }
  }
}
