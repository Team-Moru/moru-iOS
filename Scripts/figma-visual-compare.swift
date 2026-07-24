#!/usr/bin/xcrun swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO

private struct Options {
  let referenceURL: URL
  let candidateURL: URL
  let outputDirectory: URL
  let maskedTopPixels: Int
  let maskedBottomPixels: Int
  let differenceGain: Int
}

private struct ComparisonMetrics: Codable {
  let width: Int
  let height: Int
  let comparedPixelCount: Int
  let maskedPixelCount: Int
  let differingPixelCount: Int
  let differingPixelPercentage: Double
  let meanAbsoluteChannelDelta: Double
  let rootMeanSquareChannelDelta: Double
  let maximumChannelDelta: Int
}

private enum ComparisonError: LocalizedError {
  case invalidArguments(String)
  case unreadableImage(URL)
  case missingCGImage(URL)
  case mismatchedDimensions(reference: CGSize, candidate: CGSize)
  case cannotCreateContext
  case cannotEncodePNG(URL)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message):
      message
    case .unreadableImage(let url):
      "Cannot read image: \(url.path)"
    case .missingCGImage(let url):
      "Cannot decode image pixels: \(url.path)"
    case .mismatchedDimensions(let reference, let candidate):
      "Image dimensions differ: reference \(reference), candidate \(candidate)"
    case .cannotCreateContext:
      "Cannot create an sRGB CoreGraphics bitmap context."
    case .cannotEncodePNG(let url):
      "Cannot encode PNG: \(url.path)"
    }
  }
}

private let usage = """
Usage:
  xcrun swift Scripts/figma-visual-compare.swift \\
    --reference <reference.png> \\
    --candidate <candidate.png> \\
    --output-dir <directory> \\
    [--mask-top-pixels <count>] \\
    [--mask-bottom-pixels <count>] \\
    [--difference-gain <1...16>]

Outputs:
  side-by-side.png
  overlay.png
  difference-heatmap.png
  metrics.json
"""

private func parseOptions(_ arguments: [String]) throws -> Options {
  let allowedKeys: Set<String> = [
    "--reference",
    "--candidate",
    "--output-dir",
    "--mask-top-pixels",
    "--mask-bottom-pixels",
    "--difference-gain",
  ]
  var values: [String: String] = [:]
  var index = 0

  while index < arguments.count {
    let key = arguments[index]
    guard allowedKeys.contains(key), index + 1 < arguments.count else {
      throw ComparisonError.invalidArguments(usage)
    }
    values[key] = arguments[index + 1]
    index += 2
  }

  guard let referencePath = values["--reference"],
        let candidatePath = values["--candidate"],
        let outputPath = values["--output-dir"] else {
    throw ComparisonError.invalidArguments(usage)
  }

  let maskedTopPixels = try integerValue(
    values["--mask-top-pixels"] ?? "0",
    name: "--mask-top-pixels",
    range: 0...Int.max
  )
  let maskedBottomPixels = try integerValue(
    values["--mask-bottom-pixels"] ?? "0",
    name: "--mask-bottom-pixels",
    range: 0...Int.max
  )
  let differenceGain = try integerValue(
    values["--difference-gain"] ?? "4",
    name: "--difference-gain",
    range: 1...16
  )

  return Options(
    referenceURL: URL(fileURLWithPath: referencePath),
    candidateURL: URL(fileURLWithPath: candidatePath),
    outputDirectory: URL(fileURLWithPath: outputPath),
    maskedTopPixels: maskedTopPixels,
    maskedBottomPixels: maskedBottomPixels,
    differenceGain: differenceGain
  )
}

private func integerValue(
  _ value: String,
  name: String,
  range: ClosedRange<Int>
) throws -> Int {
  guard let integer = Int(value), range.contains(integer) else {
    throw ComparisonError.invalidArguments(
      "\(name) must be in \(range.lowerBound)...\(range.upperBound)."
    )
  }
  return integer
}

private func loadCGImage(at url: URL) throws -> CGImage {
  guard let image = NSImage(contentsOf: url) else {
    throw ComparisonError.unreadableImage(url)
  }
  var proposedRect = CGRect(origin: .zero, size: image.size)
  guard let cgImage = image.cgImage(
    forProposedRect: &proposedRect,
    context: nil,
    hints: nil
  ) else {
    throw ComparisonError.missingCGImage(url)
  }
  return cgImage
}

private func rgbaPixels(for image: CGImage) throws -> [UInt8] {
  let width = image.width
  let height = image.height
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue

  guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
  ) else {
    throw ComparisonError.cannotCreateContext
  }
  context.interpolationQuality = .none
  context.draw(
    image,
    in: CGRect(x: 0, y: 0, width: width, height: height)
  )
  return pixels
}

private func makeCGImage(
  pixels: [UInt8],
  width: Int,
  height: Int
) throws -> CGImage {
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue
  let data = Data(pixels) as CFData

  guard let provider = CGDataProvider(data: data),
        let image = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        ) else {
    throw ComparisonError.cannotCreateContext
  }
  return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
  let representation = NSBitmapImageRep(cgImage: image)
  guard let data = representation.representation(
    using: .png,
    properties: [:]
  ) else {
    throw ComparisonError.cannotEncodePNG(url)
  }
  try data.write(to: url, options: .atomic)
}

private func compare(
  reference: [UInt8],
  candidate: [UInt8],
  width: Int,
  height: Int,
  options: Options
) -> (sideBySide: [UInt8], overlay: [UInt8], difference: [UInt8], metrics: ComparisonMetrics) {
  let pixelCount = width * height
  var sideBySide = [UInt8](repeating: 0, count: width * 2 * height * 4)
  var overlay = [UInt8](repeating: 0, count: pixelCount * 4)
  var difference = [UInt8](repeating: 0, count: pixelCount * 4)
  var differingPixelCount = 0
  var absoluteDeltaTotal: UInt64 = 0
  var squaredDeltaTotal: UInt64 = 0
  var maximumChannelDelta = 0
  var comparedPixelCount = 0

  for row in 0..<height {
    let isMasked = row < options.maskedTopPixels
      || row >= height - options.maskedBottomPixels

    for column in 0..<width {
      let pixelIndex = row * width + column
      let sourceOffset = pixelIndex * 4
      let sideReferenceOffset = (row * width * 2 + column) * 4
      let sideCandidateOffset = (row * width * 2 + width + column) * 4

      for channel in 0..<4 {
        sideBySide[sideReferenceOffset + channel] = reference[sourceOffset + channel]
        sideBySide[sideCandidateOffset + channel] = candidate[sourceOffset + channel]
      }

      for channel in 0..<3 {
        let referenceValue = Int(reference[sourceOffset + channel])
        let candidateValue = Int(candidate[sourceOffset + channel])
        overlay[sourceOffset + channel] = UInt8(
          (referenceValue + candidateValue) / 2
        )
      }
      overlay[sourceOffset + 3] = 255
      difference[sourceOffset + 3] = 255

      guard !isMasked else {
        continue
      }

      comparedPixelCount += 1
      var pixelMaximumDelta = 0
      for channel in 0..<3 {
        let delta = abs(
          Int(reference[sourceOffset + channel])
            - Int(candidate[sourceOffset + channel])
        )
        absoluteDeltaTotal += UInt64(delta)
        squaredDeltaTotal += UInt64(delta * delta)
        maximumChannelDelta = max(maximumChannelDelta, delta)
        pixelMaximumDelta = max(pixelMaximumDelta, delta)
      }
      if pixelMaximumDelta > 0 {
        differingPixelCount += 1
      }

      let heat = min(255, pixelMaximumDelta * options.differenceGain)
      difference[sourceOffset] = UInt8(heat)
      difference[sourceOffset + 1] = UInt8(heat * heat / 255)
      difference[sourceOffset + 2] = 0
    }
  }

  let comparedChannelCount = max(1, comparedPixelCount * 3)
  let meanAbsoluteDelta = Double(absoluteDeltaTotal)
    / Double(comparedChannelCount)
  let rootMeanSquareDelta = sqrt(
    Double(squaredDeltaTotal) / Double(comparedChannelCount)
  )
  let maskedPixelCount = pixelCount - comparedPixelCount
  let differingPercentage = comparedPixelCount == 0
    ? 0
    : Double(differingPixelCount) / Double(comparedPixelCount) * 100

  let metrics = ComparisonMetrics(
    width: width,
    height: height,
    comparedPixelCount: comparedPixelCount,
    maskedPixelCount: maskedPixelCount,
    differingPixelCount: differingPixelCount,
    differingPixelPercentage: differingPercentage,
    meanAbsoluteChannelDelta: meanAbsoluteDelta,
    rootMeanSquareChannelDelta: rootMeanSquareDelta,
    maximumChannelDelta: maximumChannelDelta
  )
  return (sideBySide, overlay, difference, metrics)
}

do {
  let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
  let referenceImage = try loadCGImage(at: options.referenceURL)
  let candidateImage = try loadCGImage(at: options.candidateURL)
  let referenceSize = CGSize(
    width: referenceImage.width,
    height: referenceImage.height
  )
  let candidateSize = CGSize(
    width: candidateImage.width,
    height: candidateImage.height
  )
  guard referenceSize == candidateSize else {
    throw ComparisonError.mismatchedDimensions(
      reference: referenceSize,
      candidate: candidateSize
    )
  }
  guard options.maskedTopPixels + options.maskedBottomPixels
    <= referenceImage.height else {
    throw ComparisonError.invalidArguments(
      "The combined masks exceed the image height."
    )
  }

  let referencePixels = try rgbaPixels(for: referenceImage)
  let candidatePixels = try rgbaPixels(for: candidateImage)
  let result = compare(
    reference: referencePixels,
    candidate: candidatePixels,
    width: referenceImage.width,
    height: referenceImage.height,
    options: options
  )

  try FileManager.default.createDirectory(
    at: options.outputDirectory,
    withIntermediateDirectories: true
  )
  try writePNG(
    makeCGImage(
      pixels: result.sideBySide,
      width: referenceImage.width * 2,
      height: referenceImage.height
    ),
    to: options.outputDirectory.appendingPathComponent("side-by-side.png")
  )
  try writePNG(
    makeCGImage(
      pixels: result.overlay,
      width: referenceImage.width,
      height: referenceImage.height
    ),
    to: options.outputDirectory.appendingPathComponent("overlay.png")
  )
  try writePNG(
    makeCGImage(
      pixels: result.difference,
      width: referenceImage.width,
      height: referenceImage.height
    ),
    to: options.outputDirectory.appendingPathComponent(
      "difference-heatmap.png"
    )
  )

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  let metricsData = try encoder.encode(result.metrics)
  try metricsData.write(
    to: options.outputDirectory.appendingPathComponent("metrics.json"),
    options: .atomic
  )
  print(options.outputDirectory.path)
} catch {
  FileHandle.standardError.write(
    Data("error: \(error.localizedDescription)\n".utf8)
  )
  exit(1)
}
