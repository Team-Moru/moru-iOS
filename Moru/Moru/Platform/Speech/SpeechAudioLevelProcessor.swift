//
//  SpeechAudioLevelProcessor.swift
//  Moru
//

import Foundation

struct SpeechAudioLevelProcessor {
  private enum Metric {
    static let attackWeight: Float = 0.45
    static let releaseWeight: Float = 0.35
    static let waveformSampleCount = 20
    nonisolated static let silenceFloor: Float = -45
    nonisolated static let ceiling: Float = -3
    nonisolated static let responseExponent: Float = 0.85
    nonisolated static let visualNoiseGate: Float = 0.3
    nonisolated static let visualResponseExponent: Float = 0.75
  }

  private(set) var smoothedLevel: Float = 0
  private(set) var levels = Array(repeating: CGFloat.zero, count: Metric.waveformSampleCount)

  mutating func append(samples: [Float]) -> Float {
    append(normalizedLevel: Self.normalizedLevel(for: samples))
  }

  mutating func append(normalizedLevel: Float) -> Float {
    let visualLevel = Self.visualLevel(from: normalizedLevel)
    let weight = visualLevel > smoothedLevel
      ? Metric.attackWeight
      : Metric.releaseWeight
    smoothedLevel += (visualLevel - smoothedLevel) * weight
    levels.removeFirst()
    levels.append(CGFloat(smoothedLevel))
    return smoothedLevel
  }

  mutating func append(normalizedLevels: [Float]) -> Float {
    guard normalizedLevels.count == Metric.waveformSampleCount else {
      return append(normalizedLevel: normalizedLevels.max() ?? .zero)
    }

    let visualLevels = normalizedLevels.map(Self.visualLevel(from:))
    let frameLevel = visualLevels.reduce(Float.zero, +) / Float(visualLevels.count)
    let frameWeight = frameLevel > smoothedLevel
      ? Metric.attackWeight
      : Metric.releaseWeight
    smoothedLevel += (frameLevel - smoothedLevel) * frameWeight

    for index in levels.indices {
      let targetLevel = visualLevels[index]
      let previousLevel = Float(levels[index])
      let weight = targetLevel > previousLevel
        ? Metric.attackWeight
        : Metric.releaseWeight
      levels[index] = CGFloat(previousLevel + (targetLevel - previousLevel) * weight)
    }

    return smoothedLevel
  }

  mutating func reset() {
    smoothedLevel = 0
    levels = Array(repeating: .zero, count: Metric.waveformSampleCount)
  }

  nonisolated static func rootMeanSquare(for samples: [Float]) -> Float {
    samples.withUnsafeBufferPointer { rootMeanSquare(for: $0) }
  }

  nonisolated static func normalizedLevel(for samples: [Float]) -> Float {
    samples.withUnsafeBufferPointer { normalizedLevel(for: $0) }
  }

  nonisolated static func rootMeanSquare(for samples: UnsafeBufferPointer<Float>) -> Float {
    guard !samples.isEmpty else {
      return 0
    }

    let squaredSum = samples.reduce(Float.zero) { partialResult, sample in
      partialResult + sample * sample
    }
    return sqrt(squaredSum / Float(samples.count))
  }

  nonisolated static func normalizedLevel(for samples: UnsafeBufferPointer<Float>) -> Float {
    let rms = rootMeanSquare(for: samples)
    let decibels = 20 * log10(max(rms, 0.0000001))
    let range = Metric.ceiling - Metric.silenceFloor
    let linearLevel = min(max((decibels - Metric.silenceFloor) / range, 0), 1)
    return pow(linearLevel, Metric.responseExponent)
  }

  nonisolated private static func visualLevel(from normalizedLevel: Float) -> Float {
    let clampedLevel = min(max(normalizedLevel, 0), 1)
    let gatedLevel = max(clampedLevel - Metric.visualNoiseGate, 0)
      / (1 - Metric.visualNoiseGate)
    return pow(gatedLevel, Metric.visualResponseExponent)
  }
}
