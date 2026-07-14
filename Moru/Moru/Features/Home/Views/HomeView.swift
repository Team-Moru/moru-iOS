//
//  HomeView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeView: View {
  private let onStartRoutine: RoutineLaunchHandler
  private let refreshToken: Int
  private let routineSettingContent: AnyView

  @State private var viewModel: HomeViewModel
  @State private var isRoutineSettingPresented = false
  @State private var routineLaunchMessage: String?

  init(
    viewModel: HomeViewModel,
    onStartRoutine: @escaping RoutineLaunchHandler,
    refreshToken: Int,
    routineSettingContent: AnyView
  ) {
    self.onStartRoutine = onStartRoutine
    self.refreshToken = refreshToken
    self.routineSettingContent = routineSettingContent
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: AppSpacing.lg) {
        HomeHeaderView(userName: viewModel.state.userName)

        HStack(spacing: AppSpacing.md) {
          TodayRoutineProgressCard(progress: viewModel.state.todayProgress)
          HomeStreakCard(streak: viewModel.state.streak)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)

        CurrentRoutineCard(
          routine: viewModel.state.todayRoutine,
          onTap: {
            isRoutineSettingPresented = true
          },
          onStart: {
            guard let routineID = viewModel.state.todayRoutine?.id else {
              return
            }

            switch onStartRoutine(RoutineLaunchRequest(routineID: routineID)) {
            case .started, .alreadyRunning:
              break
            case .busy:
              routineLaunchMessage = "다른 루틴이 실행 중이에요."
            }
          }
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)

        if let errorMessage = viewModel.state.errorMessage {
          Text(errorMessage)
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.orange500)
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
        if let routineLaunchMessage {
          Text(routineLaunchMessage)
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.orange500)
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
      }
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(homeBackground.ignoresSafeArea())
    .task(id: refreshToken) {
      routineLaunchMessage = nil
      viewModel.load()
    }
    .sheet(isPresented: $isRoutineSettingPresented, onDismiss: {
      viewModel.load()
    }) {
      routineSettingContent
    }
  }

  private var homeBackground: LinearGradient {
    LinearGradient(
      stops: [
        Gradient.Stop(color: AppColor.babyBlue100, location: 0),
        Gradient.Stop(color: AppColor.babyBlue50, location: 1),
      ],
      startPoint: UnitPoint(x: 0.5, y: 0),
      endPoint: UnitPoint(x: 0.5, y: 1)
    )
  }
}

#if DEBUG
#Preview {
  DefaultHomeFlowBuilder(
    loadHomeRoutinesUseCase: HomePreviewLoadHomeRoutinesUseCase(),
    routineSettingContentFactory: {
      AnyView(RoutineSettingView(dependencies: .homePreview))
    }
  ).make(
    onStartRoutine: { _ in .started },
    refreshToken: 0
  )
}

@MainActor
private final class HomePreviewLoadHomeRoutinesUseCase: LoadHomeRoutinesUseCaseProtocol {
  func execute() throws -> HomeRoutineLoadResult {
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
          estimatedSeconds: 600
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 6,
        minute: 15,
        weekdays: Weekday.allCases
      )
    )
    return HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "다인"),
      todayRoutine: routine,
      manualRoutines: [routine],
      todayRun: nil,
      streak: HomeRoutineStreak(
        currentDays: 3,
        bestDays: 7,
        completedWeekdays: [.monday, .tuesday, .wednesday]
      )
    )
  }
}
#endif
