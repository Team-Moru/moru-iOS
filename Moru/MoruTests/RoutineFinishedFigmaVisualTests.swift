//
//  RoutineFinishedFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

@MainActor
final class RoutineFinishedFigmaVisualTests: XCTestCase {
  func testRoutineFinishedStatesRenderDeterministicallyAtReferenceVariants() throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_ROUTINE_FINISHED_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-d2-\(phase)"
    )

    for state in RoutineFinishedCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let filename = "\(state.rawValue)-\(variant.rawValue).png"
        let first = try MoruVisualCaptureFixture.render(
          routineFinishedView(for: state),
          filename: filename,
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          routineFinishedView(for: state),
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        XCTAssertEqual(first.pngData(), second.pngData())
      }
    }
  }

  private func routineFinishedView(
    for state: RoutineFinishedCaptureState
  ) -> some View {
    RoutineFinishedView(
      completionRate: state.completionRate,
      streak: state.streak,
      completedStepTitles: state.completedStepTitles,
      isTrial: state == .trial,
      onTapTodayRecord: {},
      onTapHome: {}
    )
  }
}

private enum RoutineFinishedCaptureState: String, CaseIterable {
  case regular
  case trial
  case noStreak = "no-streak"
  case noCompletedSteps = "no-completed-steps"
  case longKorean = "long-korean"

  var completionRate: Double {
    switch self {
    case .longKorean:
      0.67
    case .noCompletedSteps:
      0
    case .regular, .trial, .noStreak:
      1
    }
  }

  var streak: RoutineStreak? {
    switch self {
    case .regular:
      RoutineStreak(
        currentDays: 4,
        bestDays: 7,
        completedWeekdays: [.monday, .tuesday, .wednesday, .thursday]
      )
    case .noCompletedSteps:
      RoutineStreak(
        currentDays: 2,
        bestDays: 5,
        completedWeekdays: [.monday, .tuesday]
      )
    case .longKorean:
      RoutineStreak(
        currentDays: 12,
        bestDays: 42,
        completedWeekdays: Set(Weekday.allCases)
      )
    case .trial, .noStreak:
      nil
    }
  }

  var completedStepTitles: [String] {
    switch self {
    case .regular:
      [
        "잠자리 정리하기",
        "가볍게 스트레칭하기",
        "심호흡하며 명상하기",
        "짧은 독서 몰입하기",
        "오늘의 다짐 확인하기",
        "감정과 생각을 기록하기",
      ]
    case .trial:
      [
        "잠자리 정리하기",
        "오늘의 다짐 확인하기",
      ]
    case .noStreak:
      [
        "물 한 잔 마시기",
        "창문 열고 환기하기",
        "오늘 계획 확인하기",
      ]
    case .noCompletedSteps:
      []
    case .longKorean:
      [
        "잠에서 깬 몸을 천천히 깨우는 전신 스트레칭하기",
        "창문을 활짝 열고 아침 공기를 깊게 마시며 환기하기",
        "오늘 꼭 마무리할 가장 중요한 한 가지 목표 확인하기",
        "따뜻한 물 한 잔을 천천히 마시며 몸의 감각 살피기",
        "마음이 차분해지는 호흡에 집중하며 짧게 명상하기",
        "감사한 일을 떠올리고 오늘의 다짐을 또렷하게 기록하기",
      ]
    }
  }
}
