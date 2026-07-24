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
  func testMainScreensRenderAtReferenceAccessibilitySizes() throws {
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
        mainScreen(historyView(), selection: .record),
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
  func testHistoryAndCompletionStreakSurfacesRenderAtReferenceAccessibilitySizes() throws {
    for variant in [VisualVariant.lightMedium, .lightAccessibility3] {
      try render(
        mainScreen(historyView(), selection: .record),
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
  private func historyView() -> some View {
    let viewModel = HistoryViewModel(loadHistoryUseCase: VisualHistoryUseCase())
    viewModel.load()
    return HistoryView(viewModel: viewModel)
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
    return ProfileView(viewModel: viewModel)
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
      action: {}
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
    let baselineFilename = filename.replacingOccurrences(of: "-dark-", with: "-light-")
    let baseline = try XCTUnwrap(
      VisualBaseline.hashes[baselineFilename],
      "Missing visual baseline: \(baselineFilename)",
      file: file,
      line: line
    )
    let expectedHash = try XCTUnwrap(
      Data(base64Encoded: baseline),
      "Invalid visual baseline: \(baselineFilename)",
      file: file,
      line: line
    )
    let actualHash = try visualHash(for: image)
    XCTAssertEqual(actualHash.count, expectedHash.count, file: file, line: line)
    let distance = zip(actualHash, expectedHash).reduce(0) { result, pair in
      result + Int((pair.0 ^ pair.1).nonzeroBitCount)
    }
    XCTAssertLessThanOrEqual(
      distance,
      VisualBaseline.maximumHammingDistance,
      "Visual regression in \(filename), hash distance: \(distance), "
        + "actual hash: \(actualHash.base64EncodedString())",
      file: file,
      line: line
    )
  }

  private func visualHash(for image: UIImage) throws -> Data {
    let width = 17
    let height = 32
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    let cgImage = try XCTUnwrap(image.cgImage)
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var luminance = [Int]()
    luminance.reserveCapacity(width * height)
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let red = 299 * Int(pixels[offset])
      let green = 587 * Int(pixels[offset + 1])
      let blue = 114 * Int(pixels[offset + 2])
      luminance.append((red + green + blue) / 1_000)
    }

    var hash = Data(capacity: (width - 1) * height / 8)
    var byte: UInt8 = 0
    var bitIndex = 0
    for row in 0..<height {
      for column in 0..<(width - 1) {
        if luminance[row * width + column] > luminance[row * width + column + 1] {
          byte |= 1 << (7 - bitIndex)
        }
        bitIndex += 1
        if bitIndex == 8 {
          hash.append(byte)
          byte = 0
          bitIndex = 0
        }
      }
    }
    return hash
  }

}

private enum VisualBaseline {
  static let maximumHammingDistance = 24

  static let hashes: [String: String] = [
    "moru-pr32-final-home-light-M.png":
      "BAAWAB8AvAB4wHBg8PDw8PDw8OD4QH8AnACWAMcA5gCWCURIGTYxNzEzOcQ5cLFyhIRoAyADgiBsyGTIAAAAAA==",
    "moru-pr32-final-home-light-AX3.png":
      "BAAWAB8APADQwNBg0PDxgNUA8qD6oPSA1IDNEsWQ5JikgEBAAxIFyw0jHgceJw6iBcqNio7KkTJkyGTIAAAAAA==",
    "moru-pr32-final-routine-light-M.png":
      "AAAAACAAwADEAOAA4ATUCNgwyDDQCAAByACGAFg4yDhCEIYEWBDYOEgQgAJHAE4AAAAAAAAAESJsyGTIAAAAAA==",
    "moru-pr32-final-routine-light-AX3.png":
      "AAAAADgAxADEAOQQykDKQspg2RTZDNpk2mTAYMBgxBCoAugApMBZAN0QXGBaSERwQHCAylsA2wBkSGTIAAAAAA==",
    "moru-pr32-final-history-light-M.png":
      "AAAAACAAwALAANoUzBjcmMSEQADgAuQIGCBxcXnhOdgCAsAA5CAWAEYBVVFVUX9QdRhxUFVUVUBk2GTIAAAAAA==",
    "moru-pr32-final-history-light-AX3.png":
      "AAAIAOAA5ADUAcgEwWTBNMCkwLTBVMAkwjTDNMjMyMzIjMjQyNDIzMiEyATIBMgEYMDKAsogCYBkyGTIAAAAAA==",
    "moru-pr32-final-profile-light-M.png":
      "AAAAAAAAEADIAMgA4ABAA0AHYAe4AEADQANAA3ADYAOcAEADQoNCAyACRANyg2QDZAODAEAAEyJsyGTIAAAAAA==",
    "moru-pr32-final-profile-light-AX3.png":
      "AAAAAAAAKADAAMQA0AAYAmADYANsB2wHFYIMA0gDYANAA0UDcgPaA2kDkWBkA2wDSYNpg2EDYkNkyGTIAAAAAA==",
    "moru-pr32-final-current-routine-light-M.png":
      "AAAAAAQAwATBBHCYcph5GAYC8ITQBNAM0AzUDNSM6QzwDIIAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
    "moru-pr32-final-current-routine-light-AX3.png":
      "AAAAABAQyoLqTMpIdlByQFCAVIB1APUw4GjgcOBoyjAgInSGEIY5CgGabmZ7ZjWaPArVkvmSMlIyKiAieUYZQg==",
    "moru-pr34-home-active-routines-light-M.png":
      "AAAAABAAwgCCAlAFZANCB0ANYANgyWDJKwNQB1QHJANBBUADYAlkyGABgAIAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
    "moru-pr34-home-active-routines-light-AX3.png":
      "AAAAABaAyADIACYjSYdJh2ADVgNSA1oDCgNgGXIZUANwAWM5YTF0AQAHbYVlh2ADVANWA1IDIAtgDVADUANkAQ==",
    "moru-pr43-alarm-ring-light-M.png":
      "AAAAAAAAIiEAABAAJVglOAZYALASMAUAAAAAAAAAgEAjAyYTiGbA8ABwBAAAAAAAAADABjAHGvM4B4ACAAAAAA==",
    "moru-pr43-alarm-ring-light-AX3.png":
      "AAAAAAAAQIEEIBM2K4sqGxY2IEhEDAAEAAAAAAAAwCAGky4DKUsBIsBwAHAEAAAAAABAABAHPnM+exAHQAAAAA==",
    "moru-pr44-bundled-voices-light-M.png":
      "AAAAAMAAgACCBMkA0ADQoOSAwAAwBVAMUAR0BlANGANUDVANKANQBVQNIQMAAAAAAAAAAAABZAHBZMhkZAkAAg==",
    "moru-pr44-bundled-voices-light-AX3.png":
      "AAAAAMAAgACKDOXg5eTnYMVA1WLmMuYw2UTMQNSACwAwA3ANUg06AzCDcAdSDToDMUN4B1oNcgHJZMhkZAkAAg==",
    "moru-pr50-session-empty-home-light-M.png":
      "AACAAAADaAMAA0AAAIADAAMwDUg9QDGwBocGgwBGAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEyJsyGTIAAAAAA==",
    "moru-pr50-session-empty-home-light-AX3.png":
      "AACAACVPUpNSoyJOBgAGAAaAOyAzODKEOaZ1GX2RO7IRGh7DGsMBH0AAAAAAAQAAAAAAAAAAEiJkyGTIAAAAAA==",
    "moru-pr50-session-empty-routine-light-M.png":
      "AAAAACAAwADAACAAAAAAgAMAAxANSB2AGOIGgwaDAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAESJsyGTIAAAAAA==",
    "moru-pr50-session-empty-routine-light-AX3.png":
      "AAAAADgAxADEAOUADgAGgAaABoA7IDMoMKQ9olWYXZB7sBJYDTcZAzkjHScbLgCAAAAAAAAAEiJkyGTIAAAAAA==",
  ]
}

private enum VisualVariant: CaseIterable {
  case lightMedium
  case lightAccessibility3
  case darkMedium
  case darkAccessibility3

  var userInterfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .lightMedium, .lightAccessibility3:
      return .light
    case .darkMedium, .darkAccessibility3:
      return .dark
    }
  }

  var dynamicTypeSize: DynamicTypeSize {
    switch self {
    case .lightMedium, .darkMedium:
      return .medium
    case .lightAccessibility3, .darkAccessibility3:
      return .accessibility3
    }
  }

  var filenameSuffix: String {
    switch self {
    case .lightMedium:
      return "light-M"
    case .lightAccessibility3:
      return "light-AX3"
    case .darkMedium:
      return "dark-M"
    case .darkAccessibility3:
      return "dark-AX3"
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
