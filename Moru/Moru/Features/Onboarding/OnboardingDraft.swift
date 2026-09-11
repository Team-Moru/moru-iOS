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
  var suggestionSource: RoutineSuggestionSource?
  var alarmHour: Int = 7
  var alarmMinute: Int = 0
  var selectedWeekdays: Set<Weekday> = Set(Weekday.displayOrder.prefix(5))
  var includeWeather: Bool = false
  var includeFortune: Bool = false
  var selectedVoice: VoiceProfile = .aoede

  var orderedGoalTags: [String] {
    Self.goalOptions
      .map(\.tag)
      .filter(selectedGoalTags.contains)
  }

  var orderedKeywords: [String] {
    Self.keywordOptions.filter(selectedKeywords.contains)
  }

  var orderedWeekdays: [Weekday] {
    Weekday.displayOrder.filter(selectedWeekdays.contains)
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
    OnboardingGoalOption(
      tag: "energy",
      title: "활력",
      subtitle: OnboardingCopy.goalDescription(for: "energy")
    ),
    OnboardingGoalOption(
      tag: "health",
      title: "건강",
      subtitle: OnboardingCopy.goalDescription(for: "health")
    ),
    OnboardingGoalOption(
      tag: "mind",
      title: "마음 안정",
      subtitle: OnboardingCopy.goalDescription(for: "mind")
    ),
    OnboardingGoalOption(
      tag: "habit",
      title: "습관 형성",
      subtitle: OnboardingCopy.goalDescription(for: "habit")
    ),
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
