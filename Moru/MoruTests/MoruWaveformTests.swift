//
//  MoruWaveformTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class MoruWaveformTests: XCTestCase {
  func testUsesLiveLevelsWhenReduceMotionIsEnabled() {
    let levels = (0..<20).map { CGFloat($0) / 19 }
    let waveform = MoruWaveform(levels: levels, usesReducedMotion: true)

    XCTAssertEqual(waveform.displayedLevels.count, 20)
    XCTAssertEqual(waveform.displayedLevels.first, 0)
    XCTAssertEqual(waveform.displayedLevels.last, 1)
    XCTAssertGreaterThan(waveform.displayedLevels[12], waveform.displayedLevels[5])
  }

  func testInvalidLevelCountRendersTwentyQuietBars() {
    let waveform = MoruWaveform(levels: [0.2, 0.8])

    XCTAssertEqual(waveform.displayedLevels.count, 20)
    XCTAssertTrue(waveform.displayedLevels.allSatisfy { $0 == 0 })
  }

  func testAmplifiesPerBarDifferenceForLegibility() {
    let levels = (0..<20).map { $0.isMultiple(of: 2) ? CGFloat(0.4) : CGFloat(0.6) }
    let waveform = MoruWaveform(levels: levels)
    let renderedDifference = waveform.displayedLevels[1] - waveform.displayedLevels[0]

    XCTAssertGreaterThan(renderedDifference, 0.2)
  }
}
