//
//  HomeView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeView: View {
  private let dependencies: DependencyContainer
  private let onStartRoutine: RoutineLaunchHandler
  private let refreshToken: Int

  @State private var viewModel: HomeViewModel
  @State private var isRoutineSettingPresented = false
  @State private var routineLaunchMessage: String?

  init(
    dependencies: DependencyContainer,
    onStartRoutine: @escaping RoutineLaunchHandler = { _ in .started },
    refreshToken: Int = 0
  ) {
    self.dependencies = dependencies
    self.onStartRoutine = onStartRoutine
    self.refreshToken = refreshToken
    _viewModel = State(
      initialValue: HomeViewModel(
        loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
          routineRepository: dependencies.routineRepository,
          routineRunRepository: dependencies.routineRunRepository,
          localProfileRepository: dependencies.localProfileRepository
        )
      )
    )
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
      RoutineSettingView(dependencies: dependencies)
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
  HomeView(dependencies: .homePreview)
}
#endif
