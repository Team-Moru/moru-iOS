//
//  HomeView.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Accessibility
import SwiftUI
import UIKit

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

struct HomeRoutineServerNoticeBoundary {
  private let announceAccessibility: HomeAccessibilityAnnouncementHandler

  init(
    announceAccessibility: @escaping HomeAccessibilityAnnouncementHandler = { message in
      AccessibilityNotification.Announcement(message).post()
    }
  ) {
    self.announceAccessibility = announceAccessibility
  }

  @MainActor
  func noticeDidChange(
    from oldNotice: HomeRoutineServerNotice?,
    to newNotice: HomeRoutineServerNotice?
  ) {
    guard oldNotice != newNotice,
          newNotice == .showingSavedRoutines else {
      return
    }

    announceAccessibility(HomeRoutineServerNotice.showingSavedRoutinesMessage)
  }
}

struct HomeView: View {
  static let rootAccessibilityIdentifier = "home.root"
  static let emptyCreateRoutineAccessibilityIdentifier =
    "home.empty.create-routine"
  static let routineSyncingAccessibilityIdentifier =
    "home.routine-sync.syncing"
  static let routineSavedDataAccessibilityIdentifier =
    "home.routine-sync.saved-data"
  static let routineServerRetryAccessibilityIdentifier =
    "home.routine-sync.retry"

  private let routineLaunchBoundary: HomeRoutineLaunchBoundary
  private let routineServerNoticeBoundary: HomeRoutineServerNoticeBoundary
  private let refreshToken: Int
  private let routineSettingContent: AnyView
  private let routineCreationContent: AnyView
  private let clearsRoutineLaunchMessageOnRefresh: Bool
  private let automaticallyLoads: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
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
    self.routineServerNoticeBoundary = HomeRoutineServerNoticeBoundary()
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
            homeContent(previousContent, showsRoutineServerNotice: false)
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
          routineServerNotice
          weatherCard
            .padding(.top, 24)
          HomeEmptyView(onCreateRoutine: {
            presentedRoutineSheet = .create
          })
          .padding(.top, MoruPilotSpacing.twenty)
        case .failed(let failure, let previousContent):
          if let previousContent {
            homeContent(previousContent, showsRoutineServerNotice: false)
            HomeFailureBanner(failure: failure, retryAction: viewModel.retry)
              .padding(.top, MoruPilotSpacing.twenty)
          } else {
            HomeHeaderView(userName: "")
            weatherCard
              .padding(.top, 24)
            HomeFailureView(failure: failure, retryAction: viewModel.retry)
              .padding(.top, MoruPilotSpacing.twenty)
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
      viewModel.loadWeatherAutomaticallyIfNeeded()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }

      viewModel.resumeWeatherAfterAuthorizationChange()
    }
    .onChange(of: viewModel.routineServerState.notice) { oldNotice, newNotice in
      routineServerNoticeBoundary.noticeDidChange(
        from: oldNotice,
        to: newNotice
      )
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

  private var weatherCard: some View {
    HomeWeatherCard(
      state: viewModel.weatherState,
      requestWeather: viewModel.requestWeather
    )
    .padding(.horizontal, AppSpacing.screenHorizontal)
  }

  @ViewBuilder
  private var routineServerNotice: some View {
    if let notice = viewModel.routineServerState.notice {
      HomeRoutineServerNoticeView(
        notice: notice,
        retryAction: viewModel.retry
      )
      .padding(.top, MoruPilotSpacing.twelve)
      .padding(.horizontal, MoruPilotSpacing.twenty)
    }
  }

  @ViewBuilder
  private func homeContent(
    _ content: HomeContentState,
    showsRoutineServerNotice: Bool = true
  ) -> some View {
    HomeHeaderView(userName: content.userName)

    if showsRoutineServerNotice {
      routineServerNotice
    }

    routineProgressCards(content)
      .padding(.top, 24)
      .padding(.horizontal, MoruPilotSpacing.twenty)

    weatherCard
      .padding(.top, MoruPilotSpacing.twenty)

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

struct HomeWeatherCard: View {
  let state: HomeWeatherState
  let requestWeather: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    weatherContent
    .padding(.horizontal, MoruPilotSpacing.twenty)
    .padding(.vertical, MoruPilotSpacing.twelve)
    .frame(
      maxWidth: .infinity,
      minHeight: minimumCardHeight,
      alignment: .leading
    )
    .homePilotSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.weather.card")
  }

  private var minimumCardHeight: CGFloat {
    switch state {
    case .fresh, .stale:
      HomeFigmaLayout.weatherCardHeight
    default:
      HomeFigmaLayout.actionableWeatherCardHeight
    }
  }

  @ViewBuilder
  private var weatherContent: some View {
    switch state {
    case .notRequested:
      weatherRequestButton
    case .requestingPermission, .locating, .loading:
      weatherLoadingContent
    case .fresh(let content):
      weatherSnapshotContent(content)
    case .stale(let content):
      weatherSnapshotContent(content)
    case .denied:
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        weatherMessage("위치 권한이 꺼져 있어요")
        openLocationSettingsButton
      }
    case .restricted:
      weatherMessage("위치 접근이 제한되어 있어요")
    case .noFix:
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        weatherMessage("현재 위치를 확인할 수 없어요")
        weatherRequestButton
      }
    case .unavailable(.service(.attributionUnavailable)):
      VStack(alignment: .leading, spacing: AppSpacing.sm) {
        weatherMessage("날씨 출처 정보를 불러오지 못했어요")
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
        .homeFigmaTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textSecondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var weatherRequestButton: some View {
    Button(action: requestWeather) {
      Label("현재 위치 날씨 보기", systemImage: "location.fill")
        .homeFigmaTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textPrimary)
    }
    .accessibilityHint("현재 위치의 날씨를 요청합니다.")
  }

  private var openLocationSettingsButton: some View {
    Button {
      Task {
        await AppSettingsOpener().open()
      }
    } label: {
      Label("설정에서 위치 권한 켜기", systemImage: "gearshape.fill")
        .homeFigmaTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textPrimary)
    }
    .accessibilityHint("MORU의 위치 권한을 변경할 수 있는 설정을 엽니다.")
  }

  @ViewBuilder
  private func weatherSnapshotContent(
    _ content: HomeWeatherContent
  ) -> some View {
    if let markImage = attributionMarkImage(for: content.attribution) {
      ZStack(alignment: .topTrailing) {
        weatherReading(content.snapshot)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .bottomTrailing) {
            temperatureRange(for: content.snapshot)
          }

        HStack(spacing: -MoruPilotSpacing.sixteen) {
          weatherAttributionLink(
            content.attribution,
            markImage: markImage
          )
          .offset(x: -1, y: MoruPilotSpacing.four)
          refreshButton
            .offset(x: 7, y: MoruPilotSpacing.four)
        }
        .offset(y: -MoruPilotSpacing.eight)
      }
    } else {
      VStack(alignment: .leading, spacing: MoruPilotSpacing.eight) {
        weatherMessage("날씨 출처 정보를 불러오지 못했어요")
        weatherRequestButton
      }
    }
  }

  @ViewBuilder
  private func temperatureRange(for snapshot: HomeWeatherSnapshot) -> some View {
    if let dailyHighCelsius = snapshot.dailyHighCelsius,
       let dailyLowCelsius = snapshot.dailyLowCelsius {
      Text(
        "최고 \(temperatureText(for: dailyHighCelsius)) · "
          + "최저 \(temperatureText(for: dailyLowCelsius))"
      )
      .homeFigmaTextStyle(.c2.weight(.regular))
      .foregroundStyle(MoruPilotColor.textSecondary)
      .lineLimit(1)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "최고 섭씨 \(temperatureText(for: dailyHighCelsius)), "
          + "최저 섭씨 \(temperatureText(for: dailyLowCelsius))"
      )
    }
  }

  private func weatherAttributionLink(
    _ attribution: HomeWeatherAttribution,
    markImage: UIImage
  ) -> some View {
    Link(destination: attribution.legalPageURL) {
      Image(uiImage: markImage)
        .resizable()
        .scaledToFit()
        .frame(height: 14)
        .fixedSize()
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .padding(.vertical, 5)
    .background {
      if colorScheme == .dark {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.black.opacity(0.6))
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Apple Weather")
    .accessibilityHint("Apple Weather의 날씨 데이터 출처 및 법적 고지 페이지를 엽니다.")
    .accessibilityIdentifier("home.weather.attribution.mark")
  }

  private func attributionMarkImage(
    for attribution: HomeWeatherAttribution
  ) -> UIImage? {
    let data = colorScheme == .dark
      ? attribution.combinedMarkDarkData
      : attribution.combinedMarkLightData
    return UIImage(data: data)
  }

  private func weatherReading(
    _ snapshot: HomeWeatherSnapshot
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(temperatureText(for: snapshot))
        .homeFigmaTextStyle(.h2)
        .foregroundStyle(MoruPilotColor.textPrimary)
        .lineLimit(1)

      Text("\(conditionLabel(for: snapshot.condition)) · 현재 위치")
      .homeFigmaTextStyle(.c2.weight(.regular))
      .foregroundStyle(MoruPilotColor.textTertiary)
      .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(weatherSnapshotAccessibilityLabel(snapshot))
    .accessibilityIdentifier("home.weather.reading")
  }

  private var refreshButton: some View {
    Button(action: requestWeather) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(MoruPilotColor.textSecondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("현재 위치 날씨 새로고침")
    .accessibilityHint("현재 위치의 날씨를 다시 요청합니다.")
  }

  private func weatherMessage(_ message: String) -> some View {
    Text(message)
      .homeFigmaTextStyle(.c1)
      .foregroundStyle(MoruPilotColor.textSecondary)
  }

  private func weatherSnapshotAccessibilityLabel(
    _ snapshot: HomeWeatherSnapshot
  ) -> String {
    let rounded = snapshot.temperatureCelsius.rounded(.toNearestOrAwayFromZero)
    var components = [
      "현재 위치",
      conditionLabel(for: snapshot.condition),
      "섭씨 \(String(format: "%.0f", rounded))도",
    ]
    if let dailyHighCelsius = snapshot.dailyHighCelsius,
       let dailyLowCelsius = snapshot.dailyLowCelsius {
      components.append("최고 섭씨 \(temperatureText(for: dailyHighCelsius))")
      components.append("최저 섭씨 \(temperatureText(for: dailyLowCelsius))")
    }
    return components.joined(separator: ", ")
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

  private func temperatureText(for snapshot: HomeWeatherSnapshot) -> String {
    temperatureText(for: snapshot.temperatureCelsius)
  }

  private func temperatureText(for temperatureCelsius: Double) -> String {
    let rounded = temperatureCelsius.rounded(.toNearestOrAwayFromZero)
    return "\(String(format: "%.0f", rounded))°"
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
        .frame(height: 84)

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

private struct HomeRoutineServerNoticeView: View {
  let notice: HomeRoutineServerNotice
  let retryAction: () -> Void

  var body: some View {
    switch notice {
    case .syncing:
      HStack(spacing: MoruPilotSpacing.eight) {
        ProgressView()
          .tint(AppColor.orange400)
          .accessibilityHidden(true)
        Text(notice.message)
          .homeFigmaTextStyle(.c1)
          .foregroundStyle(MoruPilotColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .homeRoutineServerNoticeSurface()
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(
        HomeView.routineSyncingAccessibilityIdentifier
      )

    case .showingSavedRoutines:
      VStack(spacing: 0) {
        Button(action: retryAction) {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: MoruPilotSpacing.eight) {
              savedRoutineNoticeLabel
              Spacer(minLength: MoruPilotSpacing.eight)
              retryLabel
            }

            VStack(alignment: .leading, spacing: MoruPilotSpacing.four) {
              savedRoutineNoticeLabel
              retryLabel
            }
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(notice.message) 다시 시도")
        .accessibilityHint("서버에서 최신 루틴 정보를 다시 확인합니다.")
        .accessibilityIdentifier(
          HomeView.routineServerRetryAccessibilityIdentifier
        )
      }
      .homeRoutineServerNoticeSurface(verticalPadding: 0)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(
        HomeView.routineSavedDataAccessibilityIdentifier
      )
    }
  }

  private var savedRoutineNoticeLabel: some View {
    HStack(spacing: MoruPilotSpacing.eight) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(AppColor.orange500)
        .accessibilityHidden(true)
      Text(notice.message)
        .homeFigmaTextStyle(.c1)
        .foregroundStyle(MoruPilotColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  private var retryLabel: some View {
    Text("다시 시도")
      .homeFigmaTextStyle(.c1.weight(.semiBold))
      .foregroundStyle(MoruPilotColor.accent)
      .fixedSize(horizontal: true, vertical: false)
  }
}

private extension View {
  func homeRoutineServerNoticeSurface(
    verticalPadding: CGFloat = MoruPilotSpacing.twelve
  ) -> some View {
    padding(.horizontal, MoruPilotSpacing.sixteen)
      .padding(.vertical, verticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(AppColor.grayWhite.opacity(0.45))
      .clipShape(RoundedRectangle(cornerRadius: MoruPilotRadius.card))
      .overlay {
        RoundedRectangle(cornerRadius: MoruPilotRadius.card)
          .stroke(MoruPilotColor.border.opacity(0.5), lineWidth: 1)
      }
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
