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
  static let rootAccessibilityIdentifier = "home.root"
  static let emptyCreateRoutineAccessibilityIdentifier =
    "home.empty.create-routine"

  private let routineLaunchBoundary: HomeRoutineLaunchBoundary
  private let refreshToken: Int
  private let routineSettingContent: AnyView
  private let routineCreationContent: AnyView
  private let clearsRoutineLaunchMessageOnRefresh: Bool
  private let automaticallyLoads: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: HomeViewModel
  @State private var presentedRoutineSheet: HomeRoutineSheet?
  @State private var routineLaunchMessage: String?

  init(
    viewModel: HomeViewModel,
    onStartRoutine: @escaping RoutineLaunchHandler,
    refreshToken: Int,
    routineSettingContent: AnyView,
    routineCreationContent: AnyView? = nil,
    initialRoutineLaunchMessage: String? = nil,
    automaticallyLoads: Bool = true
  ) {
    self.routineLaunchBoundary = HomeRoutineLaunchBoundary(onStartRoutine: onStartRoutine)
    self.refreshToken = refreshToken
    self.routineSettingContent = routineSettingContent
    self.routineCreationContent = routineCreationContent ?? routineSettingContent
    self.clearsRoutineLaunchMessageOnRefresh = initialRoutineLaunchMessage == nil
    self.automaticallyLoads = automaticallyLoads
    _viewModel = State(initialValue: viewModel)
    _routineLaunchMessage = State(initialValue: initialRoutineLaunchMessage)
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: 0) {
        switch viewModel.state {
        case .loading(let previousContent):
          if let previousContent {
            homeContent(previousContent)
            HomeRefreshIndicator()
              .padding(.top, MoruPilotSpacing.twenty)
          } else {
            HomeHeaderView(userName: "")
            HomeLoadingSkeleton()
              .padding(.top, 24)
              .padding(.horizontal, MoruPilotSpacing.twenty)
          }
        case .content(let content):
          homeContent(content)
        case .empty(let content):
          HomeHeaderView(userName: content.userName)
          HomeEmptyView(onCreateRoutine: {
            presentedRoutineSheet = .create
          })
          .padding(.top, 24)
        case .failed(let failure, let previousContent):
          if let previousContent {
            homeContent(previousContent)
            HomeFailureBanner(failure: failure, retryAction: viewModel.retry)
              .padding(.top, MoruPilotSpacing.twenty)
          } else {
            HomeHeaderView(userName: "")
            HomeFailureView(failure: failure, retryAction: viewModel.retry)
              .padding(.top, 24)
          }
        }
      }
      .padding(.bottom, MoruPilotSpacing.sixtyFour)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .accessibilityLabel("홈")
    .background(homeBackground.ignoresSafeArea())
    .task(id: refreshToken) {
      guard automaticallyLoads else {
        return
      }

      if clearsRoutineLaunchMessageOnRefresh {
        routineLaunchMessage = nil
      }
      viewModel.load()
    }
    .sheet(item: $presentedRoutineSheet, onDismiss: {
      viewModel.load()
    }) { sheet in
      switch sheet {
      case .settings:
        routineSettingContent
      case .create:
        routineCreationContent
      }
    }
  }

  @ViewBuilder
  private func homeContent(_ content: HomeContentState) -> some View {
    HomeHeaderView(userName: content.userName)

    routineProgressCards(content)
      .padding(.top, 24)
      .padding(.horizontal, MoruPilotSpacing.twenty)

    CurrentRoutineCard(
      routine: content.todayRoutine,
      onTap: {
        presentedRoutineSheet = .settings
      },
      onStart: {
        guard let routineID = content.todayRoutine?.id else {
          return
        }

        startRoutine(routineID)
      }
    )
    .padding(.top, MoruPilotSpacing.twenty)
    .padding(.horizontal, MoruPilotSpacing.twenty)

    HomeActiveRoutineSection(
      routines: content.activeRoutines,
      onOpenSettings: { _ in
        presentedRoutineSheet = .settings
      },
      onStartRoutine: startRoutine
    )
    .padding(.top, MoruPilotSpacing.thirtyTwo)
    .padding(.horizontal, MoruPilotSpacing.twenty)

    if let routineLaunchMessage {
      Text(routineLaunchMessage)
        .font(AppFont.caption1Medium)
        .foregroundStyle(AppColor.orange500)
        .padding(.top, MoruPilotSpacing.sixteen)
        .padding(.horizontal, MoruPilotSpacing.twenty)
    }
  }

  private func startRoutine(_ routineID: UUID) {
    let result = routineLaunchBoundary.start(routineID: routineID)
    routineLaunchMessage = HomeRoutineLaunchBoundary.message(for: result)
  }

  @ViewBuilder
  private func routineProgressCards(_ content: HomeContentState) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: AppSpacing.md) {
        TodayRoutineProgressCard(progress: content.todayProgress)
        HomeStreakCard(streak: content.streak)
      }
    } else {
      HStack(spacing: MoruPilotSpacing.twenty) {
        TodayRoutineProgressCard(progress: content.todayProgress)
        HomeStreakCard(streak: content.streak)
      }
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

private enum HomeRoutineSheet: String, Identifiable {
  case settings
  case create

  var id: String {
    rawValue
  }
}

private struct HomeLoadingSkeleton: View {
  var body: some View {
    VStack(spacing: MoruPilotSpacing.twenty) {
      HStack(spacing: MoruPilotSpacing.twenty) {
        HomeSkeletonBlock()
          .frame(height: 184)
        HomeSkeletonBlock()
          .frame(height: 184)
      }

      HomeSkeletonBlock()
        .frame(height: 326)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("홈 정보를 불러오는 중이에요.")
  }
}

private struct HomeSkeletonBlock: View {
  var body: some View {
    RoundedRectangle(cornerRadius: MoruPilotRadius.largeCard)
      .fill(
        LinearGradient(
          colors: [
            AppColor.gray150.opacity(0.5),
            AppColor.gray250.opacity(0.5),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .accessibilityHidden(true)
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
  let onCreateRoutine: () -> Void

  var body: some View {
    VStack(spacing: AppSpacing.md) {
      Image(systemName: "checklist")
        .font(AppFont.title1SemiBold)
        .foregroundStyle(AppColor.orange300)

      Text("아직 만든 루틴이 없어요.")
        .font(AppFont.heading3SemiBold)
        .foregroundStyle(AppColor.moruTextPrimary)

      Text("새 루틴을 만들어 나만의 아침을 시작해 보세요.")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
        .multilineTextAlignment(.center)

      MoruButton("새 루틴 만들기", style: .secondary, action: onCreateRoutine)
        .accessibilityIdentifier(
          HomeView.emptyCreateRoutineAccessibilityIdentifier
        )
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
    let additionalRoutine = Routine(
      name: "출근 준비 루틴",
      steps: [
        RoutineStep(type: .confirm, title: "침구 정리", order: 0, estimatedSeconds: 60),
        RoutineStep(type: .timer, title: "아침 식사", order: 1, estimatedSeconds: 600),
      ],
      alarmSchedule: AlarmSchedule(hour: 7, minute: 30, weekdays: Weekday.weekdays)
    )
    return HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "다인"),
      todayRoutine: routine,
      manualRoutines: [routine, additionalRoutine],
      todayRunsByRoutineID: [:],
      streak: HomeRoutineStreak(
        currentDays: 3,
        bestDays: 7,
        completedWeekdays: [.monday, .tuesday, .wednesday]
      )
    )
  }
}
#endif
