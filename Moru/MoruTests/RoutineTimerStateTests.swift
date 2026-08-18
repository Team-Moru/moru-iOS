//
//  RoutineTimerStateTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class RoutineTimerStateTests: XCTestCase {
  func testLastFiveSecondsAreAnnouncedInOrderBeforeCompletion() {
    var state = RoutineTimerState(totalSeconds: 6)
    var actions = state.start()

    for _ in 0..<6 {
      actions.append(contentsOf: state.tick())
    }

    XCTAssertEqual(
      actions,
      [
        .announce(5),
        .announce(4),
        .announce(3),
        .announce(2),
        .announce(1),
        .complete,
      ]
    )
  }

  func testFiveSecondTimerAnnouncesFiveWhenItStarts() {
    var state = RoutineTimerState(totalSeconds: 5)

    XCTAssertEqual(state.start(), [.announce(5)])
  }

  func testOneSecondTimerAnnouncesThenCompletesExactlyOnce() {
    var state = RoutineTimerState(totalSeconds: 1)

    XCTAssertEqual(state.start(), [.announce(1)])
    XCTAssertEqual(state.tick(), [.complete])
    XCTAssertTrue(state.tick().isEmpty)
  }
}
