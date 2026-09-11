//
//  AlarmScheduleNextFireDateTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

/// 홈 대표 카드가 "다음 알람"을 계산하는 근거. 기준 시각은 2026-07-15(수) Asia/Seoul이다.
@MainActor
final class AlarmScheduleNextFireDateTests: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }()

  func testTodayAlarmThatHasNotPassedYetFiresToday() throws {
    let schedule = makeSchedule(hour: 7, minute: 0, weekdays: Weekday.weekdays)

    let next = schedule.nextFireDate(
      after: try date(day: 15, hour: 6, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 15, hour: 7, minute: 0))
  }

  func testTodayAlarmThatAlreadyPassedFiresOnTheNextScheduledWeekday() throws {
    let schedule = makeSchedule(hour: 7, minute: 0, weekdays: Weekday.weekdays)

    let next = schedule.nextFireDate(
      after: try date(day: 15, hour: 8, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 16, hour: 7, minute: 0))
  }

  func testExactFireTimeCountsAsPassedSoTheFollowingDayIsReturned() throws {
    let schedule = makeSchedule(hour: 7, minute: 0, weekdays: Weekday.weekdays)

    let next = schedule.nextFireDate(
      after: try date(day: 15, hour: 7, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 16, hour: 7, minute: 0))
  }

  func testWeekdayAlarmAfterFridayFiresOnTheFollowingMonday() throws {
    let schedule = makeSchedule(hour: 7, minute: 0, weekdays: Weekday.weekdays)

    // 2026-07-17은 금요일, 2026-07-20이 다음 월요일이다.
    let next = schedule.nextFireDate(
      after: try date(day: 17, hour: 8, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 20, hour: 7, minute: 0))
  }

  func testWeekendOnlyAlarmSkipsWeekdays() throws {
    let schedule = makeSchedule(hour: 9, minute: 30, weekdays: [.saturday, .sunday])

    // 2026-07-18이 토요일이다.
    let next = schedule.nextFireDate(
      after: try date(day: 15, hour: 10, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 18, hour: 9, minute: 30))
  }

  func testMidnightAlarmFiresAtTheStartOfTheNextScheduledDay() throws {
    let schedule = makeSchedule(hour: 0, minute: 0, weekdays: [.thursday])

    let next = schedule.nextFireDate(
      after: try date(day: 15, hour: 23, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 16, hour: 0, minute: 0))
  }

  func testEarliestWeekdayWinsWhenSeveralAreScheduled() throws {
    let schedule = makeSchedule(
      hour: 7,
      minute: 0,
      weekdays: [.sunday, .thursday, .monday]
    )

    // 수요일 기준이면 목요일이 가장 빠르다.
    let next = schedule.nextFireDate(
      after: try date(day: 15, hour: 8, minute: 0),
      calendar: calendar
    )

    XCTAssertEqual(next, try date(day: 16, hour: 7, minute: 0))
  }

  func testDisabledScheduleHasNoNextFireDate() throws {
    let schedule = makeSchedule(
      hour: 7,
      minute: 0,
      weekdays: Weekday.weekdays,
      isEnabled: false
    )

    XCTAssertNil(
      schedule.nextFireDate(
        after: try date(day: 15, hour: 6, minute: 0),
        calendar: calendar
      )
    )
  }

  func testScheduleWithoutWeekdaysHasNoNextFireDate() throws {
    let schedule = makeSchedule(hour: 7, minute: 0, weekdays: [])

    XCTAssertNil(
      schedule.nextFireDate(
        after: try date(day: 15, hour: 6, minute: 0),
        calendar: calendar
      )
    )
  }

  // MARK: - Helpers

  private func makeSchedule(
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    isEnabled: Bool = true
  ) -> AlarmSchedule {
    AlarmSchedule(
      id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      isEnabled: isEnabled
    )
  }

  private func date(day: Int, hour: Int, minute: Int) throws -> Date {
    try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          calendar: calendar,
          timeZone: calendar.timeZone,
          year: 2026,
          month: 7,
          day: day,
          hour: hour,
          minute: minute
        )
      )
    )
  }
}
