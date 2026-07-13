//
//  HomeView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct HomeView: View {
  private let dependencies: DependencyContainer
  private let onStartRoutine: @MainActor (UUID) -> Void

  @State private var viewModel: HomeViewModel
  @State private var isRoutineSettingPresented = false

  init(
    dependencies: DependencyContainer,
    onStartRoutine: @escaping @MainActor (UUID) -> Void = { _ in }
  ) {
    self.dependencies = dependencies
    self.onStartRoutine = onStartRoutine
    _viewModel = State(initialValue: HomeViewModel(dependencies: dependencies))
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
            viewModel.currentRoutineCardDidTap()
          },
          onStart: {
            guard let routineID = viewModel.state.todayRoutine?.id else {
              return
            }

            onStartRoutine(routineID)
          }
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)

        if let errorMessage = viewModel.state.errorMessage {
          Text(errorMessage)
            .font(AppFont.caption1Medium)
            .foregroundStyle(AppColor.orange500)
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
      }
      .padding(.bottom, AppSpacing.xxl)
    }
    .background(homeBackground.ignoresSafeArea())
    .task {
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
