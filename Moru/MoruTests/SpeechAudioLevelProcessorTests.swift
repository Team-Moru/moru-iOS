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

  func testNormalizedLevelKeepsConversationalVolumesDistinct() {
    let silence = SpeechAudioLevelProcessor.normalizedLevel(for: [0])
    let quietSpeech = SpeechAudioLevelProcessor.normalizedLevel(for: [0.01])
    let normalSpeech = SpeechAudioLevelProcessor.normalizedLevel(for: [0.1])
    let loudSpeech = SpeechAudioLevelProcessor.normalizedLevel(for: [0.316_227_76])
    let maximum = SpeechAudioLevelProcessor.normalizedLevel(for: [0.707_945_76])

    XCTAssertEqual(silence, 0, accuracy: 0.0001)
    XCTAssertGreaterThan(quietSpeech, silence)
    XCTAssertGreaterThan(normalSpeech, quietSpeech)
    XCTAssertGreaterThan(loudSpeech, normalSpeech)
    XCTAssertLessThan(loudSpeech, 1)
    XCTAssertEqual(maximum, 1, accuracy: 0.0001)
  }

  func testProcessorKeepsTwentySmoothedWaveformValues() {
    var processor = SpeechAudioLevelProcessor()

    let smoothedLevel = processor.append(normalizedLevel: 1)

    XCTAssertEqual(smoothedLevel, 0.45, accuracy: 0.0001)
    XCTAssertEqual(processor.levels.count, 20)
    XCTAssertEqual(
      processor.levels.last ?? .zero,
      CGFloat(0.45),
      accuracy: CGFloat(0.0001)
    )
    XCTAssertTrue(processor.levels.dropLast().allSatisfy { $0 == 0 })
  }

  func testProcessorRespondsFasterToSpeechThanSilence() {
    var processor = SpeechAudioLevelProcessor()

    let attackLevel = processor.append(normalizedLevel: 1)
    let releaseLevel = processor.append(normalizedLevel: 0)

    XCTAssertGreaterThan(attackLevel, 0.4)
    XCTAssertLessThan(releaseLevel, attackLevel)
    XCTAssertGreaterThan(releaseLevel, 0.25)
  }

  func testProcessorPreservesPerBarLevelsFromAudioFrame() {
    var processor = SpeechAudioLevelProcessor()
    let frameLevels = (0..<20).map { Float($0) / 19 }

    let smoothedLevel = processor.append(normalizedLevels: frameLevels)

    XCTAssertEqual(processor.levels.count, 20)
    XCTAssertLessThan(processor.levels.first ?? 1, 0.01)
    XCTAssertGreaterThan(processor.levels.last ?? 0, 0.4)
    XCTAssertLessThan(processor.levels[5], processor.levels[15])
    XCTAssertGreaterThan(smoothedLevel, 0.15)
  }

  func testProcessorGatesAmbientNoiseAndReturnsToRest() {
    var processor = SpeechAudioLevelProcessor()
    let ambientLevels = Array(repeating: Float(0.25), count: 20)
    let voiceLevels = Array(repeating: Float(0.7), count: 20)

    _ = processor.append(normalizedLevels: ambientLevels)
    XCTAssertTrue(processor.levels.allSatisfy { $0 == 0 })

    _ = processor.append(normalizedLevels: voiceLevels)
    XCTAssertGreaterThan(processor.levels[0], 0.2)

    for _ in 0..<8 {
      _ = processor.append(normalizedLevels: ambientLevels)
    }

    XCTAssertLessThan(processor.levels[0], 0.02)
  }
}
