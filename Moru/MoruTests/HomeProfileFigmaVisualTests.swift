//
//  HomeProfileFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import UIKit
import Vision
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
    XCTAssertEqual(ProfileCopy.account, "계정")
    XCTAssertEqual(ProfileCopy.socialLogin, "소셜 로그인")
    XCTAssertEqual(ProfileCopy.dataManagement, "데이터 관리")
    XCTAssertEqual(ProfileCopy.resetLocalData, "로컬 데이터 초기화")
    XCTAssertEqual(ProfileCopy.support, "고객 지원")
    XCTAssertEqual(ProfileCopy.privacyPolicy, "개인정보처리방침")
    XCTAssertEqual(ProfileCopy.termsOfService, "이용약관")
    XCTAssertEqual(ProfileCopy.contact, "문의하기")
    XCTAssertEqual(ProfileCopy.contactEmail, "mmoru2026@gmail.com")
  }

  func testGreetingCopyUsesDesignPeriodsAndPreservesEveningPunctuation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let cases: [(Int, Int, HomeGreetingPeriod, String)] = [
      (5, 59, .evening, "편안한 밤 되세요!"),
      (6, 0, .morning, "좋은 아침이에요"),
      (11, 59, .morning, "좋은 아침이에요"),
      (12, 0, .afternoon, "오늘 하루도 힘내봐요"),
      (17, 59, .afternoon, "오늘 하루도 힘내봐요"),
      (18, 0, .evening, "편안한 밤 되세요!"),
    ]

    for (hour, minute, expectedPeriod, expectedText) in cases {
      let date = try XCTUnwrap(
        calendar.date(
          from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 13,
            hour: hour,
            minute: minute
          )
        )
      )
      let period = HomeGreetingPeriod(date: date, calendar: calendar)

      XCTAssertEqual(period, expectedPeriod)
      XCTAssertEqual(period.text, expectedText)
    }

    XCTAssertEqual(
      HomeGreetingPeriod.evening.greeting(userName: " 모루 "),
      "편안한 밤 되세요!\n모루님"
    )
  }

  func testProfileSupportLinksReuseValidatedPolicyURLsAndExactContactEmail() {
    let links = ProfileSupportLinks(
      policyConfiguration: AccountEntryPolicyConfiguration(
        infoDictionary: [
          "MoruPrivacyPolicyURL": "https://team-moru.github.io/privacy",
          "MoruTermsOfServiceURL": "https://team-moru.github.io/terms",
        ]
      )
    )

    XCTAssertEqual(
      links.privacyPolicyURL?.absoluteString,
      "https://team-moru.github.io/privacy"
    )
    XCTAssertEqual(
      links.termsOfServiceURL?.absoluteString,
      "https://team-moru.github.io/terms"
    )
    XCTAssertEqual(
      links.contactURL.absoluteString,
      "mailto:mmoru2026@gmail.com"
    )
    XCTAssertEqual(
      ProfileView.privacyPolicyAccessibilityIdentifier,
      "profile.support.privacy"
    )
    XCTAssertEqual(
      ProfileView.termsOfServiceAccessibilityIdentifier,
      "profile.support.terms"
    )
    XCTAssertEqual(
      ProfileView.contactAccessibilityIdentifier,
      "profile.support.contact"
    )
  }

  func testProfileSupportLinksKeepContactAvailableWhenPoliciesAreMisconfigured() {
    let links = ProfileSupportLinks(
      policyConfiguration: AccountEntryPolicyConfiguration(
        infoDictionary: [
          "MoruPrivacyPolicyURL": "https://example.com/privacy",
          "MoruTermsOfServiceURL": "http://example.com/terms",
        ]
      )
    )

    XCTAssertNil(links.privacyPolicyURL)
    XCTAssertNil(links.termsOfServiceURL)
    XCTAssertEqual(
      links.contactURL.absoluteString,
      "mailto:mmoru2026@gmail.com"
    )
  }

  func testProfileSupportRowsUseStableOrderCopyAndAccessibilityContracts() {
    XCTAssertEqual(
      ProfileSupportLinkDestination.allCases,
      [.privacyPolicy, .termsOfService, .contact]
    )
    XCTAssertEqual(
      ProfileSupportLinkDestination.allCases.map(\.title),
      ["개인정보처리방침", "이용약관", "문의하기"]
    )
    XCTAssertEqual(
      ProfileSupportLinkDestination.allCases.map {
        ProfileView.supportAccessibilityIdentifier(for: $0)
      },
      [
        "profile.support.privacy",
        "profile.support.terms",
        "profile.support.contact",
      ]
    )
    XCTAssertEqual(
      ProfileSupportLinkDestination.privacyPolicy.accessibilityLabel,
      "개인정보처리방침"
    )
    XCTAssertEqual(
      ProfileSupportLinkDestination.privacyPolicy.accessibilityHint,
      "웹 브라우저에서 개인정보처리방침을 엽니다."
    )
  }

  func testProfileSupportLinkOpenerReportsMisconfigurationWithoutOpening() async {
    var openedURLs: [URL] = []
    let opener = ProfileSupportLinkOpener { url in
      openedURLs.append(url)
      return true
    }

    let alert = await opener.open(destination: .privacyPolicy, url: nil)

    XCTAssertTrue(openedURLs.isEmpty)
    XCTAssertEqual(
      alert,
      ProfileSupportLinkAlert(
        destination: .privacyPolicy,
        reason: .misconfigured
      )
    )
    XCTAssertEqual(alert?.title, "링크를 열 수 없어요")
    XCTAssertEqual(
      alert?.message,
      "주소 설정을 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
    )
  }

  func testProfileSupportLinkOpenerReportsSystemOpenFailure() async throws {
    let privacyURL = try XCTUnwrap(
      URL(string: "https://team-moru.github.io/privacy")
    )
    var openedURLs: [URL] = []
    let opener = ProfileSupportLinkOpener { url in
      openedURLs.append(url)
      return false
    }

    let alert = await opener.open(
      destination: .privacyPolicy,
      url: privacyURL
    )

    XCTAssertEqual(openedURLs, [privacyURL])
    XCTAssertEqual(alert?.reason, .openFailed)
    XCTAssertEqual(
      alert?.message,
      "개인정보처리방침을 열지 못했어요. 잠시 후 다시 시도해 주세요."
    )
  }

  func testProfileSupportLinkOpenerReturnsNoAlertAfterSuccess() async throws {
    let termsURL = try XCTUnwrap(
      URL(string: "https://team-moru.github.io/terms")
    )
    let opener = ProfileSupportLinkOpener { _ in true }

    let alert = await opener.open(
      destination: .termsOfService,
      url: termsURL
    )

    XCTAssertNil(alert)
  }

  func testLoadingAndFailedProfilesRenderPrivacyRow() throws {
    for shouldFail in [false, true] {
      let profileUseCase = shouldFail
        ? HomeProfileCaptureProfileUseCase(error: .unavailable)
        : HomeProfileCaptureProfileUseCase(
          result: ProfileSettingsLoadResult(
            profile: LocalProfile(displayName: "김모루", selectedVoice: .aoede),
            fallbackNotice: nil
          )
        )
      let viewModel = makeProfileViewModel(profileUseCase: profileUseCase)
      if shouldFail {
        viewModel.loadProfileSettings()
      }

      let renderedText = try renderRecognizedText(
        ProfileView(
          viewModel: viewModel,
          accountSessionStore: makeAccountSessionStore(),
          automaticallyLoads: false,
          supportLinks: profileSupportLinks
        ),
        filename: "profile-support-\(shouldFail ? "failed" : "loading").png"
      )

      XCTAssertTrue(
        renderedText.contains(ProfileCopy.privacyPolicy),
        "\(shouldFail ? "failed" : "loading") 렌더에 개인정보처리방침 행이 있어야 합니다. "
          + "인식된 문구: \(renderedText)"
      )
    }
  }

  func testGuestAndSignedInContentProfilesRenderOneCompleteSupportSection() throws {
    for isSignedIn in [false, true] {
      let accountSessionStore = makeAccountSessionStore()
      if isSignedIn {
        try accountSessionStore.establishSession(
          credentials: AccountCredentials(
            memberID: 68,
            accessToken: "support-access-token",
            refreshToken: "support-refresh-token",
            onboardingCompleted: true,
            provider: .kakao
          )
        )
      }
      let viewModel = makeProfileViewModel(
        profileUseCase: HomeProfileCaptureProfileUseCase(
          result: ProfileSettingsLoadResult(
            profile: LocalProfile(displayName: "김모루", selectedVoice: .aoede),
            fallbackNotice: nil
          )
        )
      )
      viewModel.loadProfileSettings()

      let renderedText = try renderRecognizedText(
        ProfileView(
          viewModel: viewModel,
          accountSessionStore: accountSessionStore,
          automaticallyLoads: false,
          supportLinks: profileSupportLinks
        ),
        filename: "profile-support-\(isSignedIn ? "signed-in" : "guest").png"
      )

      let supportTitles = [
        ProfileCopy.privacyPolicy,
        ProfileCopy.termsOfService,
        ProfileCopy.contact,
      ]
      XCTAssertTrue(
        supportTitles.allSatisfy(renderedText.contains),
        "\(isSignedIn ? "signed-in" : "guest") content 렌더에 고객 지원 3개 행이 있어야 합니다. "
          + "인식된 문구: \(renderedText)"
      )
    }
  }

  func testWeatherCardHeightContract() {
    XCTAssertEqual(HomeFigmaLayout.weatherCardHeight, 84)
    XCTAssertEqual(HomeFigmaLayout.actionableWeatherCardHeight, 104)
  }

  func testSignedInProfileRendersConnectionStatusAtReferenceViewport() throws {
    let credentialStore = HomeProfileCaptureCredentialStore()
    let accountSessionStore = AccountSessionStore(
      credentialStore: credentialStore,
      accessTokenProvider: MemoryAccessTokenProvider()
    )
    try accountSessionStore.establishSession(
      credentials: AccountCredentials(
        memberID: 68,
        accessToken: "capture-access-token",
        refreshToken: "capture-refresh-token",
        onboardingCompleted: true,
        provider: .kakao
      )
    )

    let viewModel = ProfileViewModel(
      profileSettingsUseCase: HomeProfileCaptureProfileUseCase(
        result: ProfileSettingsLoadResult(
          profile: LocalProfile(displayName: "김모루", selectedVoice: .aoede),
          fallbackNotice: nil
        )
      ),
      voicePreviewPlayer: HomeProfileCaptureVoicePlayer(),
      alarmService: HomeProfileCaptureAlarmService(status: .configured),
      resetUseCase: HomeProfileCaptureResetUseCase(),
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
    viewModel.loadProfileSettings()

    let screen = MainTabView(
      home: AnyView(EmptyView()),
      routineSetting: RoutineSettingView(dependencies: .mock()),
      history: AnyView(EmptyView()),
      profile: AnyView(
        ProfileView(
          viewModel: viewModel,
          accountSessionStore: accountSessionStore,
          automaticallyLoads: false
        )
      ),
      selection: .constant(.my),
      historyReloadToken: 0
    )
    let image = try MoruVisualCaptureFixture.render(
      screen,
      filename: "profile-kakao-connected-light-M.png",
      variant: .lightMedium,
      outputDirectory: URL(
        fileURLWithPath: "/private/tmp/moru-profile-social-connection"
      )
    )

    XCTAssertEqual(image.size, CGSize(width: 393, height: 852))
  }

  func testMoruVoiceSettingsPageRendersAtReferenceViewport() throws {
    let viewModel = ProfileViewModel(
      profileSettingsUseCase: HomeProfileCaptureProfileUseCase(
        result: ProfileSettingsLoadResult(
          profile: LocalProfile(displayName: "김모루", selectedVoice: .aoede),
          fallbackNotice: nil
        )
      ),
      voicePreviewPlayer: HomeProfileCaptureVoicePlayer(),
      alarmService: HomeProfileCaptureAlarmService(status: .configured),
      resetUseCase: HomeProfileCaptureResetUseCase(),
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
    viewModel.loadProfileSettings()

    let image = try MoruVisualCaptureFixture.render(
      NavigationStack {
        MoruVoiceSettingsView(
          profileViewModel: viewModel,
          accountServerViewModel: AccountServerSettingsViewModel(),
          onOpenDeviceVoiceSelection: {},
          onOpenServerVoiceSelection: {}
        )
      },
      filename: "moru-voice-settings-light-M.png",
      variant: .lightMedium,
      outputDirectory: URL(
        fileURLWithPath: "/private/tmp/moru-voice-settings"
      )
    )

    XCTAssertEqual(image.size, CGSize(width: 393, height: 852))
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
        try await assertDeterministicCapture(
          state: state,
          variant: variant,
          outputDirectory: outputDirectory
        )
      }
    }
  }

  func testWeatherAttributionRendersAtSmallWidthInLightAndDark() async throws {
    let outputDirectory = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment[
        "MORU_WEATHER_ATTRIBUTION_CAPTURE_DIR"
      ] ?? "/private/tmp/moru-weather-attribution"
    )
    let configurations: [(name: String, value: MoruVisualCaptureConfiguration)] = [
      (
        name: "light",
        value: MoruVisualCaptureConfiguration(
          size: CGSize(width: 320, height: 420),
          scale: 2
        )
      ),
      (
        name: "dark",
        value: MoruVisualCaptureConfiguration(
          size: CGSize(width: 320, height: 420),
          scale: 2,
          colorScheme: .dark,
          userInterfaceStyle: .dark
        )
      ),
    ]

    for configuration in configurations {
      for variant in MoruVisualCaptureVariant.allCases {
        let image = try MoruVisualCaptureFixture.render(
          weatherAttributionCardScreen,
          filename: "weather-\(configuration.name)-\(variant.rawValue).png",
          variant: variant,
          outputDirectory: outputDirectory,
          configuration: configuration.value
        )

        XCTAssertEqual(image.size, configuration.value.size)
        XCTAssertEqual(image.scale, configuration.value.scale)
      }
    }
  }

  private var weatherAttributionCardScreen: some View {
    HomeWeatherCard(
      state: .fresh(
        HomeWeatherContent(
          snapshot: weatherSnapshot,
          attribution: weatherAttribution
        )
      ),
      requestWeather: {}
    )
    .padding(MoruPilotSpacing.twenty)
    .frame(
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .top
    )
    .background(AppColor.babyBlue50)
  }

  private func assertDeterministicCapture(
    state: HomeProfileCaptureState,
    variant: MoruVisualCaptureVariant,
    outputDirectory: URL
  ) async throws {
    let screen = try await screen(for: state)
    try autoreleasepool {
      let filename = "\(state.rawValue)-\(variant.rawValue).png"
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
      : .fresh(
        HomeWeatherContent(
          snapshot: weatherSnapshot,
          attribution: weatherAttribution
        )
      )
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
      completedStepCount: completedStepCount,
      skippedStepIndex: state == .homePartialData ? 1 : nil
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
    completedStepCount: Int,
    skippedStepIndex: Int? = nil
  ) -> RoutineRun {
    var results = routine.steps.prefix(completedStepCount).map { step in
      RoutineStepResult(
        stepID: step.id,
        stepTitle: step.title,
        stepType: step.type,
        completedAt: Date(timeIntervalSince1970: 1_784_841_300),
        durationSeconds: step.estimatedSeconds
      )
    }
    if let skippedStepIndex,
       routine.steps.indices.contains(skippedStepIndex) {
      let step = routine.steps[skippedStepIndex]
      results.append(
        RoutineStepResult(
          stepID: step.id,
          stepTitle: step.title,
          stepType: step.type,
          skipped: true
        )
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
      dailyHighCelsius: 29,
      dailyLowCelsius: 20,
      latitudeE4: 375_665,
      longitudeE4: 1_269_780,
      fetchedAt: Date(timeIntervalSince1970: 1_784_841_300),
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }

  private var weatherAttribution: HomeWeatherAttribution {
    return HomeWeatherAttribution(
      serviceName: "Apple Weather",
      combinedMarkLightData: weatherAttributionMarkData(color: .black),
      combinedMarkDarkData: weatherAttributionMarkData(color: .white),
      legalPageURL: URL(
        string: "https://weatherkit.apple.com/legal-attribution.html"
      )!
    )
  }

  private func weatherAttributionMarkData(color: UIColor) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: 84, height: 20),
      format: format
    )

    return renderer.pngData { _ in
      let text = " Weather" as NSString
      text.draw(
        at: CGPoint(x: 1, y: 1),
        withAttributes: [
          .font: UIFont.systemFont(ofSize: 14, weight: .medium),
          .foregroundColor: color,
        ]
      )
    }
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

  private var profileSupportLinks: ProfileSupportLinks {
    ProfileSupportLinks(
      policyConfiguration: AccountEntryPolicyConfiguration(
        infoDictionary: [
          "MoruPrivacyPolicyURL": "https://team-moru.github.io/privacy",
          "MoruTermsOfServiceURL": "https://team-moru.github.io/terms",
        ]
      )
    )
  }

  private func makeProfileViewModel(
    profileUseCase: any ProfileSettingsUseCaseProtocol
  ) -> ProfileViewModel {
    ProfileViewModel(
      profileSettingsUseCase: profileUseCase,
      voicePreviewPlayer: HomeProfileCaptureVoicePlayer(),
      alarmService: HomeProfileCaptureAlarmService(status: .configured),
      resetUseCase: HomeProfileCaptureResetUseCase(),
      resetAvailability: { true },
      onOpenSettings: {},
      onResetSucceeded: {}
    )
  }

  private func makeAccountSessionStore() -> AccountSessionStore {
    AccountSessionStore(
      credentialStore: HomeProfileCaptureCredentialStore(),
      accessTokenProvider: MemoryAccessTokenProvider()
    )
  }

  private func renderRecognizedText<Content: View>(
    _ content: Content,
    filename: String
  ) throws -> String {
    let image = try MoruVisualCaptureFixture.render(
      content,
      filename: filename,
      variant: .lightMedium,
      outputDirectory: URL(
        fileURLWithPath: "/private/tmp/moru-profile-support-fallback"
      ),
      configuration: MoruVisualCaptureConfiguration(
        size: CGSize(width: 393, height: 1_200),
        scale: 3
      )
    )
    let cgImage = try XCTUnwrap(image.cgImage)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: cgImage).perform([request])

    return (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }
      .joined()
      .replacingOccurrences(of: " ", with: "")
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

private final class HomeProfileCaptureCredentialStore:
  CredentialStore,
  @unchecked Sendable {
  private var credentials: AccountCredentials?

  func load() throws -> AccountCredentials? {
    credentials
  }

  func save(_ credentials: AccountCredentials) throws {
    self.credentials = credentials
  }

  func remove() throws {
    credentials = nil
  }
}
