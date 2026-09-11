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
  private static let homeReferenceDate: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.date(
      from: DateComponents(year: 2026, month: 7, day: 24, hour: 9, minute: 0)
    )!
  }()

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
        variant: variant
      )
      try render(
        weeklyComparisonCard(),
        filename: "moru-pr52-weekly-comparison-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        routineFinishedView(streak: RoutineStreak(
          currentDays: 3,
          bestDays: 7,
          completedWeekdays: [.sunday, .monday, .tuesday]
        )),
        filename: "moru-pr52-regular-completion-\(variant.filenameSuffix).png",
        variant: variant
      )
      try render(
        routineFinishedView(streak: nil, isTrial: true),
        filename: "moru-pr52-trial-completion-\(variant.filenameSuffix).png",
        variant: variant
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
    let tabIdentifiers = MainTabState.availableTabs.map(\.accessibilityIdentifier)

    XCTAssertEqual(Set(rootIdentifiers).count, rootIdentifiers.count)
    XCTAssertEqual(Set(tabIdentifiers).count, tabIdentifiers.count)
    XCTAssertFalse(MoruTabItem.containerAccessibilityIdentifier.isEmpty)
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
      stepResults: ["물 마시기", "스트레칭", "오늘 계획 확인"]
        .enumerated()
        .map { index, title in
          RoutineStepResult(
            stepID: UUID(),
            stepTitle: title,
            stepType: index == 1 ? .timer : .confirm,
            completedAt: Date(timeIntervalSince1970: 1)
          )
        },
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
    MainTabView(
      home: AnyView(selection == .home ? AnyView(content) : AnyView(EmptyView())),
      routineSetting: AnyView(selection == .routine ? AnyView(content) : AnyView(EmptyView())),
      history: AnyView(selection == .record ? AnyView(content) : AnyView(EmptyView())),
      profile: AnyView(selection == .my ? AnyView(content) : AnyView(EmptyView())),
      selection: .constant(selection)
    )
  }

  @MainActor
  private func render<Content: View>(
    _ content: Content,
    filename: String,
    variant: VisualVariant
  ) throws {
    let outputDirectory = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-final-screens"
    )
    let image = try MoruVisualCaptureFixture.render(
      content
        // 홈 인사말은 시간대(오전/오후/저녁)에 따라 바뀌어 AX3 레이아웃이 흔들린다.
        // 기준선은 오전에 승인됐으므로 09:00 KST로 고정한다.
        .environment(\.homeCaptureReferenceDate, Self.homeReferenceDate),
      filename: filename,
      variant: variant.captureVariant,
      outputDirectory: outputDirectory
    )
    try assertVisualBaseline(
      image,
      name: filename,
      expected: VisualBaseline.hashes[filename],
      outputDirectory: outputDirectory
    )
  }

}

private enum VisualBaseline {
  static let hashes: [String: String] = [
    "moru-pr32-final-current-routine-light-AX3.png":
      "AAAAAAAAgoJlZWUk8kj6QMpA2kDyyPLAyWjAYMBowFB0oXSFeAF5mW9hf2F9YVwZVZF5kXjROAlpQXlBXUFYkQ==",
    "moru-pr32-final-current-routine-light-M.png":
      "AAAAAAAAoAhgBfKY8tj4GEAE0A1QBVANWQVZDVAN0A2EAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
    "moru-pr32-final-history-light-AX3.png":
      "AAAAAAAACADgAOQA1APYAMFkwSTANMC0xRTAdMIkwjTIzMjMyMzI0MjQyMzIxMgEyATIBOAAyiLOCmTLrcvZJA==",
    "moru-pr32-final-history-light-M.png":
      "AAAAAAAAIADAAMgCwADaFMwY3JjEBEgAoALiBDhwMXFxYTFhAgDAAKAgFwBGASFBVVVvcM9w9zD1GGTLpcvSFA==",
    "moru-pr32-final-home-light-AX3.png":
      "AAAEAQcADwA8gDjg3mLGYfBx+eD5gO2A1oDWgAlgCYESyQZBR2UkoSbJLYEuSQxBgBADAAMgEyDkiuTL5NvsiA==",
    "moru-pr32-final-home-light-M.png":
      "AAAEAQcADwA8gDjgcOBw8HDxeOD8wMyAzwDWAAoIGTEwMTBxPMA58DFgCABkAmCBaQEGAEAE4yTkmuTb5NvSJA==",
    "moru-pr32-final-profile-light-AX3.png":
      "AAAAAAAACADgAOQAxAAqwJrS6MLNTrxCKBDZANEA7IToBBIAyADIgHpE6kTkQPMA4yjiIMIkxcCk0CTYpNjRIA==",
    "moru-pr32-final-profile-light-M.png":
      "AAAAAAAAIADAAMgAwYA6QmpCyIIxAMgAgADgBOAEkACQAGAE4ASYAMACwiDCIOgE6QSWAMAAwgSsnGTYpNjBJA==",
    "moru-pr32-final-routine-light-AX3.png":
      "AAAAAAAACADAAMQA5AA4AAIAykTKYNkY2RTTMNpwxOTAYMAQFgHoAOyAWxLdEF2AGmRAcEBwkCCsimzbrEvTJA==",
    "moru-pr32-final-routine-light-M.png":
      "AAAAAAAAIACAAMgAyAAUAOEA4ADZGMg0yDDxCMACyAAmBlg4SDhCBIICWDjIOEIQgARPAEUAQQAsymzbrFrSJA==",
    "moru-pr34-home-active-routines-light-AX3.png":
      "AAAAAAaAyQDJAKVCSIVIjWMBYiFSgWmBaZEUgWkxajBoQUkFfkHjOOE4fID4AIOKbI1khWdhUoFakWmRaZFCSQ==",
    "moru-pr34-home-active-routines-light-M.png":
      "AAAAABgAwACBAnAFQAVkQUGNQgxiA2DJ5MjiAIwGcAV0QXRBSI1ABGIhZMjkyPIQAAQAAAAAAAAAAAAAAAAAAA==",
    "moru-pr43-alarm-ring-light-AX3.png":
      "AAAAAAAAAEEAABM2K4sqmxY2KIhEDAAsAAAAAAAAQAAIaiaTLkspQ4BwIHAAIAQAAAAAAEAAGAceez5XkAYAAA==",
    "moru-pr43-alarm-ring-light-M.png":
      "AAAAAAAAIiEAABAABVglOAZYACASMAQAAAAAAAAAwIALIyYDBhPRdEDwAGAAAAAAAAAgAIACOoca4xAHwAQAAA==",
    "moru-pr44-bundled-voices-light-AX3.png":
      "AAAAAIAQmCDAAAiI5eTlZOVI1WL1cuYw2QDNQMyIhAAGAnAHUA06BwSDMAdQDXoHBgM5A3kB5qDNHM0c8sB4AQ==",
    "moru-pr44-bundled-voices-light-M.png":
      "AAAAAIAAmCCCAMwA1ADQoNSA5oAJIlAMUAwkAlAMUAU0A1ANWAcyh1ANGAcAAAAAAAAAAAAAAAPkAMFkyGhgAA==",
    "moru-pr50-session-empty-home-light-AX3.png":
      "AAAEAQcADwA8gDjg3mLGYfBx+eD5gO2A1oDWgApgalFLAUOnakla0SQiBoAGAAaAOyAzOTCEOaTkmuTb5NvpIA==",
    "moru-pr50-session-empty-home-light-M.png":
      "AAAEAQcADwA8gDjgcOBw8HDxeOD8wMyAzwDWAAEgdAFgAWADAAAAAACAAwADMA1IPcCxsgaTD4fkyuTb5MvJJA==",
    "moru-pr50-session-empty-routine-light-AX3.png":
      "AAAAAAAACADAAMQA5AA4AABABgAGAAaAOyA7ODKEMKZVGFWQe7B7sIU+Hscax4E+4AAAAAAAUSQsymzbrFrSJA==",
    "moru-pr50-session-empty-routine-light-M.png":
      "AAAAAAAAIACAAMgAyAAwAAAAAAAAAAMgDwANSFigGCYGk4MCwAAAAAAAAAAAAAAAAAAAAAAAUSQsymzbrFrSJA==",
    "moru-pr52-history-streak-light-AX3.png":
      "AAAAAAAACADgAOQA1APYAMFkwSTANMC0xRTAdMIkwjTIzMjMyMzI0MjQyMzIxMgEyATIBOAAyiLOCmTLrcvZJA==",
    "moru-pr52-history-streak-light-M.png":
      "AAAAAAAAIADAAMgCwADaFMwY3JjEBEgAoALiBDhwMXFxYTFhAgDAAKAgFwBGASFBVVVvcM9w9zD1GGTLpcvSFA==",
    "moru-pr52-regular-completion-light-AX3.png":
      "AQAKAQ8EZghyKXKpclFzUPvg8PBw4HhBPQAtSg8iDgJOWHO4AAKSIASALIiMjB6iOaMYs/ZA5ADJZMlk9oCyAg==",
    "moru-pr52-regular-completion-light-M.png":
      "AQAKAQ8AHgA8wHjgcPBw8PDw+UB9QHygPwA/AAMGf5ErUYAEAwAGghBAYMBxwHAgCADAIAaCBoPpaMDEwMggAw==",
    "moru-pr52-trial-completion-light-AX3.png":
      "AQAKAR8EbwhiKXOpcrByMPWQ8PBwYHhBPQAtSg8iDgJOWHO4AAJEQBqAGgAfOB0gHSQAF3AB5ADJZMls9oCgAg==",
    "moru-pr52-trial-completion-light-M.png":
      "AQAKAQ8AHgA8wHjgcPBw8PDw+UB9QH6APwA/AAMGf5Eq0QAAByAHAAOAAEAAAAAAAAAAAQAAAAPgAMTEwMggAw==",
    "moru-pr52-weekly-comparison-light-AX3.png":
      "AAAAAAAAAAAAAAAAAAAAAOAIxQTMFMxE2KTcpMBc3iTeZM1MzEzANMzMzozchNkk2STikAAAAAAAAAAAAAAAAA==",
    "moru-pr52-weekly-comparison-light-M.png":
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMSA8zDjOOK42ATgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
  ]
}

/// 앱 루트가 Light로 고정돼 있어(`.preferredColorScheme(.light)` 게이트) 다크 변형은 찍지 않는다.
private enum VisualVariant: CaseIterable {
  case lightMedium
  case lightAccessibility3

  var captureVariant: MoruVisualCaptureVariant {
    switch self {
    case .lightMedium:
      return .lightMedium
    case .lightAccessibility3:
      return .lightAccessibility3
    }
  }

  var filenameSuffix: String {
    captureVariant.rawValue
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
        standardDeviationMinutes: 5,
        regularityScore: 96,
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
