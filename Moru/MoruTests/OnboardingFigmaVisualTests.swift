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

    XCTAssertEqual(OnboardingStep.experience.progressIndex, 1)
    XCTAssertEqual(OnboardingStep.goals.progressIndex, 2)
    XCTAssertEqual(OnboardingStep.suggestedRoutine.progressIndex, 3)
    XCTAssertEqual(OnboardingStep.duration.progressIndex, 4)
    XCTAssertEqual(OnboardingStep.freeform.progressIndex, 5)
    XCTAssertNil(OnboardingStep.organizing.progressIndex)
    XCTAssertEqual(OnboardingStep.review.progressIndex, 6)
    XCTAssertEqual(OnboardingStep.alarm.progressIndex, 7)
    XCTAssertEqual(OnboardingStep.voice.progressIndex, 8)
    XCTAssertNil(OnboardingStep.completion.progressIndex)

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

  func testOnboardingStatesRenderDeterministicallyAtReferenceVariants() throws {
    let environment = ProcessInfo.processInfo.environment
    let phase = environment["MORU_ONBOARDING_CAPTURE_PHASE"] ?? "after"
    let outputDirectory = URL(
      fileURLWithPath: environment["MORU_CAPTURE_OUTPUT_DIR"]
        ?? "/private/tmp/moru-figma-p1-\(phase)"
    )

    for state in OnboardingCaptureState.allCases {
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
  }

  private func screen(for state: OnboardingCaptureState) throws -> AnyView {
    if state == .splash {
      return AnyView(SplashScreenView())
    }

    var draft = OnboardingDraft()
    draft.experience = .wantsRecommendation
    draft.selectedGoalTags = ["energy", "health"]
    draft.selectedKeywords = ["물 마시기", "스트레칭"]
    draft.freeformText = state == .freeform
      ? ""
      : "일어나면 물을 마시고 스트레칭한 뒤 오늘 계획을 확인하기"
    draft.alarmHour = 7
    draft.alarmMinute = 0
    draft.selectedWeekdays = [.monday, .wednesday, .friday, .sunday]

    let suggestionService: any RoutineSuggestionService
    if state == .previewUnavailable {
      suggestionService = OnboardingFailingSuggestionService()
    } else if state == .longKorean {
      suggestionService = try OnboardingLongKoreanSuggestionService(draft: draft)
    } else {
      suggestionService = LocalTemplateSuggestionService.shared
      draft.previewRoutine = try suggestionService.makeRoutine(from: draft.suggestionInput)
    }

    let viewModel = OnboardingViewModel(
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
    case .splash:
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
    case .review, .longKorean:
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
  case experience
  case goals
  case suggestedRoutine = "suggested-routine"
  case duration
  case freeform
  case organizing
  case review
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
