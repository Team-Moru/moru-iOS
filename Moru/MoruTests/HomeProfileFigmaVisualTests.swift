//
//  HomeProfileFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

@MainActor
final class HomeProfileFigmaVisualTests: XCTestCase {
  func testFigmaCopyContract() {
    XCTAssertEqual(HomeCopy.greeting, "좋은 아침이에요,")
    XCTAssertEqual(
      HomeCopy.encouragement,
      "오늘도 작은 루틴이 큰 변화를 만들어요."
    )
    XCTAssertEqual(HomeCopy.todayRoutine, "오늘의 루틴")
    XCTAssertEqual(HomeCopy.currentRoutine, "현재 사용 중인 루틴")
    XCTAssertEqual(HomeCopy.activeRoutines, "활성 루틴")
    XCTAssertEqual(ProfileCopy.title, "설정")
    XCTAssertEqual(ProfileCopy.voiceSettings, "음성 설정")
    XCTAssertEqual(ProfileCopy.moruVoice, "모루 말투")
  }

  func testHomeAndProfileStatesRenderDeterministicallyAtReferenceVariants() async throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_HOME_PROFILE_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-p2-\(phase)"
    )

    for state in HomeProfileCaptureState.allCases {
      for variant in MoruVisualCaptureVariant.allCases {
        let filename = "\(state.rawValue)-\(variant.rawValue).png"
        let screen = try await screen(for: state)
        let first = try MoruVisualCaptureFixture.render(
          screen,
          filename: filename,
          variant: variant,
          outputDirectory: outputDirectory
        )
        let second = try MoruVisualCaptureFixture.render(
          screen,
          filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
          variant: variant,
          outputDirectory: outputDirectory
        )

        XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
        XCTAssertEqual(first.scale, 3)
        XCTAssertEqual(first.pngData(), second.pngData())
      }
    }
  }

  private func screen(for state: HomeProfileCaptureState) async throws -> AnyView {
    switch state {
    case .homeRegular, .homeEmpty, .homeFailure, .homePartialData,
         .homeWeatherDenied, .homeLongKorean:
      return AnyView(homeScreen(for: state))
    case .homeLoading:
      return AnyView(homeScreen(for: state))
    case .profileRegular, .profileLoading, .profileFailure,
         .profileFallbackVoice, .profilePermissionOff,
         .profileResetUnavailable, .profileLongKorean:
      return AnyView(try await profileScreen(for: state))
    }
  }

  private func homeScreen(for state: HomeProfileCaptureState) -> some View {
    let loadUseCase: HomeProfileCaptureHomeUseCase
    if state == .homeFailure {
      loadUseCase = HomeProfileCaptureHomeUseCase(error: .unavailable)
    } else {
      loadUseCase = HomeProfileCaptureHomeUseCase(result: homeResult(for: state))
    }

    let weatherState: HomeWeatherState = state == .homeWeatherDenied
      ? .denied
      : .fresh(weatherSnapshot)
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: loadUseCase,
      initialWeatherState: weatherState
    )
    if state != .homeLoading {
      viewModel.load()
    }

    let home = HomeView(
      viewModel: viewModel,
      onStartRoutine: { _ in .started },
      refreshToken: 0,
      routineSettingContent: AnyView(EmptyView()),
      automaticallyLoads: false
    )

    return MainTabView(
      home: AnyView(home),
      routineSetting: RoutineSettingView(dependencies: .mock()),
      history: AnyView(EmptyView()),
      selection: .constant(.home),
      historyReloadToken: 0
    )
  }

  private func profileScreen(
    for state: HomeProfileCaptureState
  ) async throws -> some View {
    let profileUseCase: HomeProfileCaptureProfileUseCase
    if state == .profileFailure {
      profileUseCase = HomeProfileCaptureProfileUseCase(error: .unavailable)
    } else {
      profileUseCase = HomeProfileCaptureProfileUseCase(
        result: profileResult(for: state)
      )
    }
    let alarmStatus: ProfileAlarmStatus = state == .profilePermissionOff
      ? .permissionOff
      : .configured
    let viewModel = ProfileViewModel(
      profileSettingsUseCase: profileUseCase,
      voicePreviewPlayer: HomeProfileCaptureVoicePlayer(),
      alarmService: HomeProfileCaptureAlarmService(status: alarmStatus),
      resetUseCase: HomeProfileCaptureResetUseCase(),
      resetAvailability: { state != .profileResetUnavailable },
      onOpenSettings: {},
      onResetSucceeded: {}
    )

    if state != .profileLoading {
      viewModel.loadProfileSettings()
      await viewModel.refreshAlarmStatus()
    }

    return MainTabView(
      home: AnyView(EmptyView()),
      routineSetting: RoutineSettingView(dependencies: .mock()),
      history: AnyView(EmptyView()),
      profile: AnyView(
        ProfileView(
          viewModel: viewModel,
          accountSessionStore: AccountSessionStore(
            credentialStore: KeychainCredentialStore(
              service: "com.teammoru.MoruTests.profile-visual"
            ),
            accessTokenProvider: MemoryAccessTokenProvider()
          ),
          automaticallyLoads: false
        )
      ),
      selection: .constant(.my),
      historyReloadToken: 0
    )
  }

  private func homeResult(
    for state: HomeProfileCaptureState
  ) -> HomeRoutineLoadResult {
    if state == .homeEmpty {
      return HomeRoutineLoadResult(
        profile: LocalProfile(displayName: "모루"),
        todayRoutine: nil,
        manualRoutines: [],
        todayRunsByRoutineID: [:],
        streak: .empty
      )
    }

    let routine = makeRoutine(
      name: state == .homeLongKorean
        ? "몸과 마음을 천천히 깨우며 하루를 준비하는 긴 아침 루틴"
        : "기본 루틴"
    )
    let completedStepCount = state == .homePartialData ? 1 : routine.steps.count
    let run = makeRun(
      routine: routine,
      completedStepCount: completedStepCount
    )
    let activeRoutine = makeRoutine(
      id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
      name: "주말 활력 루틴"
    )

    return HomeRoutineLoadResult(
      profile: LocalProfile(
        displayName: state == .homeLongKorean
          ? "아침을 단단하게 시작하는 모루 사용자"
          : "모루"
      ),
      todayRoutine: routine,
      manualRoutines: [routine, activeRoutine],
      todayRunsByRoutineID: [routine.id: run],
      streak: RoutineStreak(
        currentDays: state == .homePartialData ? 1 : 12,
        bestDays: 18,
        completedWeekdays: state == .homePartialData
          ? [.monday]
          : [.monday, .tuesday, .wednesday, .thursday, .friday]
      )
    )
  }

  private func makeRoutine(
    id: UUID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
    name: String
  ) -> Routine {
    Routine(
      id: id,
      name: name,
      steps: [
        RoutineStep(
          id: UUID(uuidString: "31000000-0000-0000-0000-000000000001")!,
          type: .confirm,
          title: "물 한 잔 마시기",
          order: 0,
          estimatedSeconds: 60
        ),
        RoutineStep(
          id: UUID(uuidString: "31000000-0000-0000-0000-000000000002")!,
          type: .timer,
          title: "스트레칭 10분",
          order: 1,
          estimatedSeconds: 679
        ),
        RoutineStep(
          id: UUID(uuidString: "31000000-0000-0000-0000-000000000003")!,
          type: .input,
          title: "오늘의 기록 한 줄",
          order: 2,
          estimatedSeconds: 155
        ),
        RoutineStep(
          id: UUID(uuidString: "31000000-0000-0000-0000-000000000004")!,
          type: .timer,
          title: "햇빛 5분 쬐기",
          order: 3,
          estimatedSeconds: 302
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 6,
        minute: 15,
        weekdays: Weekday.allCases
      ),
      isActive: true
    )
  }

  private func makeRun(
    routine: Routine,
    completedStepCount: Int
  ) -> RoutineRun {
    let results = routine.steps.prefix(completedStepCount).map { step in
      RoutineStepResult(
        stepID: step.id,
        stepTitle: step.title,
        stepType: step.type,
        completedAt: Date(timeIntervalSince1970: 1_784_841_300),
        durationSeconds: step.estimatedSeconds
      )
    }

    return RoutineRun(
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 1_784_840_400),
      completedAt: Date(timeIntervalSince1970: 1_784_841_300),
      results: results
    )
  }

  private var weatherSnapshot: HomeWeatherSnapshot {
    HomeWeatherSnapshot(
      id: UUID(uuidString: "32000000-0000-0000-0000-000000000001")!,
      condition: .clear,
      temperatureCelsius: 26,
      latitudeE4: 375_665,
      longitudeE4: 1_269_780,
      fetchedAt: Date(timeIntervalSince1970: 1_784_841_300),
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }

  private func profileResult(
    for state: HomeProfileCaptureState
  ) -> ProfileSettingsLoadResult {
    let displayName = state == .profileLongKorean
      ? "아침을 단단하게 시작하는 모루 사용자"
      : "김모루"
    let fallbackNotice = state == .profileFallbackVoice
      ? "사용할 수 없는 목소리를 아오이(으)로 변경했어요."
      : nil
    return ProfileSettingsLoadResult(
      profile: LocalProfile(
        displayName: displayName,
        selectedVoice: .aoede
      ),
      fallbackNotice: fallbackNotice
    )
  }
}

private enum HomeProfileCaptureState: String, CaseIterable {
  case homeRegular = "home-regular"
  case homeLoading = "home-loading"
  case homeEmpty = "home-empty"
  case homeFailure = "home-failure"
  case homePartialData = "home-partial-data"
  case homeWeatherDenied = "home-weather-denied"
  case homeLongKorean = "home-long-korean"
  case profileRegular = "profile-regular"
  case profileLoading = "profile-loading"
  case profileFailure = "profile-failure"
  case profileFallbackVoice = "profile-fallback-voice"
  case profilePermissionOff = "profile-permission-off"
  case profileResetUnavailable = "profile-reset-unavailable"
  case profileLongKorean = "profile-long-korean"
}

private enum HomeProfileCaptureError: Error {
  case unavailable
  case missingResult
}

@MainActor
private final class HomeProfileCaptureHomeUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let result: HomeRoutineLoadResult?
  private let error: HomeProfileCaptureError?

  init(
    result: HomeRoutineLoadResult? = nil,
    error: HomeProfileCaptureError? = nil
  ) {
    self.result = result
    self.error = error
  }

  func execute() throws -> HomeRoutineLoadResult {
    if let error {
      throw error
    }

    guard let result else {
      throw HomeProfileCaptureError.missingResult
    }
    return result
  }
}

@MainActor
private final class HomeProfileCaptureProfileUseCase: ProfileSettingsUseCaseProtocol {
  private let result: ProfileSettingsLoadResult?
  private let error: HomeProfileCaptureError?

  init(
    result: ProfileSettingsLoadResult? = nil,
    error: HomeProfileCaptureError? = nil
  ) {
    self.result = result
    self.error = error
  }

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    if let error {
      throw error
    }

    guard let result else {
      throw HomeProfileCaptureError.missingResult
    }
    return result
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    try loadProfileSettings()
  }

  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult {
    try loadProfileSettings()
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    true
  }
}

@MainActor
private final class HomeProfileCaptureVoicePlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}

@MainActor
private final class HomeProfileCaptureAlarmService: ProfileAlarmServicing {
  let status: ProfileAlarmStatus

  init(status: ProfileAlarmStatus) {
    self.status = status
  }

  func currentStatus() async -> ProfileAlarmStatus {
    status
  }

  func requestAuthorization() async -> ProfileAlarmStatus {
    status
  }

  func retryScheduling() async -> ProfileAlarmStatus {
    status
  }

  func cancelAllAlarms() async throws {}
}

@MainActor
private final class HomeProfileCaptureResetUseCase: ResetLocalDataUseCaseProtocol {
  func execute() async throws {}
}
