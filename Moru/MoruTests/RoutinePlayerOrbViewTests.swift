//
//  RoutinePlayerOrbViewTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class RoutinePlayerOrbViewTests: XCTestCase {
  func testOrbReturnsToItsRestingStateWithoutSpeech() {
    let silentOrb = RoutinePlayerOrbView(
      levels: Array(repeating: .zero, count: 20),
      isListening: true
    )
    let pausedOrb = RoutinePlayerOrbView(
      levels: Array(repeating: 1, count: 20),
      isListening: true,
      isPaused: true
    )

    XCTAssertEqual(silentOrb.visualIntensity, 0)
    XCTAssertEqual(pausedOrb.visualIntensity, 0)
  }

  func testOrbRespondsStronglyToSpeechLevels() {
    let orb = RoutinePlayerOrbView(
      levels: Array(repeating: 0.7, count: 20),
      isListening: true
    )

    XCTAssertGreaterThan(orb.visualIntensity, 0.8)
  }
}
