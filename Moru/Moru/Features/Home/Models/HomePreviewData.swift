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
      name: "활력 루틴",
      summary: "활기차게 하루를 시작하는 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 한 잔 마시기",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          type: .timer,
          title: "가벼운 스트레칭",
          order: 1,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .input,
          title: "오늘의 목표 말하기",
          order: 2,
          estimatedSeconds: 120
        ),
        RoutineStep(
          type: .timer,
          title: "햇빛 쬐기",
          order: 3,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .confirm,
          title: "영양제 챙기기",
          order: 4,
          estimatedSeconds: 60
        ),
        RoutineStep(
          type: .timer,
          title: "아침 명상",
          order: 5,
          estimatedSeconds: 300
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 6,
        minute: 15,
        weekdays: Weekday.allCases
      ),
      isActive: true
    )
    let weekendRoutine = Routine(
      name: "주말 루틴",
      summary: "여유롭게 주말을 시작하는 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "창문 열기",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          type: .timer,
          title: "침구 정리하기",
          order: 1,
          estimatedSeconds: 180
        ),
        RoutineStep(
          type: .input,
          title: "이번 주 돌아보기",
          order: 2,
          estimatedSeconds: 240
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 8,
        minute: 0,
        weekdays: [.saturday, .sunday]
      ),
      isActive: false
    )
    let meditationRoutine = Routine(
      name: "명상 루틴",
      summary: "마음을 차분하게 정리하는 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "편안하게 앉기",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          type: .timer,
          title: "호흡 명상",
          order: 1,
          estimatedSeconds: 300
        ),
        RoutineStep(
          type: .input,
          title: "지금 기분 말하기",
          order: 2,
          estimatedSeconds: 120
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 21,
        minute: 0,
        weekdays: Weekday.allCases
      ),
      isActive: false
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

    let routineRepository = MockRoutineRepository(
      routines: [routine, weekendRoutine, meditationRoutine]
    )
    let localProfileRepository = MockLocalProfileRepository(
      profile: LocalProfile(displayName: "다인")
    )

    return DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: MockRoutineRunRepository(runs: [run]),
      localProfileRepository: localProfileRepository,
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: localProfileRepository,
        routineRepository: routineRepository
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }
}
#endif
