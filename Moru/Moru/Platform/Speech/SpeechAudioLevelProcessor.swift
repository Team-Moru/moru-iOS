//
//  SpeechAudioLevelProcessor.swift
//  Moru
//

import Foundation

struct SpeechAudioLevelProcessor {
  private enum Metric {
    static let smoothingPreviousWeight: Float = 0.75
    static let smoothingCurrentWeight: Float = 0.25
    static let waveformSampleCount = 20
  }

  private(set) var smoothedLevel: Float = 0
  private(set) var levels = Array(repeating: CGFloat.zero, count: Metric.waveformSampleCount)

  mutating func append(samples: [Float]) -> Float {
    append(normalizedLevel: Self.normalizedLevel(for: samples))
  }

  mutating func append(normalizedLevel: Float) -> Float {
    let clampedLevel = min(max(normalizedLevel, 0), 1)
    smoothedLevel = smoothedLevel * Metric.smoothingPreviousWeight
      + clampedLevel * Metric.smoothingCurrentWeight
    levels.removeFirst()
    levels.append(CGFloat(smoothedLevel))
    return smoothedLevel
  }

  mutating func reset() {
    smoothedLevel = 0
    levels = Array(repeating: .zero, count: Metric.waveformSampleCount)
  }

  nonisolated static func rootMeanSquare(for samples: [Float]) -> Float {
    guard !samples.isEmpty else {
      return 0
    }

    let squaredSum = samples.reduce(Float.zero) { partialResult, sample in
      partialResult + sample * sample
    }
    return sqrt(squaredSum / Float(samples.count))
  }

  nonisolated static func normalizedLevel(for samples: [Float]) -> Float {
    let rms = rootMeanSquare(for: samples)
    let decibels = 20 * log10(max(rms, 0.0000001))
    let silenceFloor: Float = -55
    let ceiling: Float = -10
    let range = ceiling - silenceFloor
    return min(max((decibels - silenceFloor) / range, 0), 1)
  }
}
