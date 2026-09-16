//
//  FigmaPilotFoundationTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import SwiftUI
import UIKit
import XCTest
@testable import Moru

@MainActor
final class FigmaPilotFoundationTests: XCTestCase {
  func testPilotColorAliasesMatchApprovedHexValues() {
    // 표면 토큰(canvas/cardSurface/tileSurface)은 여기 없다. 시스템 시맨틱
    // 색이라 값을 애플이 정하고 iOS 버전·외관에 따라 달라진다. hex로 못 박으면
    // OS가 바뀔 때 이 테스트가 먼저 깨진다. 대신 아래에서 위계만 확인한다.
    let colors: [(Color, UInt32)] = [
      (MoruColor.accent, 0xFF9861),
      (MoruColor.accentSoft, 0xFFAC80),
      (MoruColor.accentTint, 0xFFDFCE),
      (MoruColor.accentSurface, 0xFFEBE0),
      (MoruColor.progressTrack, 0xF6F8FA),
      (MoruColor.border, 0xE3E6EE),
      (MoruColor.textStrong, 0x3C3D5E),
      (MoruColor.textPrimary, 0x515574),
      (MoruColor.textSecondary, 0x80889E),
      (MoruColor.textTertiary, 0x999FB3),
      (MoruColor.shadow, 0xD8E3FF),
      (MoruColor.ctaFill, 0xFF9861),
      (MoruColor.onCTA, 0xFFFFFF),
      (MoruColor.summarySurface, 0xFFC09E),
      (MoruColor.surfaceMuted, 0xF2F4F9),
      (MoruColor.disabled, 0xB3B7C9),
      (MoruColor.link, 0x427DFF),
      (MoruColor.linkDisabled, 0xADC7FF),
    ]

    for (color, expectedHex) in colors {
      XCTAssertEqual(rgbHex(color), expectedHex)
    }
  }

  /// 표면은 hex가 아니라 **위계**로 지킨다.
  ///
  /// 바탕보다 카드가 밝아야 카드가 선다. 예전에 프로필 카드가 배경과 255 중
  /// 2밖에 차이나지 않아 사실상 보이지 않던 적이 있다. 시스템 시맨틱 색으로
  /// 옮겨 구조적으로 막았지만, 누군가 다시 커스텀 색을 넣으면 그때 깨지라고
  /// 남긴다.
  func testSurfaceHierarchyKeepsCardsAboveTheCanvas() {
    let canvas = rgbHex(MoruColor.canvas)
    let card = rgbHex(MoruColor.cardSurface)

    XCTAssertGreaterThan(
      luminance(card),
      luminance(canvas),
      "카드가 바탕보다 밝아야 표면으로 읽힌다"
    )
    XCTAssertGreaterThan(
      luminance(card) - luminance(canvas),
      8,
      "차이가 너무 작으면 카드가 보이지 않는다"
    )
  }

  private func luminance(_ hex: UInt32) -> Double {
    let r = Double((hex >> 16) & 0xFF)
    let g = Double((hex >> 8) & 0xFF)
    let b = Double(hex & 0xFF)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  func testPilotSpacingAndRadiusAliasesMatchApprovedValues() {
    XCTAssertEqual(
      [
        MoruSpacing.four,
        MoruSpacing.eight,
        MoruSpacing.ten,
        MoruSpacing.twelve,
        MoruSpacing.sixteen,
        MoruSpacing.twenty,
        MoruSpacing.thirtyTwo,
        MoruSpacing.thirtySix,
        MoruSpacing.sixtyFour,
      ],
      [4, 8, 10, 12, 16, 20, 32, 36, 64]
    )
    XCTAssertEqual(
      [
        MoruRadius.card,
        MoruRadius.largeCard,
        MoruRadius.pill,
      ],
      [16, 24, 100]
    )

    let configuration = MoruVisualCaptureConfiguration.iPhone16
    let components = configuration.calendar.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: configuration.now
    )
    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 7)
    XCTAssertEqual(components.day, 24)
    XCTAssertEqual(components.hour, 6)
    XCTAssertEqual(components.minute, 15)
  }

  func testMoruTextStylesMatchFigmaScaleAndLineHeight() {
    let styles: [(MoruTextStyle, CGFloat, CGFloat)] = [
      (.d1, 48, 67.2),
      (.d2, 36, 50.4),
      (.h1, 32, 44.8),
      (.h2, 28, 39.2),
      (.h3, 24, 33.6),
      (.b1, 22, 30.8),
      (.b2, 20, 28),
      (.b3, 18, 25.2),
      (.b4, 16, 22.4),
      (.c1, 14, 19.6),
      (.c2, 12, 16.8),
    ]

    for (style, expectedSize, expectedLineHeight) in styles {
      XCTAssertEqual(style.fontSize, expectedSize, accuracy: 0.001)
      XCTAssertEqual(style.lineHeight, expectedLineHeight, accuracy: 0.001)
      XCTAssertEqual(style.lineHeight / style.fontSize, 1.4, accuracy: 0.001)
    }
    XCTAssertEqual(MoruTextStyle.b3.weight(.semiBold).weight, .semiBold)
  }

  func testDefaultCommonComponentInitializersCompile() {
    _ = MoruProgressBar(current: 1, total: 9)
    _ = MoruToggle(isOn: .constant(true))
    _ = MoruButton("다음") {}
    _ = MoruRoutineCard(
      title: "활력 루틴",
      description: "6개 항목 ・15분",
      isActive: true
    )
    _ = MoruRoutineCard(
      title: "활력 루틴",
      description: "6개 항목 ・15분",
      isActive: .constant(true)
    )
  }

  func testPilotComponentBoardRendersDeterministicallyAtReferenceVariants() throws {
    let fallbackDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("moru-figma-pilot-d0")
    let outputDirectory = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment[
        "MORU_CAPTURE_OUTPUT_DIR"
      ] ?? fallbackDirectory.path
    )

    for variant in MoruVisualCaptureVariant.allCases {
      let first = try MoruVisualCaptureFixture.render(
        componentBoard(),
        filename: "after-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )
      let second = try MoruVisualCaptureFixture.render(
        componentBoard(),
        filename: "after-repeat-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )

      XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
      XCTAssertEqual(first.scale, 3)
      try assertVisualRepeat(first, second)
    }
  }

  private func rgbHex(_ color: Color) -> UInt32 {
    let resolved = UIColor(color).resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .light)
    )
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(
      resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    )
    XCTAssertEqual(alpha, 1, accuracy: 0.001)

    return UInt32(round(red * 255)) << 16
      | UInt32(round(green * 255)) << 8
      | UInt32(round(blue * 255))
  }

  private func componentBoard() -> some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: MoruSpacing.twenty) {
          Text("공통 기준")
            .moruTextStyle(.h3)
            .foregroundStyle(MoruColor.textStrong)
            .fixedSize(horizontal: false, vertical: true)

          MoruProgressBar(
            current: 5,
            total: 9
          )

          HStack(spacing: MoruSpacing.twenty) {
            MoruToggle(
              isOn: .constant(true)
            )
            MoruToggle(
              isOn: .constant(false)
            )
          }

          MoruRoutineCard(
            title: "활력 루틴",
            description: "6개 항목 ・15분",
            isActive: true
          )
          MoruRoutineCard(
            title: "새 루틴 추가하기",
            isAddCard: true
          )
          MoruButton(
            "루틴 시작하기"
          ) {}
        }
        .padding(.vertical, MoruSpacing.thirtySix)
        .padding(.horizontal, MoruSpacing.twenty)
      }
    }
    .background(MoruColor.canvas)
  }
}
