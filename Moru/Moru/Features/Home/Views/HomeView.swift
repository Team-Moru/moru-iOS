
import Accessibility
import Foundation
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
struct HomeRoutineLaunchFeedback: Equatable {
  let visibleMessage: String
  let accessibilityLabel: String

  static func configuration(for result: RoutineLaunchResult) -> Self? {
    guard let visibleMessage = HomeRoutineLaunchBoundary.message(for: result) else {
      return nil
    }

    return Self(
      visibleMessage: visibleMessage,
      accessibilityLabel: visibleMessage
    )
  }
}

struct HomeView: View {
  static let rootAccessibilityIdentifier = "home.root"
  static let rootAccessibilityLabel = "홈"

  private let routineLaunchBoundary: HomeRoutineLaunchBoundary
  private let refreshToken: Int
  private let routineSettingContent: AnyView
  private let clearsRoutineLaunchFeedbackOnRefresh: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var viewModel: HomeViewModel
  @State private var isRoutineSettingPresented = false
  @State private var routineLaunchFeedback: HomeRoutineLaunchFeedback?

  init(
    viewModel: HomeViewModel,
    onStartRoutine: @escaping RoutineLaunchHandler,
    refreshToken: Int,
    routineSettingContent: AnyView,
    initialRoutineLaunchResult: RoutineLaunchResult? = nil
  ) {
    self.routineLaunchBoundary = HomeRoutineLaunchBoundary(onStartRoutine: onStartRoutine)
    self.refreshToken = refreshToken
    self.routineSettingContent = routineSettingContent
    self.clearsRoutineLaunchFeedbackOnRefresh = initialRoutineLaunchResult == nil
    _viewModel = State(initialValue: viewModel)
    _routineLaunchFeedback = State(
      initialValue: initialRoutineLaunchResult.flatMap(
        HomeRoutineLaunchFeedback.configuration(for:)
      )
    )
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
            weatherCard
            HomeLoadingView()
          }
        case .content(let content):
          homeContent(content)
        case .empty:
          weatherCard
          HomeEmptyView(onOpenRoutineSettings: {
            isRoutineSettingPresented = true
          })
        case .failed(let failure, let previousContent):
          if let previousContent {
            homeContent(previousContent)
            HomeFailureBanner(failure: failure, retryAction: viewModel.retry)
          } else {
            weatherCard
            HomeFailureView(failure: failure, retryAction: viewModel.retry)
          }
        }
      }
      .padding(.bottom, AppSpacing.xxl)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.rootAccessibilityIdentifier)
    .accessibilityLabel(Self.rootAccessibilityLabel)
    .background(homeBackground.ignoresSafeArea())
    .task(id: refreshToken) {
      if clearsRoutineLaunchFeedbackOnRefresh {
        routineLaunchFeedback = nil
      }
      viewModel.load()
    }
    .sheet(isPresented: $isRoutineSettingPresented, onDismiss: {
      viewModel.load()
    }) {
      routineSettingContent
    }
  }

  private var weatherCard: some View {
    HomeWeatherCard(
      state: viewModel.weatherState,
      requestWeather: viewModel.requestWeather
    )
    .padding(.horizontal, AppSpacing.screenHorizontal)
  }

  @ViewBuilder
  private func routineProgressCards(_ content: HomeContentState) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: AppSpacing.md) {
        TodayRoutineProgressCard(progress: content.todayProgress)
        HomeStreakCard(streak: content.streak)
      }
    } else {
      HStack(spacing: AppSpacing.md) {
        TodayRoutineProgressCard(progress: content.todayProgress)
        HomeStreakCard(streak: content.streak)
      }
    }
  }

  @ViewBuilder
  private func homeContent(_ content: HomeContentState) -> some View {
    HomeHeaderView(userName: content.userName)

    routineProgressCards(content)
      .padding(.horizontal, AppSpacing.screenHorizontal)

    weatherCard

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
        routineLaunchFeedback = HomeRoutineLaunchFeedback.configuration(for: result)
      }
    )
    .padding(.horizontal, AppSpacing.screenHorizontal)

    if let routineLaunchFeedback {
      Text(routineLaunchFeedback.visibleMessage)
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.orange500)
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(routineLaunchFeedback.accessibilityLabel)
        .accessibilityIdentifier("home.routineLaunch.feedback")
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

private struct HomeWeatherCard: View {
  let state: HomeWeatherState
  let requestWeather: () -> Void

  var body: some View {
    MoruCard(
      backgroundColor: AppColor.grayWhite,
      shadowColor: AppColor.babyBlue150,
      shadowRadius: 7.5,
      shadowY: 0
    ) {
      weatherContent
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.weather.card")
    .accessibilityLabel(weatherAccessibilityLabel)
  }

  private var weatherAccessibilityLabel: String {
    switch state {
    case .notRequested:
      "현재 위치 날씨 보기"
    case .requestingPermission, .locating, .loading:
      "날씨를 불러오는 중이에요"
    case .fresh(let snapshot):
      weatherSnapshotAccessibilityLabel(snapshot, updateText: "업데이트")
    case .stale(let snapshot):
      weatherSnapshotAccessibilityLabel(snapshot, updateText: "마지막 업데이트")
    case .denied:
      "위치 권한이 꺼져 있어요"
    case .restricted:
      "위치 접근이 제한되어 있어요"
    case .noFix:
      "현재 위치를 확인할 수 없어요"
    case .unavailable:
      "날씨 정보를 불러오지 못했어요"
    }
  }

  private func weatherSnapshotAccessibilityLabel(
    _ snapshot: HomeWeatherSnapshot,
    updateText: String
  ) -> String {
    "\(conditionLabel(for: snapshot.condition)), \(temperatureText(for: snapshot)), "
      + "\(updateText) \(updateTime(for: snapshot))"
  }

  @ViewBuilder
  private var weatherContent: some View {
    switch state {
    case .notRequested:
      weatherRequestButton
    case .requestingPermission, .locating, .loading:
      weatherLoadingContent
    case .fresh(let snapshot):
      weatherSnapshotContent(snapshot, updateText: "업데이트")
    case .stale(let snapshot):
      weatherSnapshotContent(snapshot, updateText: "마지막 업데이트")
    case .denied:
      weatherMessage("위치 권한이 꺼져 있어요")
    case .restricted:
      weatherMessage("위치 접근이 제한되어 있어요")
    case .noFix:
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        weatherMessage("현재 위치를 확인할 수 없어요")
        weatherRequestButton
      }
    case .unavailable:
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        weatherMessage("날씨 정보를 불러오지 못했어요")
        weatherRequestButton
      }
    }
  }

  private var weatherLoadingContent: some View {
    HStack(spacing: AppSpacing.sm) {
      ProgressView()
        .tint(AppColor.orange400)
        .accessibilityHidden(true)
      Text("날씨를 불러오는 중이에요")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextSecondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var weatherRequestButton: some View {
    Button(action: requestWeather) {
      Label("현재 위치 날씨 보기", systemImage: "location.fill")
        .font(AppFont.label1NormalMedium)
        .foregroundStyle(AppColor.moruTextPrimary)
    }
    .accessibilityLabel("현재 위치 날씨 보기")
    .accessibilityHint("현재 위치의 날씨를 요청합니다.")
  }

  private func weatherSnapshotContent(
    _ snapshot: HomeWeatherSnapshot,
    updateText: String
  ) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      HStack(spacing: AppSpacing.sm) {
        Image(systemName: symbolName(for: snapshot.condition))
          .foregroundStyle(AppColor.orange400)
          .accessibilityHidden(true)

        Text(conditionLabel(for: snapshot.condition))
          .font(AppFont.label1NormalMedium)
          .foregroundStyle(AppColor.moruTextPrimary)

        Text(temperatureText(for: snapshot))
          .font(AppFont.heading3SemiBold)
          .foregroundStyle(AppColor.moruTextPrimary)
      }
      .accessibilityElement(children: .combine)

      HStack {
        Text("\(updateText) \(updateTime(for: snapshot))")
          .font(AppFont.caption1Medium)
          .foregroundStyle(AppColor.moruTextSecondary)
        Spacer()
        Button(action: requestWeather) {
          Image(systemName: "arrow.clockwise")
            .foregroundStyle(AppColor.moruTextSecondary)
        }
        .accessibilityLabel("현재 위치 날씨 새로고침")
        .accessibilityHint("현재 위치의 날씨를 다시 요청합니다.")
      }
    }
  }

  private func weatherMessage(_ message: String) -> some View {
    Text(message)
      .font(AppFont.label1NormalMedium)
      .foregroundStyle(AppColor.moruTextSecondary)
      .accessibilityElement(children: .combine)
  }

  private func conditionLabel(for condition: HomeWeatherCondition) -> String {
    switch condition {
    case .clear:
      "맑음"
    case .cloudy:
      "흐림"
    case .rain:
      "비"
    case .snow:
      "눈"
    case .wind:
      "바람"
    case .fog:
      "안개"
    case .thunderstorm:
      "뇌우"
    case .mixed:
      "혼합"
    case .other:
      "기타"
    }
  }

  private func symbolName(for condition: HomeWeatherCondition) -> String {
    switch condition {
    case .clear:
      "sun.max.fill"
    case .cloudy:
      "cloud.fill"
    case .rain:
      "cloud.rain.fill"
    case .snow:
      "snowflake"
    case .wind:
      "wind"
    case .fog:
      "cloud.fog.fill"
    case .thunderstorm:
      "cloud.bolt.rain.fill"
    case .mixed:
      "cloud.sleet.fill"
    case .other:
      "cloud.fill"
    }
  }

  private func temperatureText(for snapshot: HomeWeatherSnapshot) -> String {
    let rounded = snapshot.temperatureCelsius.rounded(.toNearestOrAwayFromZero)
    return "\(String(format: "%.0f", rounded))°C"
  }

  private func updateTime(for snapshot: HomeWeatherSnapshot) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "ko_KR")
    let storedTimeZone = TimeZone(identifier: snapshot.fetchedTimeZoneIdentifier)
    let hasMatchingOffset = storedTimeZone?.secondsFromGMT(for: snapshot.fetchedAt)
      == snapshot.fetchedUTCOffsetSeconds
    formatter.timeZone = hasMatchingOffset
      ? storedTimeZone
      : TimeZone(secondsFromGMT: snapshot.fetchedUTCOffsetSeconds)
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: snapshot.fetchedAt)
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
        .font(AppFont.label1NormalMedium)
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
    weatherRepository: nil,
    weatherService: nil,
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
