#if DEBUG
import CoreLocation
import Foundation
import SwiftUI
import UIKit

@MainActor
enum MoruUITestFixture {
  static let configuration = FixtureConfiguration(arguments: ProcessInfo.processInfo.arguments)
}

@MainActor
struct MoruUITestFixtureView: View {
  let configuration: FixtureConfiguration
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    fixtureContent
      .accessibilityValue(dynamicTypeProbeValue)
      .environment(\.locale, configuration.locale)
      .environment(\.timeZone, configuration.timeZone)
      .transaction { transaction in
        if configuration.disableAnimations {
          transaction.animation = nil
        }
      }
      .onAppear {
        if configuration.disableAnimations {
          UIView.setAnimationsEnabled(false)
        }
      }
  }

  private var dynamicTypeProbeValue: String {
    if dynamicTypeSize == .medium {
      return "M"
    }
    if dynamicTypeSize == .accessibility3 {
      return "AX3"
    }
    return "unexpected"
  }

  @ViewBuilder
  private var fixtureContent: some View {
    switch configuration.fixture {
    case .launchSlow:
      LaunchStatusView()
    case .onboardingExperience:
      FixtureOnboardingSurface(step: .experience)
    case .onboardingCompletion:
      FixtureOnboardingSurface(step: .completion)
    case .trialStep:
      FixtureTrialPlayerSurface(step: FixtureData.confirmStep)
    case .trialInput:
      FixtureTrialPlayerSurface(step: FixtureData.inputStep)
    case .trialComplete:
      FixtureCompletionSurface(configuration: .trialHomeOnly)
    case .homeWeatherFresh:
      FixtureHomeSurface(now: configuration.clock)
    case .profileRoot:
      FixtureProfileSurface(status: .configured)
    case .alarmPermissionOff:
      FixtureProfileSurface(status: .permissionOff)
    case .voiceSelection:
      FixtureProfileSurface(status: .configured)
    case .notificationDowngrade:
      FixtureProfileSurface(status: .configured)
    case .regularComplete:
      FixtureCompletionSurface(configuration: .regularRecordAndHome)
    case .historyDashboard, .historyWeekly:
      FixtureHistorySurface(
        now: configuration.clock,
        timeZone: configuration.timeZone,
        destination: nil
      )
    case .historyDetail:
      FixtureHistorySurface(
        now: configuration.clock,
        timeZone: configuration.timeZone,
        destination: .runDetail(FixtureData.historyRunID)
      )
    case .componentsDefault:
      MoruCommonComponentsPreviewHost()
    case .absenceAudit:
      FixtureProfileSurface(status: .configured)
    }
  }
}

struct FixtureConfiguration {
  let fixture: FixtureName
  let clock: Date
  let locale: Locale
  let timeZone: TimeZone
  let disableAnimations: Bool

  init?(arguments: [String]) {
    guard let fixtureName = Self.value(for: "-moruUITestFixture", in: arguments) else {
      return nil
    }
    guard let fixture = FixtureName(rawValue: fixtureName),
          let clockText = Self.value(for: "-moruUITestClockMillis", in: arguments),
          let clockMillis = Int64(clockText),
          let localeIdentifier = Self.value(for: "-moruUITestLocale", in: arguments),
          let timeZoneIdentifier = Self.value(for: "-moruUITestTimeZone", in: arguments),
          let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
      assertionFailure("Invalid Moru UI test fixture launch arguments.")
      return nil
    }


    self.fixture = fixture
    self.clock = Date(timeIntervalSince1970: Double(clockMillis) / 1_000)
    self.locale = Locale(identifier: localeIdentifier)
    self.timeZone = timeZone
    self.disableAnimations = arguments.contains("-moruUITestDisableAnimations")
  }


  private static func value(for name: String, in arguments: [String]) -> String? {
    let indexes = arguments.indices.filter { arguments[$0] == name }
    guard indexes.count == 1,
          let index = indexes.first,
          index < arguments.index(before: arguments.endIndex) else {
      return nil
    }

    let value = arguments[arguments.index(after: index)]
    return value.hasPrefix("-") ? nil : value
  }
}

enum FixtureName: String, CaseIterable {
  case launchSlow = "launch-slow"
  case onboardingExperience = "onboarding-experience"
  case onboardingCompletion = "onboarding-completion"
  case trialStep = "trial-step"
  case trialInput = "trial-input"
  case trialComplete = "trial-complete"
  case homeWeatherFresh = "home-weather-fresh"
  case profileRoot = "profile-root"
  case alarmPermissionOff = "alarm-permission-off"
  case voiceSelection = "voice-selection"
  case notificationDowngrade = "notification-downgrade"
  case regularComplete = "regular-complete"
  case historyDashboard = "history-dashboard"
  case historyWeekly = "history-weekly"
  case historyDetail = "history-detail"
  case componentsDefault = "components-default"
  case absenceAudit = "absence-audit"
}

@MainActor
private struct FixtureOnboardingSurface: View {
  let step: OnboardingStep

  var body: some View {
    OnboardingFlowView(viewModel: FixtureData.onboardingViewModel(step: step))
  }
}
@MainActor
private struct FixtureTrialPlayerSurface: View {
  private let viewModel: RoutinePlayerViewModel

  init(step: RoutineStep) {
    let routine = FixtureData.routine(with: [step])
    viewModel = RoutinePlayerViewModel(
      request: TrialRoutineExecutionRequest(routineID: routine.id),
      resolver: FixtureRoutineResolver(routine: routine),
      finalizer: FixtureTrialFinalizer(),
      presentationToken: FixtureData.routineID,
      onEvent: { _, _ in }
    )
  }

  var body: some View {
    RoutinePlayerView(viewModel: viewModel)
  }
}


@MainActor
private struct FixtureCompletionSurface: View {
  let configuration: RoutineCompletionActionConfiguration

  var body: some View {
    RoutineFinishedView(
      routineName: FixtureData.routine.name,
      completionRate: 100,
      completedStepCount: FixtureData.routine.steps.count,
      skippedStepCount: 0,
      actionConfiguration: configuration,
      onAction: { _ in },
      isActionDisabled: false
    )
  }
}

@MainActor
private struct FixtureHomeSurface: View {
  @State private var selection: MoruTabItem = .home
  private let now: Date
  private let viewModel: HomeViewModel

  init(now: Date) {
    self.now = now
    viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: FixtureHomeLoadUseCase(),
      weatherRepository: FixtureHomeWeatherRepository(),
      weatherService: FixtureHomeWeatherService(snapshot: FixtureData.weatherSnapshot(now: now)),
      now: { now }
    )
  }

  var body: some View {
    MainTabView(
      home: AnyView(
        HomeView(
          viewModel: viewModel,
          onStartRoutine: { _ in .started },
          refreshToken: 0,
          routineSettingContent: AnyView(RoutineSettingView(dependencies: .homePreview))
        )
      ),
      routineSetting: RoutineSettingView(dependencies: .homePreview),
      history: AnyView(
        FixtureHistorySurface(
          now: now,
          timeZone: TimeZone(identifier: "Asia/Seoul")!,
          destination: nil
        )
      ),
      profile: AnyView(FixtureProfileSurface(status: .configured)),
      selection: $selection,
      historyReloadToken: 0
    )
    .task {
      viewModel.requestWeather()
    }
  }
}

@MainActor
private struct FixtureProfileSurface: View {
  private let viewModel: ProfileViewModel

  init(status: ProfileAlarmStatus) {
    viewModel = ProfileViewModel(
      profileSettingsUseCase: FixtureProfileSettingsUseCase(),
      voicePreviewPlayer: FixtureVoicePreviewPlayer(),
      alarmStatusProvider: { status },
      resetPerformer: FixtureProfileResetPerformer(),
      onOpenSettings: {},
      onRetryAlarmRepair: {}
    )
  }

  var body: some View {
    ProfileView(viewModel: viewModel)
  }
}

@MainActor
private struct FixtureHistorySurface: View {
  let now: Date
  let timeZone: TimeZone
  let destination: HistoryDestination?

  var body: some View {
    HistoryView(
      viewModel: HistoryViewModel(loadHistoryUseCase: FixtureHistoryLoadUseCase(
        now: now,
        timeZone: timeZone
      )),
      destination: .constant(destination)
    )
  }
}


@MainActor
private final class FixtureSuggestionService: RoutineSuggestionService {
  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    FixtureData.routine
  }
}

@MainActor
private final class FixtureCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  func execute(_ request: CompleteOnboardingRequest) async throws -> CompleteOnboardingResult {
    CompleteOnboardingResult(profile: FixtureData.profile, routine: FixtureData.routine)
  }
}
@MainActor
private final class FixtureRoutineResolver: ResolveRoutineExecutionUseCaseProtocol {
  private let routine: Routine

  init(routine: Routine) {
    self.routine = routine
  }

  func execute(_ request: ResolveRoutineExecutionRequest) -> RoutineExecutionResolution {
    request.routineID == routine.id ? .available(routine) : .notFound
  }
}

@MainActor
private final class FixtureTrialFinalizer: TrialRoutineFinalizing {
  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
    makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      endedEarly: false
    )
  }
}


@MainActor
private final class FixtureHomeLoadUseCase: LoadHomeRoutinesUseCaseProtocol {
  func execute() throws -> HomeRoutineLoadResult {
    HomeRoutineLoadResult(
      profile: FixtureData.profile,
      todayRoutine: FixtureData.routine,
      manualRoutines: [FixtureData.routine],
      todayRun: nil,
      streak: HomeRoutineStreak(
        currentDays: 4,
        bestDays: 12,
        completedWeekdays: [.monday, .tuesday, .wednesday, .thursday]
      )
    )
  }
}

@MainActor
private final class FixtureHomeWeatherRepository: HomeWeatherRepository {
  func cachedWeather() throws -> HomeWeatherSnapshot? {
    nil
  }

  func saveWeather(_ snapshot: HomeWeatherSnapshot) throws {}

  func eraseCachedWeather() throws {}
}

@MainActor
private final class FixtureHomeWeatherService: HomeWeatherService {
  let snapshot: HomeWeatherSnapshot

  init(snapshot: HomeWeatherSnapshot) {
    self.snapshot = snapshot
  }

  var authorizationStatus: HomeWeatherAuthorizationStatus {
    .authorized
  }

  var isLocationServiceEnabled: Bool {
    true
  }

  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus {
    .authorized
  }

  func currentLocation() async throws -> CLLocation {
    CLLocation(latitude: 37.5665, longitude: 126.9780)
  }

  func weatherSnapshot(for location: CLLocation) async throws -> HomeWeatherSnapshot {
    snapshot
  }

  func cancelCurrentLocationRequests() {}
}

@MainActor
private final class FixtureProfileSettingsUseCase: ProfileSettingsUseCaseProtocol {
  private let result: ProfileSettingsLoadResult

  init() {
    result = ProfileSettingsLoadResult(
      profile: FixtureData.profile,
      settings: LocalSettingsSnapshot(
        id: FixtureData.profile.id,
        profileID: FixtureData.profile.id,
        voiceMigrationState: .resolved,
        originalVoiceID: nil,
        resolvedVoiceID: VoiceProfile.yuna.id,
        migrationUpdatedAt: FixtureData.date,
        schemaMigrationMarker: .v2Resolved
      )
    )
  }

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    result
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func selectVoice(voiceID: String) throws -> ProfileSettingsLoadResult {
    result
  }

  func acknowledgeVoiceNotice() throws -> ProfileSettingsLoadResult {
    result
  }

  func retryVoiceResolution() throws -> ProfileSettingsLoadResult {
    result
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    VoiceProfile.localVoices.contains(voice)
  }
}

@MainActor
private final class FixtureVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}

private final class FixtureProfileResetPerformer: ProfileLocalResetPerforming {
  func availability() -> LocalResetAvailability {
    .available
  }

  func reset() async throws {}
}

@MainActor
private final class FixtureHistoryLoadUseCase: LoadHistoryUseCaseProtocol {
  private let overview: HistoryOverview

  init(now: Date, timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ko-KR")
    calendar.timeZone = timeZone
    overview = FixtureData.historyOverview(now: now, calendar: calendar)
  }

  func load() throws -> HistoryOverview {
    overview
  }
}

private enum FixtureData {
  static let date = Date(timeIntervalSince1970: 1_784_325_600)
  static let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  static let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  static let confirmStepID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  static let inputStepID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
  static let historyRunID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

  static let confirmStep = RoutineStep(
    id: confirmStepID,
    type: .confirm,
    title: "잠자리 정리하기",
    instruction: "정리가 끝났으면 말해주세요.",
    order: 0,
    estimatedSeconds: 60
  )

  static let inputStep = RoutineStep(
    id: inputStepID,
    type: .input,
    title: "오늘의 다짐",
    instruction: "어떤 하루를 만들고 싶은지 말해주세요.",
    order: 1,
    estimatedSeconds: 60
  )

  static let routine = Routine(
    id: routineID,
    name: "아침 활력 루틴",
    summary: "하루를 가볍게 시작하는 루틴",
    goalTags: ["energy"],
    steps: [confirmStep, inputStep],
    alarmSchedule: AlarmSchedule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
      hour: 7,
      minute: 0,
      weekdays: Weekday.weekdays,
      isEnabled: true
    ),
    isActive: true,
    createdAt: date,
    updatedAt: date
  )
  static func routine(with steps: [RoutineStep]) -> Routine {
    var result = routine
    result.steps = steps
    return result
  }

  static let profile = LocalProfile(
    id: profileID,
    displayName: "모루 사용자",
    selectedVoice: .yuna,
    createdAt: date,
    updatedAt: date
  )

  @MainActor
  static func onboardingViewModel(step: OnboardingStep) -> OnboardingViewModel {
    var draft = OnboardingDraft()
    draft.selectedGoalTags = ["energy"]
    draft.previewRoutine = routine

    return OnboardingViewModel(
      draft: draft,
      step: step,
      routineSuggestionService: FixtureSuggestionService(),
      completeOnboardingUseCase: FixtureCompleteOnboardingUseCase(),
      onCompleted: { _ in }
    )
  }

  static func weatherSnapshot(now: Date) -> HomeWeatherSnapshot {
    HomeWeatherSnapshot(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
      condition: .clear,
      temperatureCelsius: 24,
      latitudeE4: 375_665,
      longitudeE4: 1_269_780,
      fetchedAt: now,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }

  static func historyOverview(now: Date, calendar: Calendar) -> HistoryOverview {
    let day = calendar.startOfDay(for: now)
    let completedAt = calendar.date(byAdding: .minute, value: 10, to: day)!
    let historyRun = HistoryRun(
      id: historyRunID,
      routineName: routine.name,
      startedAt: day,
      completedAt: completedAt,
      status: .completed,
      completionRate: 1,
      stepResults: [
        HistoryStepResult(
          stepID: confirmStepID,
          stepTitle: confirmStep.title,
          isCompleted: true,
          isSkipped: false,
          transcript: nil
        ),
        HistoryStepResult(
          stepID: inputStepID,
          stepTitle: inputStep.title,
          isCompleted: true,
          isSkipped: false,
          transcript: "오늘도 차분하게 시작할게요."
        )
      ]
    )
    let weekStart = calendar.date(byAdding: .day, value: -5, to: day)!
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
    let dailyCompletionRates = (0..<7).map { offset in
      HistoryDailyCompletion(
        date: calendar.date(byAdding: .day, value: offset, to: weekStart)!,
        completionRate: offset == 5 ? 1 : 0
      )
    }

    return HistoryOverview(
      calendar: calendar,
      recentDays: [
        HistoryDaySummary(
          date: day,
          completedRunCount: 1,
          totalRunCount: 1,
          completionRate: 1,
          runs: [historyRun]
        )
      ],
      week: HistoryWeekReport(
        weekStartDate: weekStart,
        weekEndDate: weekEnd,
        completedRunCount: 1,
        totalRunCount: 1,
        completionRate: 1,
        dailyCompletionRates: dailyCompletionRates
      ),
      wakeMetrics: .calculated(
        observationCount: 4,
        averageWakeMinute: 420,
        averageDeviationMinutes: 5,
        consistencyScore: 92
      ),
      monthlyHeatmap: HistoryMonthlyHeatmap(
        monthStartDate: day,
        days: [HistoryHeatmapDay(id: "fixture-day", date: day, completionRate: 1)]
      )
    )
  }
}
#endif
