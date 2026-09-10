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

  func testEarlyCompletionCompletesOnceAndSilencesLaterTicks() {
    var state = RoutineTimerState(totalSeconds: 180)
    _ = state.start()
    _ = state.tick()
    _ = state.tick()

    XCTAssertEqual(state.completeEarly(), [.complete])
    XCTAssertTrue(state.didComplete)
    XCTAssertTrue(state.tick().isEmpty)
    XCTAssertTrue(state.completeEarly().isEmpty)
    XCTAssertEqual(state.remainingSeconds, 178)
  }

  func testEarlyCompletionAfterNaturalCompletionIsIgnored() {
    var state = RoutineTimerState(totalSeconds: 1)
    _ = state.start()

    XCTAssertEqual(state.tick(), [.complete])
    XCTAssertTrue(state.completeEarly().isEmpty)
  }
}
