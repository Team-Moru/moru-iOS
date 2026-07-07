//
//  OnboardingDraft.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

struct OnboardingDraft: Equatable {
  var experience: RoutineExperience = .firstTime
  var selectedGoalTags: Set<String> = []
  var selectedKeywords: Set<String> = []
  var freeformText: String = ""
  var previewRoutine: Routine?
  var alarmHour: Int = 7
  var alarmMinute: Int = 0
  var selectedWeekdays: Set<Weekday> = Set(Weekday.onboardingDisplayOrder.prefix(5))
  var selectedVoice: VoiceProfile = .moru

  var orderedGoalTags: [String] {
    Self.goalOptions
      .map(\.tag)
      .filter(selectedGoalTags.contains)
  }

  var orderedKeywords: [String] {
    Self.keywordOptions.filter(selectedKeywords.contains)
  }

  var orderedWeekdays: [Weekday] {
    Weekday.onboardingDisplayOrder.filter(selectedWeekdays.contains)
  }

  var suggestionInput: RoutineSuggestionInput {
    RoutineSuggestionInput(
      experience: experience,
      routineName: "",
      goalTags: orderedGoalTags,
      selectedKeywords: orderedKeywords,
      freeformText: freeformText,
      wakeUpHour: alarmHour,
      wakeUpMinute: alarmMinute,
      weekdays: orderedWeekdays
    )
  }

  var formattedAlarmTime: String {
    String(format: "%02d:%02d", alarmHour, alarmMinute)
  }

  var estimatedDurationMinutes: Int {
    guard let previewRoutine else {
      return 0
    }

    let seconds = previewRoutine.steps.reduce(0) { total, step in
      total + (step.estimatedSeconds ?? 60)
    }

    return max(1, Int(ceil(Double(seconds) / 60.0)))
  }

  static let goalOptions: [OnboardingGoalOption] = [
    OnboardingGoalOption(tag: "energy", title: "활력", subtitle: "상쾌하게 하루를 시작"),
    OnboardingGoalOption(tag: "health", title: "건강", subtitle: "몸을 부드럽게 깨우기"),
    OnboardingGoalOption(tag: "mind", title: "마음 안정", subtitle: "차분한 시작 만들기"),
    OnboardingGoalOption(tag: "habit", title: "습관 형성", subtitle: "작은 행동을 꾸준히")
  ]

  static let keywordOptions = [
    "물 마시기",
    "스트레칭",
    "명상",
    "일기",
    "독서"
  ]
}

struct OnboardingGoalOption: Identifiable, Equatable {
  let tag: String
  let title: String
  let subtitle: String

  var id: String {
    tag
  }
}

extension Weekday {
  static let onboardingDisplayOrder: [Weekday] = [
    .monday,
    .tuesday,
    .wednesday,
    .thursday,
    .friday,
    .saturday,
    .sunday
  ]

  var shortKoreanTitle: String {
    switch self {
    case .monday:
      return "월"
    case .tuesday:
      return "화"
    case .wednesday:
      return "수"
    case .thursday:
      return "목"
    case .friday:
      return "금"
    case .saturday:
      return "토"
    case .sunday:
      return "일"
    }
  }
}
