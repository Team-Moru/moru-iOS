//
//  AppRouter.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct AppRouter: View {
  private enum State {
    case ready(dependencies: DependencyContainer, sessionStore: SessionStore)
    case bootstrapFailed(String)
  }

  private let state: State

  init(dependencies: DependencyContainer, sessionStore: SessionStore) {
    state = .ready(dependencies: dependencies, sessionStore: sessionStore)
  }

  init(bootstrapFailureMessage: String) {
    state = .bootstrapFailed(bootstrapFailureMessage)
  }

  var body: some View {
    Group {
      switch state {
      case .ready(let dependencies, let sessionStore):
        SessionContentView(dependencies: dependencies, sessionStore: sessionStore)
      case .bootstrapFailed(let message):
        ContentView(
          title: "저장소를 열 수 없어요",
          message: message
        )
      }
    }
  }

  private struct SessionContentView: View {
    let dependencies: DependencyContainer
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
      Group {
        switch sessionStore.phase {
        case .loading:
          ProgressView()
        case .onboardingRequired:
          #if DEBUG
          HomeView(dependencies: dependencies)
            .task {
              prepareDebugHomeDataIfNeeded()
              sessionStore.load()
            }
          #else
          ContentView(
            title: "MORU",
            message: "첫 루틴 생성 흐름을 연결할 준비가 되었습니다."
          )
          #endif
        case .ready:
          HomeView(dependencies: dependencies)
        case .failed(let message):
          ContentView(
            title: "저장소를 열 수 없어요",
            message: message
          )
        }
      }
      .task {
        sessionStore.load()
      }
    }

    #if DEBUG
    private func prepareDebugHomeDataIfNeeded() {
      do {
        _ = try sessionStore.createDefaultProfile()

        let routines = try dependencies.routineRepository.fetchRoutines()
        guard routines.isEmpty else {
          return
        }

        try dependencies.routineRepository.saveRoutine(.debugDefault)
      } catch {
        // Debug-only bootstrap fallback. Real onboarding will own this flow later.
      }
    }
    #endif
  }
}

#if DEBUG
private extension Routine {
  static var debugDefault: Routine {
    Routine(
      name: "기본 루틴",
      summary: "아침을 가볍게 여는 기본 루틴",
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
        hour: 7,
        minute: 0,
        weekdays: Weekday.allCases,
        isEnabled: true
      ),
      isActive: true
    )
  }
}
#endif
