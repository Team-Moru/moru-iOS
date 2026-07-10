//
//  HomePreviewData.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

#if DEBUG
import Foundation

extension DependencyContainer {
  static var homePreview: DependencyContainer {
    let routine = Routine(
      name: "기본 루틴",
      summary: "가볍게 시작하는 아침 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 한 잔 마시기",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          type: .timer,
          title: "스트레칭 10분",
          order: 1,
          estimatedSeconds: 679
        ),
        RoutineStep(
          type: .input,
          title: "오늘의 기록 한 줄",
          order: 2,
          estimatedSeconds: 155
        ),
        RoutineStep(
          type: .timer,
          title: "햇빛 5분 쬐기",
          order: 3,
          estimatedSeconds: 302
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 6,
        minute: 15,
        weekdays: Weekday.allCases
      ),
      isActive: true
    )

    let run = RoutineRun(
      routine: routine,
      completedAt: Date(),
      results: routine.steps.map { step in
        RoutineStepResult(
          stepID: step.id,
          stepTitle: step.title,
          stepType: step.type,
          completedAt: Date()
        )
      }
    )

    return DependencyContainer(
      routineRepository: MockRoutineRepository(routines: [routine]),
      routineRunRepository: MockRoutineRunRepository(runs: [run]),
      localProfileRepository: MockLocalProfileRepository(
        profile: LocalProfile(displayName: "다인")
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }
}
#endif
