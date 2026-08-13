//
//  FinalScreenVisualTests.swift
//  MoruTests
//

import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Moru

final class FinalScreenVisualTests: XCTestCase {
  @MainActor
  func testMainScreensRenderAtReferenceAccessibilitySizes() async throws {
    for variant in VisualVariant.allCases {
      try render(
        mainScreen(homeView(), selection: .home),
        filename: "moru-pr32-final-home-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        mainScreen(routineView(), selection: .routine),
        filename: "moru-pr32-final-routine-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        mainScreen(await historyView(), selection: .record),
        filename: "moru-pr32-final-history-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        mainScreen(profileView(), selection: .my),
        filename: "moru-pr32-final-profile-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        currentRoutineCard(),
        filename: "moru-pr32-final-current-routine-\(variant.filenameSuffix).png",
        variant: variant
      )
    }
  }

  @MainActor
  func testActiveRoutineSectionRendersAtReferenceAccessibilitySizes() throws {
    for variant in VisualVariant.allCases {
      try render(
        activeRoutineSection(),
        filename: "moru-pr34-home-active-routines-\(variant.filenameSuffix).png",
        variant: variant
      )
    }
  }

  @MainActor
  func testAlarmRingRendersAtReferenceAccessibilitySizes() throws {
    let alarmDate = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(
          timeZone: TimeZone(identifier: "Asia/Seoul"),
          year: 2026,
          month: 7,
          day: 23,
          hour: 7,
          minute: 30
        )
      )
    )

    for variant in VisualVariant.allCases {
      try render(
        AlarmRingView(
          routineName: "활력 루틴",
          routineMinutes: 15,
          alarmDate: alarmDate
        ),
        filename: "moru-pr43-alarm-ring-\(variant.filenameSuffix).png",
        variant: variant
      )
    }
  }

  @MainActor
  func testBundledVoiceOnboardingRendersAtReferenceAccessibilitySizes() throws {
    for variant in VisualVariant.allCases {
      try render(
        onboardingVoiceView(),
        filename: "moru-pr44-bundled-voices-\(variant.filenameSuffix).png",
        variant: variant
      )
    }
  }

  @MainActor
  func testSessionEmptyStatesRenderAtReferenceAccessibilitySizes() throws {
    for variant in [VisualVariant.lightMedium, .lightAccessibility3] {
      try render(
        mainScreen(emptyHomeView(), selection: .home),
        filename: "moru-pr50-session-empty-home-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        mainScreen(emptyRoutineView(), selection: .routine),
        filename: "moru-pr50-session-empty-routine-\(variant.filenameSuffix).png",
        variant: variant
      )
    }
  }

  @MainActor
  func testHistoryAndCompletionStreakSurfacesRenderAtReferenceAccessibilitySizes() async throws {
    for variant in [VisualVariant.lightMedium, .lightAccessibility3] {
      try render(
        mainScreen(await historyView(), selection: .record),
        filename: "moru-pr52-history-streak-\(variant.filenameSuffix).png",
        variant: variant,
        matchesApprovedBaseline: false
      )
      try render(
        weeklyComparisonCard(),
        filename: "moru-pr52-weekly-comparison-\(variant.filenameSuffix).png",
        variant: variant,
        matchesApprovedBaseline: false
      )
      try render(
        routineFinishedView(streak: RoutineStreak(
          currentDays: 3,
          bestDays: 7,
          completedWeekdays: [.sunday, .monday, .tuesday]
        )),
        filename: "moru-pr52-regular-completion-\(variant.filenameSuffix).png",
        variant: variant,
        matchesApprovedBaseline: false
      )
      try render(
        routineFinishedView(streak: nil, isTrial: true),
        filename: "moru-pr52-trial-completion-\(variant.filenameSuffix).png",
        variant: variant,
        matchesApprovedBaseline: false
      )
    }
  }

  @MainActor
  func testMainScreenAccessibilityIdentifierContractsAreUnique() throws {
    let rootIdentifiers = [
      HomeView.rootAccessibilityIdentifier,
      RoutineSettingView.rootAccessibilityIdentifier,
      HistoryView.rootAccessibilityIdentifier,
      ProfileView.rootAccessibilityIdentifier,
    ]
    let tabIdentifiers = MainTabState.availableTabs.map {
      MoruTabBar.accessibilityIdentifier(for: $0)
    }

    XCTAssertEqual(Set(rootIdentifiers).count, rootIdentifiers.count)
    XCTAssertEqual(Set(tabIdentifiers).count, tabIdentifiers.count)
    XCTAssertFalse(MoruTabBar.accessibilityIdentifier.isEmpty)
    XCTAssertTrue(rootIdentifiers.allSatisfy { !$0.isEmpty })
    XCTAssertTrue(tabIdentifiers.allSatisfy { $0.hasPrefix("app.tab.") })
    XCTAssertEqual(MainTabState.availableTabs.map(\.title), ["홈", "루틴", "이력", "마이"])
    XCTAssertEqual(
      HomeView.emptyCreateRoutineAccessibilityIdentifier,
      "home.empty.create-routine"
    )
    XCTAssertEqual(
      RoutineSettingView.emptyCreateRoutineAccessibilityIdentifier,
      "routine.empty.create-routine"
    )
    XCTAssertEqual(
      RoutineSettingView.addRoutineAccessibilityIdentifier,
      "routine.add"
    )
  }

  @MainActor
  private func homeView() -> some View {
    let viewModel = HomeViewModel(loadHomeRoutinesUseCase: VisualHomeUseCase())
    viewModel.load()

    return HomeView(
      viewModel: viewModel,
      onStartRoutine: { _ in .started },
      refreshToken: 0,
      routineSettingContent: AnyView(EmptyView())
    )
  }

  @MainActor
  private func routineView() -> some View {
    RoutineSettingView(dependencies: .homePreview)
  }

  @MainActor
  private func emptyHomeView() -> some View {
    let viewModel = HomeViewModel(loadHomeRoutinesUseCase: VisualEmptyHomeUseCase())
    viewModel.load()

    return HomeView(
      viewModel: viewModel,
      onStartRoutine: { _ in .started },
      refreshToken: 0,
      routineSettingContent: AnyView(EmptyView()),
      routineCreationContent: AnyView(EmptyView())
    )
  }

  @MainActor
  private func emptyRoutineView() -> some View {
    RoutineSettingView(dependencies: .mock())
  }

  @MainActor
  private func historyView() async -> some View {
    let viewModel = HistoryViewModel(loadHistoryUseCase: VisualHistoryUseCase())
    await viewModel.load()
    return HistoryView(viewModel: viewModel, automaticallyLoads: false)
  }

  @MainActor
  private func profileView() -> some View {
    let viewModel = ProfileViewModel(
      profileSettingsUseCase: VisualProfileUseCase(),
      voicePreviewPlayer: VisualVoicePreviewPlayer(),
      alarmService: VisualAlarmService(),
      resetUseCase: VisualResetUseCase(),
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
    viewModel.loadProfileSettings()
    return ProfileView(
      viewModel: viewModel,
      accountSessionStore: AccountSessionStore(
        credentialStore: KeychainCredentialStore(
          service: "com.teammoru.MoruTests.final-profile-visual"
        ),
        accessTokenProvider: MemoryAccessTokenProvider()
      )
    )
  }

  @MainActor
  private func onboardingVoiceView() -> some View {
    var draft = OnboardingDraft()
    draft.previewRoutine = .mockMorningRoutine
    let viewModel = OnboardingViewModel(
      draft: draft,
      step: .voice,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: VisualCompleteOnboardingUseCase(),
      voicePreviewPlayer: VisualVoicePreviewPlayer(),
      onCompleted: { _ in }
    )

    return OnboardingFlowView(viewModel: viewModel)
  }

  @MainActor
  private func currentRoutineCard() -> some View {
    ScrollView {
      CurrentRoutineCard(
        routine: .placeholder,
        onTap: {},
        onStart: {}
      )
      .padding(AppSpacing.screenHorizontal)
    }
    .background(AppColor.babyBlue50)
  }

  @MainActor
  private func weeklyComparisonCard() -> some View {
    HistoryWeeklySummaryCard(
      title: "7월 13일 ~ 7월 19일",
      completedRuns: 4,
      totalRuns: 5,
      completionRate: 0.8,
      completionRateChangePercentagePoints: 20,
      averageDurationText: "12:30"
    )
    .padding(AppSpacing.screenHorizontal)
    .background(AppColor.grayWhite)
  }

  @MainActor
  private func routineFinishedView(
    streak: RoutineStreak?,
    isTrial: Bool = false
  ) -> some View {
    RoutineFinishedView(
      completionRate: 1,
      streak: streak,
      completedStepTitles: ["물 마시기", "스트레칭", "오늘 계획 확인"],
      isTrial: isTrial,
      onTapTodayRecord: {},
      onTapHome: {}
    )
  }

  @MainActor
  private func activeRoutineSection() -> some View {
    var inProgressRoutine = HomeRoutineState.placeholder
    inProgressRoutine.id = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    inProgressRoutine.title = "출근 준비 루틴"
    inProgressRoutine.scheduleText = "평일 07:30"
    inProgressRoutine.stepSummaryText = "4개 스텝 · 18분"
    inProgressRoutine.completionText = "2/4 완료"
    inProgressRoutine.statusText = "진행 중"
    inProgressRoutine.progressText = "50%"
    inProgressRoutine.progress = 0.5

    var readyRoutine = HomeRoutineState.placeholder
    readyRoutine.id = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    readyRoutine.title = "주말 리셋 루틴"
    readyRoutine.scheduleText = "주말 08:00"
    readyRoutine.stepSummaryText = "3개 스텝 · 12분"
    readyRoutine.completionText = "0/3 완료"
    readyRoutine.statusText = "진행 전"
    readyRoutine.progressText = "0%"
    readyRoutine.progress = 0

    return ScrollView {
      HomeActiveRoutineSection(
        routines: [inProgressRoutine, readyRoutine],
        onOpenSettings: { _ in },
        onStartRoutine: { _ in }
      )
      .padding(AppSpacing.screenHorizontal)
    }
    .background(AppColor.babyBlue50)
  }

  @MainActor
  private func mainScreen<Content: View>(
    _ content: Content,
    selection: MoruTabItem
  ) -> some View {
    VStack(spacing: 0) {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      MoruTabBar(
        selection: .constant(selection),
        items: MainTabState.availableTabs
      )
    }
  }

  @MainActor
  private func render<Content: View>(
    _ content: Content,
    filename: String,
    variant: VisualVariant,
    matchesApprovedBaseline: Bool = true
  ) throws {
    let renderedContent = content
      .environment(\.dynamicTypeSize, variant.dynamicTypeSize)
      .environment(\.locale, Locale(identifier: "ko_KR"))
      .preferredColorScheme(.light)

    let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
    let windowScene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let hostingController = UIHostingController(rootView: renderedContent)
    let window = UIWindow(windowScene: windowScene)
    window.frame = bounds
    window.overrideUserInterfaceStyle = variant.userInterfaceStyle
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    hostingController.view.frame = bounds
    hostingController.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    hostingController.view.layoutIfNeeded()

    let renderer = UIGraphicsImageRenderer(bounds: bounds)
    let image = renderer.image { _ in
      hostingController.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }
    window.isHidden = true

    let data = try XCTUnwrap(image.pngData())
    let url = URL(fileURLWithPath: "/private/tmp/\(filename)")
    try data.write(to: url, options: .atomic)

    if matchesApprovedBaseline {
      try assertMatchesApprovedBaseline(image, filename: filename)
    } else {
      XCTAssertGreaterThan(data.count, 1_000)
    }
  }

  private func assertMatchesApprovedBaseline(
    _ image: UIImage,
    filename: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let baselineURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("docs/visual-test-baselines/final-screens")
      .appendingPathComponent(filename)
    let baseline = try XCTUnwrap(
      UIImage(contentsOfFile: baselineURL.path),
      "Missing approved visual baseline: \(baselineURL.path)",
      file: file,
      line: line
    )
    let distance = try MoruVisualHash.hammingDistance(
      between: image,
      and: baseline
    )
    XCTAssertLessThanOrEqual(
      distance,
      24,
      "Visual regression in \(filename), hash distance: \(distance), "
        + "baseline: \(baselineURL.path), actual: /private/tmp/\(filename)",
      file: file,
      line: line
    )
  }

}

private enum VisualVariant: CaseIterable {
  case lightMedium
  case lightAccessibility3

  var userInterfaceStyle: UIUserInterfaceStyle {
    .light
  }

  var dynamicTypeSize: DynamicTypeSize {
    switch self {
    case .lightMedium:
      return .medium
    case .lightAccessibility3:
      return .accessibility3
    }
  }

  var filenameSuffix: String {
    switch self {
    case .lightMedium:
      return "light-M"
    case .lightAccessibility3:
      return "light-AX3"
    }
  }
}

@MainActor
private final class VisualHomeUseCase: LoadHomeRoutinesUseCaseProtocol {
  func execute() throws -> HomeRoutineLoadResult {
    let steps = [
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
      RoutineStep(
        type: .input,
        title: "오늘의 기록 한 줄",
        order: 2,
        estimatedSeconds: 120
      ),
      RoutineStep(
        type: .timer,
        title: "햇빛 5분 쬐기",
        order: 3,
        estimatedSeconds: 300
      ),
    ]
    let routine = Routine(
      name: "기본 루틴",
      steps: steps,
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
      results: steps.prefix(2).map { step in
        RoutineStepResult(
          stepID: step.id,
          stepTitle: step.title,
          stepType: step.type,
          completedAt: Date()
        )
      }
    )

    return HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "다인"),
      todayRoutine: routine,
      manualRoutines: [routine],
      todayRunsByRoutineID: [routine.id: run],
      streak: HomeRoutineStreak(
        currentDays: 4,
        bestDays: 12,
        completedWeekdays: [.monday, .tuesday, .wednesday, .thursday]
      )
    )
  }
}

@MainActor
private final class VisualEmptyHomeUseCase: LoadHomeRoutinesUseCaseProtocol {
  func execute() throws -> HomeRoutineLoadResult {
    HomeRoutineLoadResult(
      profile: LocalProfile(displayName: "모루"),
      todayRoutine: nil,
      manualRoutines: [],
      todayRunsByRoutineID: [:],
      streak: HomeRoutineStreak(
        currentDays: 0,
        bestDays: 0,
        completedWeekdays: []
      )
    )
  }
}

@MainActor
private final class VisualHistoryUseCase: LoadHistoryUseCaseProtocol {
  func load() throws -> HistoryOverview {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ko_KR")
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let monthStart = date(2026, 7, 1, calendar: calendar)
    let runDate = date(2026, 7, 18, hour: 7, calendar: calendar)
    let step = HistoryStepResult(
      stepID: UUID(),
      stepTitle: "물 한 잔 마시기",
      isCompleted: true,
      isSkipped: false,
      transcript: nil
    )
    let run = HistoryRun(
      id: UUID(),
      routineName: "기본 루틴",
      startedAt: runDate,
      completedAt: runDate.addingTimeInterval(900),
      status: .completed,
      completionRate: 1,
      stepResults: [step]
    )
    let recentDay = HistoryDaySummary(
      date: runDate,
      completedRunCount: 1,
      totalRunCount: 1,
      completionRate: 1,
      runs: [run]
    )

    return HistoryOverview(
      calendar: calendar,
      recentDays: [recentDay],
      week: HistoryWeekReport(
        weekStartDate: date(2026, 7, 13, calendar: calendar),
        weekEndDate: date(2026, 7, 20, calendar: calendar),
        completedRunCount: 1,
        totalRunCount: 1,
        completionRate: 1,
        dailyCompletionRates: []
      ),
      wakeMetrics: .calculated(
        observationCount: 4,
        averageWakeMinute: 7 * 60,
        averageDeviationMinutes: 5,
        regularity: .veryConsistent
      ),
      monthlyHeatmap: HistoryMonthlyHeatmap(
        monthStartDate: monthStart,
        days: heatmapDays(monthStart: monthStart, calendar: calendar)
      ),
      streak: RoutineStreak(
        currentDays: 1,
        bestDays: 1,
        completedWeekdays: [.saturday]
      )
    )
  }

  private func heatmapDays(monthStart: Date, calendar: Calendar) -> [HistoryHeatmapDay] {
    let leadingFillers = 2
    return (0..<(leadingFillers + 31)).map { index in
      guard index >= leadingFillers,
            let date = calendar.date(
              byAdding: .day,
              value: index - leadingFillers,
              to: monthStart
            ) else {
        return HistoryHeatmapDay(
          id: "filler-\(index)",
          date: nil,
          completionRate: nil
        )
      }

      let day = index - leadingFillers + 1
      let rate: Double? = day > 18 ? nil : Double(day % 5) / 4
      return HistoryHeatmapDay(
        id: "day-\(day)",
        date: date,
        completionRate: rate
      )
    }
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    calendar: Calendar
  ) -> Date {
    calendar.date(
      from: DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour
      )
    )!
  }
}

@MainActor
private final class VisualProfileUseCase: ProfileSettingsUseCaseProtocol {
  private var profile = LocalProfile(displayName: "모루 사용자", selectedVoice: .aoede)

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    ProfileSettingsLoadResult(profile: profile, fallbackNotice: nil)
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    profile.displayName = displayName
    return ProfileSettingsLoadResult(profile: profile, fallbackNotice: nil)
  }

  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult {
    profile.selectedVoice = voice
    return ProfileSettingsLoadResult(profile: profile, fallbackNotice: nil)
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

@MainActor
private final class VisualVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}

@MainActor
private final class VisualCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  func execute(
    _ request: CompleteOnboardingRequest
  ) async throws -> CompleteOnboardingResult {
    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: request.suggestionInput
    )
    return CompleteOnboardingResult(
      profile: LocalProfile(selectedVoice: request.selectedVoice),
      routine: routine
    )
  }
}

@MainActor
private final class VisualAlarmService: ProfileAlarmServicing {
  func currentStatus() async -> ProfileAlarmStatus {
    .configured
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    .configured
  }

  func retryScheduling() async -> ProfileAlarmStatus {
    .configured
  }

  func cancelAllAlarms() async throws {}
}

@MainActor
private final class VisualResetUseCase: ResetLocalDataUseCaseProtocol {
  func execute() async throws {}
}
