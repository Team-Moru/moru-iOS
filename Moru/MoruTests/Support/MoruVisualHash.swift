//
//  MoruVisualHash.swift
//  MoruTests
//

import Foundation
import UIKit
import XCTest

/// 17×32 휘도 dHash. 세 테스트 파일에 복제돼 있던 구현을 하나로 모은다.
enum MoruVisualHash {
  /// 승인 기준선과의 허용 Hamming 거리
  static let regressionThreshold = 24
  /// 같은 입력을 두 번 그렸을 때의 허용 거리. Liquid Glass·머티리얼은 프레임마다 미세하게
  /// 달라 바이트 동일성은 보장되지 않는다(스파이크에서 0~4, 네이티브 TabView가 배경에
  /// 함께 있는 화면은 2026-09-11에 7까지 관측됐다).
  ///
  /// 2026-09-14에 유리를 컨트롤 계층 전반으로 넓히면서 8을 넘기기 시작했다. 대기 시간을
  /// 0.6→1.2초로 늘려도 그대로라 안정화 문제가 아니다. 유리를 새로 넣지 않은 완료 화면도
  /// 바탕색을 밝은 중립으로 옮긴 것만으로 넘쳤다 — 유리가 밝고 채도 낮은 배경을 샘플링할 때
  /// 디더링이 커진다.
  ///
  /// 임계값을 0으로 두고 전체 시각 스위트를 3회 돌려 잡음을 실측했다. 0이 아닌 비교
  /// 84건 중 절반이 1이고, 꼬리는 8·9·10에 9건, 관측 최대는 11이었다. 실제 디자인 변경은
  /// 같은 회차에서 28~136으로 나와 잡음과 겹치지 않는다. 관측 최대에 여유를 둔 값이다.
  static let repeatThreshold = 14

  static func hash(of image: UIImage) throws -> Data {
    let width = 17
    let height = 32
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    let cgImage = try XCTUnwrap(image.cgImage)
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var luminance = [Int]()
    luminance.reserveCapacity(width * height)
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let red = 299 * Int(pixels[offset])
      let green = 587 * Int(pixels[offset + 1])
      let blue = 114 * Int(pixels[offset + 2])
      luminance.append((red + green + blue) / 1_000)
    }

    var hash = Data(capacity: (width - 1) * height / 8)
    var byte: UInt8 = 0
    var bitIndex = 0
    for row in 0..<height {
      for column in 0..<(width - 1) {
        if luminance[row * width + column] > luminance[row * width + column + 1] {
          byte |= 1 << (7 - bitIndex)
        }
        bitIndex += 1
        if bitIndex == 8 {
          hash.append(byte)
          byte = 0
          bitIndex = 0
        }
      }
    }
    return hash
  }

  static func distance(_ lhs: Data, _ rhs: Data) -> Int {
    zip(lhs, rhs).reduce(0) { result, pair in
      result + Int((pair.0 ^ pair.1).nonzeroBitCount)
    }
  }
}

extension XCTestCase {
  /// 같은 입력을 두 번 그린 결과가 지각적으로 같은지 검사한다.
  @MainActor
  func assertVisualRepeat(
    _ first: UIImage,
    _ second: UIImage,
    _ name: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let distance = MoruVisualHash.distance(
      try MoruVisualHash.hash(of: first),
      try MoruVisualHash.hash(of: second)
    )
    XCTAssertLessThanOrEqual(
      distance,
      MoruVisualHash.repeatThreshold,
      "Nondeterministic render \(name), repeat hash distance: \(distance)",
      file: file,
      line: line
    )
  }

  /// 승인 기준선(base64 dHash)과 비교한다. 실패·누락 시 실제 해시를 메시지에 싣고,
  /// 재승인용으로 `<outputDirectory>/<name>.dhash`에도 적는다.
  @MainActor
  func assertVisualBaseline(
    _ image: UIImage,
    name: String,
    expected: String?,
    outputDirectory: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let actualHash = try MoruVisualHash.hash(of: image)
    let encodedActual = actualHash.base64EncodedString()
    try? FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    try? encodedActual.write(
      to: outputDirectory.appendingPathComponent("\(name).dhash"),
      atomically: true,
      encoding: .utf8
    )

    guard let expected, let expectedHash = Data(base64Encoded: expected) else {
      XCTFail(
        "Missing or invalid visual baseline: \(name), actual hash: \(encodedActual)",
        file: file,
        line: line
      )
      return
    }

    XCTAssertEqual(actualHash.count, expectedHash.count, file: file, line: line)
    let distance = MoruVisualHash.distance(actualHash, expectedHash)
    XCTAssertLessThanOrEqual(
      distance,
      MoruVisualHash.regressionThreshold,
      "Visual regression in \(name), hash distance: \(distance), "
        + "actual hash: \(encodedActual)",
      file: file,
      line: line
    )
  }
}
