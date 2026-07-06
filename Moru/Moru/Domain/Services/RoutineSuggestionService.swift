//
//  RoutineSuggestionService.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

struct RoutineSuggestionInput: Hashable {
  var routineName: String
  var goalTags: [String]
  var wakeUpHour: Int
  var wakeUpMinute: Int
  var weekdays: [Weekday]

  init(
    routineName: String = "",
    goalTags: [String] = [],
    wakeUpHour: Int = 7,
    wakeUpMinute: Int = 0,
    weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
  ) {
    self.routineName = routineName
    self.goalTags = goalTags
    self.wakeUpHour = wakeUpHour
    self.wakeUpMinute = wakeUpMinute
    self.weekdays = weekdays
  }
}

@MainActor
protocol RoutineSuggestionService {
  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine
}

struct LocalTemplateSuggestionService: RoutineSuggestionService {
  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    let now = Date()
    let trimmedName = input.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
    let routineName = trimmedName.isEmpty ? "상쾌한 아침 루틴" : trimmedName
    let alarmSchedule = AlarmSchedule(
      hour: input.wakeUpHour,
      minute: input.wakeUpMinute,
      weekdays: input.weekdays
    )

    return Routine(
      name: routineName,
      summary: "기상 직후 몸과 마음을 깨우는 로컬 추천 루틴",
      goalTags: input.goalTags,
      steps: [
        RoutineStep(
          type: .confirm,
          title: "잠자리 정리",
          instruction: "이불과 베개를 가볍게 정리해 주세요.",
          order: 0
        ),
        RoutineStep(
          type: .timer,
          title: "심호흡 명상",
          instruction: "천천히 숨을 들이마시고 내쉬며 몸을 깨워 주세요.",
          order: 1,
          estimatedSeconds: 120
        ),
        RoutineStep(
          type: .input,
          title: "오늘의 다짐",
          instruction: "하루 시작 문장을 말하거나 적어 주세요.",
          order: 2
        )
      ],
      alarmSchedule: alarmSchedule,
      createdAt: now,
      updatedAt: now
    )
  }
}
