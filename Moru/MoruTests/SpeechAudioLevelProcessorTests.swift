//
//  SpeechAudioLevelProcessorTests.swift
//  MoruTests
//

import XCTest
@testable import Moru

@MainActor
final class SpeechAudioLevelProcessorTests: XCTestCase {
  func testRootMeanSquareUsesSampleMagnitude() {
    let rms = SpeechAudioLevelProcessor.rootMeanSquare(for: [0.5, -0.5])

    XCTAssertEqual(rms, 0.5, accuracy: 0.0001)
  }

  func testNormalizedLevelClampsSilenceAndLoudAudio() {
    let silence = SpeechAudioLevelProcessor.normalizedLevel(for: [0])
    let ceiling = SpeechAudioLevelProcessor.normalizedLevel(for: [0.316_227_76])
    let louderThanCeiling = SpeechAudioLevelProcessor.normalizedLevel(for: [1])

    XCTAssertEqual(silence, 0, accuracy: 0.0001)
    XCTAssertEqual(ceiling, 1, accuracy: 0.0001)
    XCTAssertEqual(louderThanCeiling, 1, accuracy: 0.0001)
  }

  func testProcessorKeepsTwentySmoothedWaveformValues() {
    var processor = SpeechAudioLevelProcessor()

    let smoothedLevel = processor.append(normalizedLevel: 1)

    XCTAssertEqual(smoothedLevel, 0.25, accuracy: 0.0001)
    XCTAssertEqual(processor.levels.count, 20)
    XCTAssertEqual(
      processor.levels.last ?? .zero,
      CGFloat(0.25),
      accuracy: CGFloat(0.0001)
    )
    XCTAssertTrue(processor.levels.dropLast().allSatisfy { $0 == 0 })
  }
}
