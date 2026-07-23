//
//  OnboardingViewModel.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
  let objectWillChange = ObservableObjectPublisher()

  var draft: OnboardingDraft {
    willSet {
      objectWillChange.send()
    }
  }

  private(set) var step: OnboardingStep {
    willSet {
      objectWillChange.send()
    }
  }

  private(set) var isSaving: Bool = false {
    willSet {
      objectWillChange.send()
    }
  }

  private(set) var errorMessage: String? {
    willSet {
      objectWillChange.send()
    }
  }

  private let routineSuggestionService: any RoutineSuggestionService
  private let completeOnboardingUseCase: any CompleteOnboardingUseCaseProtocol
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let onCompleted: OnboardingCompletionHandler
  private var didComplete = false

  init(
    draft: OnboardingDraft = OnboardingDraft(),
    step: OnboardingStep = .experience,
    routineSuggestionService: any RoutineSuggestionService,
    completeOnboardingUseCase: any CompleteOnboardingUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying = UnavailableVoicePreviewPlayer(),
    onCompleted: @escaping OnboardingCompletionHandler
  ) {
    self.draft = draft
    self.step = step
    self.routineSuggestionService = routineSuggestionService
    self.completeOnboardingUseCase = completeOnboardingUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.onCompleted = onCompleted
  }

  var primaryButtonTitle: String {
    switch step {
    case .experience, .goals, .duration, .organizing:
      return "다음"
    case .suggestedRoutine, .freeform:
      return "이 루틴으로 시작하기"
    case .review:
      return "알람 설정하기"
    case .alarm:
      return "저장"
    case .voice:
      return "모루로 코칭받기"
    case .completion:
      return "루틴 체험하기"
    }
  }

  var validatedPreviewRoutine: Routine? {
    guard let previewRoutine = draft.previewRoutine, !previewRoutine.steps.isEmpty else {
      return nil
    }

    return previewRoutine
  }

  var hasValidatedPreviewRoutine: Bool {
    validatedPreviewRoutine != nil
  }

  var canAdvance: Bool {
    switch step {
    case .suggestedRoutine, .duration, .review:
      return hasValidatedPreviewRoutine
    case .alarm:
      return hasValidatedPreviewRoutine && !draft.selectedWeekdays.isEmpty
    case .voice:
      return hasValidatedPreviewRoutine
        && VoiceProfile.localVoices.contains(draft.selectedVoice)
    case .completion:
      return !isSaving && !didComplete
    case .experience, .goals, .freeform, .organizing:
      return true
    }
  }

  func selectExperience(_ experience: RoutineExperience) {
    draft.experience = experience
  }

  func toggleGoal(tag: String) {
    if draft.selectedGoalTags.contains(tag) {
      draft.selectedGoalTags.remove(tag)
    } else {
      draft.selectedGoalTags.insert(tag)
    }
  }

  func toggleKeyword(_ keyword: String) {
    if draft.selectedKeywords.contains(keyword) {
      draft.selectedKeywords.remove(keyword)
    } else {
      draft.selectedKeywords.insert(keyword)
    }
  }

  func updateAlarm(hour: Int, minute: Int) {
    draft.alarmHour = min(max(hour, 0), 23)
    draft.alarmMinute = min(max(minute, 0), 59)
    _ = refreshPreview()
  }

  func toggleWeekday(_ weekday: Weekday) {
    if draft.selectedWeekdays.contains(weekday) {
      draft.selectedWeekdays.remove(weekday)
    } else {
      draft.selectedWeekdays.insert(weekday)
    }
    _ = refreshPreview()
  }

  func selectVoice(_ voice: VoiceProfile) {
    guard VoiceProfile.localVoices.contains(voice) else {
      return
    }

    draft.selectedVoice = voice
    _ = voicePreviewPlayer.previewVoice(voice)
  }

  func voiceSelectionViewDidDisappear() {
    voicePreviewPlayer.stopVoicePreview()
  }

  func primaryButtonDidTap() {
    guard canAdvance else {
      errorMessage = "필수 항목을 확인해 주세요."
      return
    }

    errorMessage = nil

    switch step {
    case .goals:
      guard refreshPreview() else {
        return
      }
      step = .suggestedRoutine
    case .freeform:
      guard refreshPreview() else {
        return
      }
      step = .organizing
    case .completion:
      Task {
        await completeButtonDidTap()
      }
    default:
      if let next = step.next {
        step = next
      }
    }
  }

  func backButtonDidTap() {
    guard !isSaving, let previous = step.previous else {
      return
    }

    errorMessage = nil
    step = previous
  }

  func organizingDidFinish() {
    guard step == .organizing else {
      return
    }

    step = .review
  }

  @discardableResult
  func refreshPreview() -> Bool {
    draft.previewRoutine = nil

    do {
      draft.previewRoutine = try routineSuggestionService.makeRoutine(
        from: draft.suggestionInput
      )

      guard hasValidatedPreviewRoutine else {
        draft.previewRoutine = nil
        errorMessage = "루틴 항목을 불러올 수 없어요."
        return false
      }
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func completeButtonDidTap() async {
    guard !isSaving, !didComplete else {
      return
    }

    isSaving = true
    errorMessage = nil

    do {
      let result = try await completeOnboardingUseCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: draft.suggestionInput,
          selectedVoice: draft.selectedVoice
        )
      )
      didComplete = true
      isSaving = false
      onCompleted(result.routine.id)
    } catch {
      isSaving = false
      errorMessage = error.localizedDescription
    }
  }
}
