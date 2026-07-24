//
//  RoutineManagementCopy.swift
//  Moru
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI

enum RoutineManagementCopy {
  static let addRoutine = "새 루틴 추가하기"
  static let addStep = "새 항목 추가하기"
  static let createCompletion = "완료"
  static let editCompletion = "저장"
  static let creationTitle = "루틴 추가"
  static let recommendedTitle = "추천 루틴 만들기"
  static let recommendedDescription = "경험과 목표를 바탕으로\n로컬 템플릿을 추천해요."
  static let directTitle = "직접 루틴 만들기"
  static let directDescription = "각각의 항목을 직접 지정할 수 있어요."

  static func routineMetadata(stepCount: Int, totalMinutes: Int) -> String {
    "\(stepCount)개 항목 ・\(totalMinutes)분"
  }

  static func routineMetadata(
    stepCountText: String,
    durationText: String
  ) -> String {
    "\(stepCountText) ・\(durationText)"
  }

  static func scheduleSummary(
    weekdays: Set<Weekday>,
    hour: Int,
    minute: Int
  ) -> String {
    "\(weekdaySummary(weekdays))・\(String(format: "%02d시 %02d분", hour, minute))"
  }

  static func weekdayConflictMessage(
    _ conflict: RoutineWeekdayConflictState
  ) -> String {
    [
      "\(conflict.weekdayText)로 알림이 설정된",
      "다른 루틴이 이미 있어요.",
      "해당 루틴으로 요일을 변경하시겠어요?",
    ].joined(separator: "\n")
  }

  private static func weekdaySummary(_ weekdays: Set<Weekday>) -> String {
    let text = weekdays
      .sortedByDisplayOrder()
      .map(\.shortTitle)
      .joined(separator: " ")

    return text.isEmpty ? "요일 미설정" : text
  }
}

private struct RoutineManagementTextStyleModifier: ViewModifier {
  let style: MoruTextStyle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric private var scaledFontSize: CGFloat

  init(style: MoruTextStyle) {
    self.style = style
    _scaledFontSize = ScaledMetric(
      wrappedValue: style.fontSize,
      relativeTo: style.relativeTextStyle
    )
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      content
        .font(.custom(style.weight.rawValue, size: scaledFontSize))
    } else {
      content.moruTextStyle(style)
    }
  }
}

extension View {
  func routineManagementTextStyle(_ style: MoruTextStyle) -> some View {
    modifier(RoutineManagementTextStyleModifier(style: style))
  }
}
