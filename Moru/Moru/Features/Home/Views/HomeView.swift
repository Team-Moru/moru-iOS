//
//  HomeView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Accessibility
import SwiftUI

typealias HomeAccessibilityAnnouncementHandler = @MainActor (String) -> Void

struct HomeRoutineLaunchBoundary {
  static let busyMessage = "다른 루틴이 실행 중이에요."

  private let onStartRoutine: RoutineLaunchHandler
  private let announceAccessibility: HomeAccessibilityAnnouncementHandler

  init(
    onStartRoutine: @escaping RoutineLaunchHandler,
    announceAccessibility: @escaping HomeAccessibilityAnnouncementHandler = { message in
      AccessibilityNotification.Announcement(message).post()
    }
  ) {
    self.onStartRoutine = onStartRoutine
    self.announceAccessibility = announceAccessibility
  }

  @MainActor
  func start(routineID: UUID) -> RoutineLaunchResult {
    let result = onStartRoutine(RoutineLaunchRequest(routineID: routineID))

    if result == .busy {
      announceAccessibility(Self.busyMessage)
    }

    return result
  }

  static func message(for result: RoutineLaunchResult) -> String? {
    switch result {
    case .started, .alreadyRunning:
      nil
    case .busy:
      busyMessage
    }
  }
}

struct HomeView: View {
  private let routineLaunchBoundary: HomeRoutineLaunchBoundary
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
    self.routineLaunchBoundary = HomeRoutineLaunchBoundary(onStartRoutine: onStartRoutine)
    self.refreshToken = refreshToken
    self.routineSettingContent = routineSettingContent
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: AppSpacing.lg) {
        switch viewModel.state {
        case .loading(let previousContent):
          if let previousContent {
            homeContent(previousContent)
            HomeRefreshIndicator()
          } else {
            HomeLoadingView()
          }
        case .content(let content):
          homeContent(content)
        case .empty:
          HomeEmptyView(onOpenRoutineSettings: {
            isRoutineSettingPresented = true
          })
        case .failed(let failure, let previousContent):
          if let previousContent {
            homeContent(previousContent)
            HomeFailureBanner(failure: failure, retryAction: viewModel.retry)
          } else {
            HomeFailureView(failure: failure, retryAction: viewModel.retry)
          }
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

  @ViewBuilder
  private func homeContent(_ content: HomeContentState) -> some View {
    HomeHeaderView(userName: content.userName)

    HStack(spacing: AppSpacing.md) {
      TodayRoutineProgressCard(progress: content.todayProgress)
      HomeStreakCard(streak: content.streak)
    }
    .padding(.horizontal, AppSpacing.screenHorizontal)

    CurrentRoutineCard(
      routine: content.todayRoutine,
      onTap: {
        isRoutineSettingPresented = true
      },
      onStart: {
        guard let routineID = content.todayRoutine?.id else {
          return
        }

        let result = routineLaunchBoundary.start(routineID: routineID)
        routineLaunchMessage = HomeRoutineLaunchBoundary.message(for: result)
      }
    )
    .padding(.horizontal, AppSpacing.screenHorizontal)

    if let routineLaunchMessage {
      Text(routineLaunchMessage)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.orange500)
        .padding(.horizontal, AppSpacing.screenHorizontal)
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

private struct HomeLoadingView: View {
  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      ProgressView()
        .tint(AppColor.orange400)
      Text("홈 정보를 불러오는 중이에요.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
    .accessibilityElement(children: .combine)
  }
}

private struct HomeRefreshIndicator: View {
  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      ProgressView()
        .tint(AppColor.orange400)
      Text("홈 정보를 새로 불러오는 중이에요.")
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .padding(.horizontal, AppSpacing.screenHorizontal)
    .accessibilityElement(children: .combine)
  }
}

private struct HomeEmptyView: View {
  let onOpenRoutineSettings: () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.md) {
      Image(systemName: "checklist")
        .font(AppFont.title1SemiBold)
        .foregroundStyle(AppColor.orange300)

      Text("아직 설정한 루틴이 없어요.")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text("루틴 탭에서 아침 루틴을 만들어 보세요.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)

      MoruButton("루틴 설정하기", style: .secondary, action: onOpenRoutineSettings)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
    .padding(.horizontal, AppSpacing.screenHorizontal)
  }
}

private struct HomeFailureView: View {
  let failure: HomeFailure
  let retryAction: () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.md) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(AppFont.title1SemiBold)
        .foregroundStyle(AppColor.orange500)

      Text(failure.userMessage)
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)
        .multilineTextAlignment(.center)

      MoruButton("다시 시도", style: .secondary, action: retryAction)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
    .padding(.horizontal, AppSpacing.screenHorizontal)
  }
}

private struct HomeFailureBanner: View {
  let failure: HomeFailure
  let retryAction: () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      Text(failure.userMessage)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextPrimary)
        .multilineTextAlignment(.center)

      MoruButton("다시 시도", style: .secondary, action: retryAction)
    }
    .padding(.horizontal, AppSpacing.screenHorizontal)
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
