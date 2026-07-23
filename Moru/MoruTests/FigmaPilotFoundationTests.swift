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
    let colors: [(Color, UInt32)] = [
      (MoruPilotColor.canvas, 0xF3F6FC),
      (MoruPilotColor.accent, 0xFF9861),
      (MoruPilotColor.accentSoft, 0xFFAC80),
      (MoruPilotColor.accentTint, 0xFFDFCE),
      (MoruPilotColor.accentSurface, 0xFFEBE0),
      (MoruPilotColor.progressTrack, 0xF6F8FA),
      (MoruPilotColor.border, 0xE3E6EE),
      (MoruPilotColor.textStrong, 0x3C3D5E),
      (MoruPilotColor.textPrimary, 0x515574),
      (MoruPilotColor.textSecondary, 0x80889E),
      (MoruPilotColor.textTertiary, 0x999FB3),
      (MoruPilotColor.shadow, 0xD8E3FF),
    ]

    for (color, expectedHex) in colors {
      XCTAssertEqual(rgbHex(color), expectedHex)
    }
  }

  func testPilotSpacingAndRadiusAliasesMatchApprovedValues() {
    XCTAssertEqual(
      [
        MoruPilotSpacing.four,
        MoruPilotSpacing.eight,
        MoruPilotSpacing.ten,
        MoruPilotSpacing.twelve,
        MoruPilotSpacing.sixteen,
        MoruPilotSpacing.twenty,
        MoruPilotSpacing.thirtyTwo,
        MoruPilotSpacing.thirtySix,
        MoruPilotSpacing.sixtyFour,
      ],
      [4, 8, 10, 12, 16, 20, 32, 36, 64]
    )
    XCTAssertEqual(
      [
        MoruPilotRadius.card,
        MoruPilotRadius.largeCard,
        MoruPilotRadius.pill,
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

  func testLegacyCommonComponentInitializersRemainSourceCompatible() {
    _ = MoruProgressBar(current: 1, total: 9)
    _ = MoruToggle(isOn: .constant(true))
    _ = MoruTabBar(selection: .constant(.routine))
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
    let outputDirectory = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment[
        "MORU_CAPTURE_OUTPUT_DIR"
      ] ?? "/private/tmp/moru-figma-pilot-d0"
    )

    for variant in MoruVisualCaptureVariant.allCases {
      let first = try MoruVisualCaptureFixture.render(
        componentBoard(componentStyle: .figmaPilot),
        filename: "after-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )
      let second = try MoruVisualCaptureFixture.render(
        componentBoard(componentStyle: .figmaPilot),
        filename: "after-repeat-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )
      _ = try MoruVisualCaptureFixture.render(
        componentBoard(componentStyle: .legacy),
        filename: "before-\(variant.rawValue).png",
        variant: variant,
        outputDirectory: outputDirectory
      )

      XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
      XCTAssertEqual(first.scale, 3)
      XCTAssertEqual(first.pngData(), second.pngData())
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

  private func componentBoard(
    componentStyle: MoruPilotComponentStyle
  ) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: MoruPilotSpacing.twenty) {
          Text("공통 기준")
            .moruTextStyle(.h3)
            .foregroundStyle(MoruPilotColor.textStrong)
            .fixedSize(horizontal: false, vertical: true)

          MoruProgressBar(
            current: 5,
            total: 9,
            componentStyle: componentStyle
          )

          HStack(spacing: MoruPilotSpacing.twenty) {
            MoruToggle(
              isOn: .constant(true),
              componentStyle: componentStyle
            )
            MoruToggle(
              isOn: .constant(false),
              componentStyle: componentStyle
            )
          }

          MoruRoutineCard(
            title: "활력 루틴",
            description: "6개 항목 ・15분",
            isActive: true,
            componentStyle: componentStyle
          )
          MoruRoutineCard(
            title: "새 루틴 추가하기",
            isAddCard: true,
            componentStyle: componentStyle
          )
          MoruButton(
            "루틴 시작하기",
            componentStyle: componentStyle
          ) {}
        }
        .padding(.vertical, MoruPilotSpacing.thirtySix)
        .padding(.horizontal, MoruPilotSpacing.twenty)
      }

      MoruTabBar(
        selection: .constant(.routine),
        componentStyle: componentStyle
      )
    }
    .background(MoruPilotColor.canvas)
  }
}
