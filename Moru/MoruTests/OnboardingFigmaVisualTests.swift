//
//  OnboardingFigmaVisualTests.swift
//  MoruTests
//
//  Created by Codex on 7/24/26.
//

import Foundation
import SwiftUI
import XCTest
@testable import Moru

@MainActor
final class OnboardingFigmaVisualTests: XCTestCase {
  func testFlowLayoutWrapsItemsWithoutFallingBackToSingleItemRows() {
    let measurement = FlowLayout.measure(
      sizes: [
        CGSize(width: 80, height: 32),
        CGSize(width: 88, height: 32),
        CGSize(width: 72, height: 32),
        CGSize(width: 64, height: 32),
      ],
      maximumWidth: 176,
      spacing: 8
    )

    XCTAssertEqual(
      measurement.origins,
      [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 88, y: 0),
        CGPoint(x: 0, y: 40),
        CGPoint(x: 80, y: 40),
      ]
    )
    XCTAssertEqual(measurement.size, CGSize(width: 176, height: 72))
  }

  func testFigmaGoalSpacingAndAlarmTimePresentationContract() {
    XCTAssertEqual(OnboardingFigmaLayout.goalTitleContentSpacing, 88)
    XCTAssertEqual(OnboardingFigmaLayout.alarmScrollBottomSpacing, 72)
    XCTAssertEqual(
      OnboardingFigmaLayout.alarmAccessibilityScrollBottomSpacing,
      128
    )

    let midnight = OnboardingAlarmTimePresentation(hour: 0, minute: 5)
    XCTAssertEqual(midnight.time, "12:05")
    XCTAssertEqual(midnight.period, "AM")
    XCTAssertEqual(midnight.accessibilityValue, "오전 12시 5분")

    let noon = OnboardingAlarmTimePresentation(hour: 12, minute: 0)
    XCTAssertEqual(noon.time, "12:00")
    XCTAssertEqual(noon.period, "PM")
    XCTAssertEqual(noon.accessibilityValue, "오후 12시 0분")

    let evening = OnboardingAlarmTimePresentation(hour: 19, minute: 45)
    XCTAssertEqual(evening.time, "07:45")
    XCTAssertEqual(evening.period, "PM")
    XCTAssertEqual(evening.accessibilityValue, "오후 7시 45분")
    XCTAssertEqual(
      OnboardingAlarmTimePresentation.displayHourText(for: 19),
      "07"
    )
  }

  func testWeekdaySelectorKeepsFullHitTargetsOnNarrowScreens() {
    let referenceWidth: CGFloat = 353
    XCTAssertEqual(
      OnboardingFigmaLayout.weekdaySpacing(
        availableWidth: referenceWidth
      ),
      7
    )

    let narrowWidth: CGFloat = 335
    let narrowSpacing = OnboardingFigmaLayout.weekdaySpacing(
      availableWidth: narrowWidth
    )
    let occupiedWidth =
      OnboardingFigmaLayout.weekdayButtonSize * 7
      + narrowSpacing * 6

    XCTAssertEqual(narrowSpacing, 4.5)
    XCTAssertLessThanOrEqual(occupiedWidth, narrowWidth)
  }

  func testAlarmRendersAtNarrowPhoneWidth() throws {
    let outputDirectory = URL(
      fileURLWithPath: "/private/tmp/moru-figma-p1-after"
    )
    let image = try MoruVisualCaptureFixture.render(
      screen(for: .alarm),
      filename: "alarm-light-M-375.png",
      variant: .lightMedium,
      outputDirectory: outputDirectory,
      configuration: MoruVisualCaptureConfiguration(
        size: CGSize(width: 375, height: 812),
        scale: 3
      )
    )

    XCTAssertEqual(image.size, CGSize(width: 375, height: 812))
    XCTAssertEqual(image.scale, 3)
  }

  func testFigmaCopyAndProgressContract() {
    XCTAssertEqual(
      RoutineExperience.allCases.map(OnboardingCopy.experienceDescription),
      [
        "루틴을 경험해본 적 없어요",
        "어떤 루틴이 좋을지 모르겠어요",
        "이미 루틴이 있어요",
      ]
    )
    XCTAssertEqual(
      OnboardingDraft.goalOptions.map(\.subtitle),
      [
        "에너지 넘치는 하루 시작",
        "몸과 마음을 챙기는 루틴",
        "차분하고 평온한 아침",
        "꾸준한 생활 루틴 만들기",
      ]
    )
    XCTAssertEqual(
      VoiceProfile.localVoices.map(OnboardingCopy.voiceDescription),
      [
        "따뜻한 친구",
        "차분한 동반자",
        "활기찬 응원자",
        "편안한 가족 같은 목소리",
      ]
    )
    XCTAssertEqual(
      VoiceProfile.localVoices.map(OnboardingCopy.voiceCTA),
      VoiceProfile.localVoices.map { "‘\($0.displayName)’로 코칭받기" }
    )

    let recommendedRoute: [OnboardingStep] = [
      .experience,
      .goals,
      .suggestedRoutine,
      .duration,
      .alarm,
      .voice,
      .completion,
    ]
    let existingRoutineRoute: [OnboardingStep] = [
      .experience,
      .freeform,
      .organizing,
      .review,
      .alarm,
      .voice,
      .completion,
    ]

    assertProgressRoute(
      recommendedRoute,
      experience: .wantsRecommendation
    )
    assertProgressRoute(existingRoutineRoute, experience: .hasRoutine)

    let onboardingAlarm = OnboardingViewModel(
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
    let recommendedAlarm = OnboardingViewModel(
      flowMode: .recommendedAddition,
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
    XCTAssertEqual(onboardingAlarm.primaryButtonTitle, "다음")
    XCTAssertEqual(recommendedAlarm.primaryButtonTitle, "저장")

    let copy = [
      OnboardingCopy.experienceSubtitle,
      OnboardingCopy.freeformSubtitle,
      OnboardingCopy.organizingTitle,
      OnboardingCopy.organizingSubtitle,
      OnboardingCopy.reviewTitle,
      OnboardingCopy.voiceSubtitle,
    ].joined(separator: " ")
    XCTAssertFalse(copy.localizedCaseInsensitiveContains("AI"))
    XCTAssertFalse(copy.contains("PRO"))
    XCTAssertFalse(copy.contains("날씨"))
    XCTAssertFalse(copy.contains("운세"))
  }

  func testAlarmSystemSoundGuidanceAndVisualContract() throws {
    XCTAssertEqual(
      OnboardingCopy.alarmSoundGuidance,
      "알람 소리와 음량은 iPhone 설정을 따라요."
    )

    try assertStateRendersDeterministically(.alarm)
  }

  func testUnsupportedAlarmNarrationOptionsDefaultToDisabled() throws {
    var draft = OnboardingDraft()
    draft.previewRoutine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: draft.suggestionInput
    )
    let viewModel = OnboardingViewModel(
      draft: draft,
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )

    XCTAssertFalse(viewModel.draft.includeWeather)
    XCTAssertFalse(viewModel.draft.includeFortune)

    let completionRequest = CompleteOnboardingRequest(
      suggestionInput: viewModel.draft.suggestionInput,
      selectedVoice: viewModel.draft.selectedVoice
    )
    XCTAssertFalse(completionRequest.includeWeather)
    XCTAssertFalse(completionRequest.includeFortune)

    XCTAssertFalse(
      viewModel.draft.previewRoutine?.alarmSchedule?.includeWeather ?? true
    )
    XCTAssertFalse(
      viewModel.draft.previewRoutine?.alarmSchedule?.includeFortune ?? true
    )
  }

  func testOnboardingStatesRenderDeterministicallyAtReferenceVariants() throws {
    for state in OnboardingCaptureState.allCases
    where state != .alarm && state != .startSplash {
      try assertStateRendersDeterministically(state)
    }
  }

  func testStartSplashRendersDeterministicallyAtReferenceVariants() throws {
    try assertStateRendersDeterministically(.startSplash)
  }

  private func assertStateRendersDeterministically(
    _ state: OnboardingCaptureState
  ) throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_ONBOARDING_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-p1-\(phase)"
    )

    for variant in MoruVisualCaptureVariant.allCases {
      let filename = "\(state.rawValue)-\(variant.rawValue).png"
      let first = try MoruVisualCaptureFixture.render(
        screen(for: state),
        filename: filename,
        variant: variant,
        outputDirectory: outputDirectory
      )
      let second = try MoruVisualCaptureFixture.render(
        screen(for: state),
        filename: "\(state.rawValue)-\(variant.rawValue)-repeat.png",
        variant: variant,
        outputDirectory: outputDirectory
      )

      XCTAssertEqual(first.size, CGSize(width: 393, height: 852))
      XCTAssertEqual(first.scale, 3)
      XCTAssertEqual(first.pngData(), second.pngData())
    }
  }

  private func assertProgressRoute(
    _ route: [OnboardingStep],
    experience: RoutineExperience,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for (index, step) in route.enumerated() {
      let viewModel = OnboardingViewModel(
        draft: OnboardingDraft(experience: experience),
        step: step,
        routineSuggestionService: LocalTemplateSuggestionService.shared
      )

      XCTAssertEqual(viewModel.progressIndex, index + 1, file: file, line: line)
      XCTAssertEqual(viewModel.progressTotal, route.count, file: file, line: line)
    }
  }

  private func screen(for state: OnboardingCaptureState) throws -> AnyView {
    if state == .splash {
      return AnyView(SplashScreenView())
    }
    if state == .startSplash {
      return AnyView(SplashScreenView(onStart: {}))
    }

    let isRecommendedAdditionExistingRoutineReview =
      state == .recommendedAdditionExistingRoutineReview
    let isExistingRoutineReview = state == .review
      || state == .existingRoutineReview
      || state == .longKorean
      || isRecommendedAdditionExistingRoutineReview
    let usesExistingRoutineRoute = state == .freeform
      || state == .organizing
      || isExistingRoutineReview
    var draft = OnboardingDraft()
    draft.experience = usesExistingRoutineRoute ? .hasRoutine : .wantsRecommendation
    draft.selectedGoalTags = state == .goals || usesExistingRoutineRoute
      ? []
      : ["mind"]
    draft.selectedKeywords = ["물 마시기", "스트레칭"]
    draft.freeformText = if state == .freeform {
      ""
    } else if isExistingRoutineReview {
      "건강 루틴: 물, 스트레칭, 오늘 할 일을 정리하고 싶어요"
    } else {
      "일어나면 물을 마시고 스트레칭한 뒤 오늘 계획을 확인하기"
    }
    draft.alarmHour = 7
    draft.alarmMinute = 0
    draft.selectedWeekdays = [.monday, .wednesday, .saturday, .sunday]

    let suggestionService: any RoutineSuggestionService
    if state == .previewUnavailable {
      suggestionService = OnboardingFailingSuggestionService()
    } else if state == .longKorean {
      suggestionService = try OnboardingLongKoreanSuggestionService(draft: draft)
    } else {
      suggestionService = LocalTemplateSuggestionService.shared
      draft.previewRoutine = try suggestionService.makeRoutine(from: draft.suggestionInput)
      if state == .review || isExistingRoutineReview {
        draft.previewRoutine?.summary = ""
      }
    }

    let viewModel = OnboardingViewModel(
      flowMode: isRecommendedAdditionExistingRoutineReview
        ? .recommendedAddition
        : .onboarding,
      draft: draft,
      step: step(for: state),
      routineSuggestionService: suggestionService,
      completeOnboardingUseCase: OnboardingCaptureCompletionUseCase(),
      voicePreviewPlayer: OnboardingCaptureVoicePreviewPlayer(),
      onCompleted: { _ in }
    )

    return AnyView(OnboardingFlowView(viewModel: viewModel))
  }

  private func step(for state: OnboardingCaptureState) -> OnboardingStep {
    switch state {
    case .splash, .startSplash:
      return .experience
    case .experience:
      return .experience
    case .goals:
      return .goals
    case .suggestedRoutine, .previewUnavailable:
      return .suggestedRoutine
    case .duration:
      return .duration
    case .freeform:
      return .freeform
    case .organizing:
      return .organizing
    case .review, .existingRoutineReview,
         .recommendedAdditionExistingRoutineReview, .longKorean:
      return .review
    case .alarm:
      return .alarm
    case .voice:
      return .voice
    case .completion:
      return .completion
    }
  }
}

private enum OnboardingCaptureState: String, CaseIterable {
  case splash
  case startSplash = "start-splash"
  case experience
  case goals
  case suggestedRoutine = "suggested-routine"
  case duration
  case freeform
  case organizing
  case review
  case existingRoutineReview = "existing-routine-review"
  case recommendedAdditionExistingRoutineReview =
    "recommended-addition-existing-routine-review"
  case alarm
  case voice
  case completion
  case longKorean = "long-korean"
  case previewUnavailable = "preview-unavailable"
}

@MainActor
private final class OnboardingLongKoreanSuggestionService: RoutineSuggestionService {
  private let routine: Routine

  init(draft: OnboardingDraft) throws {
    var routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: draft.suggestionInput
    )
    routine.name = "하루를 차분하고 활기차게 준비하는 아주 긴 아침 루틴"
    routine.summary =
      "기상 직후 몸과 마음을 천천히 깨우며 오늘의 중요한 계획까지 확인하는 루틴"
    if !routine.steps.isEmpty {
      routine.steps[0].title =
        "미지근한 물을 천천히 마시며 오늘의 컨디션을 확인하기"
    }
    self.routine = routine
  }

  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    routine
  }
}

@MainActor
private final class OnboardingFailingSuggestionService: RoutineSuggestionService {
  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    throw OnboardingCaptureError.previewUnavailable
  }
}

@MainActor
private final class OnboardingCaptureCompletionUseCase:
  CompleteOnboardingUseCaseProtocol
{
  func execute(
    _ request: CompleteOnboardingRequest
  ) async throws -> CompleteOnboardingResult {
    CompleteOnboardingResult(
      profile: LocalProfile(selectedVoice: request.selectedVoice),
      routine: try LocalTemplateSuggestionService.shared.makeRoutine(
        from: request.suggestionInput
      )
    )
  }
}

@MainActor
private final class OnboardingCaptureVoicePreviewPlayer: VoicePreviewPlaying {
  func previewVoice(_ voice: VoiceProfile) -> Bool {
    true
  }

  func stopVoicePreview() {}
}

private enum OnboardingCaptureError: LocalizedError {
  case previewUnavailable

  var errorDescription: String? {
    "로컬 추천을 불러오지 못했어요."
  }
}
