//
//  OnboardingViewModel.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation

nonisolated final class OnboardingViewModel: ObservableObject {
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
  private let onCompleted: () -> Void
  private var didComplete = false

  @MainActor
  init(
    draft: OnboardingDraft = OnboardingDraft(),
    step: OnboardingStep = .experience,
    routineSuggestionService: any RoutineSuggestionService,
    completeOnboardingUseCase: any CompleteOnboardingUseCaseProtocol,
    onCompleted: @escaping () -> Void
  ) {
    self.draft = draft
    self.step = step
    self.routineSuggestionService = routineSuggestionService
    self.completeOnboardingUseCase = completeOnboardingUseCase
    self.onCompleted = onCompleted
  }

  @MainActor
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

  @MainActor
  var canAdvance: Bool {
    switch step {
    case .alarm:
      return !draft.selectedWeekdays.isEmpty
    case .voice:
      return VoiceProfile.localVoices.contains(draft.selectedVoice)
    case .completion:
      return !isSaving && !didComplete
    default:
      return true
    }
  }

  @MainActor
  func selectExperience(_ experience: RoutineExperience) {
    draft.experience = experience
  }

  @MainActor
  func toggleGoal(tag: String) {
    if draft.selectedGoalTags.contains(tag) {
      draft.selectedGoalTags.remove(tag)
    } else {
      draft.selectedGoalTags.insert(tag)
    }
  }

  @MainActor
  func toggleKeyword(_ keyword: String) {
    if draft.selectedKeywords.contains(keyword) {
      draft.selectedKeywords.remove(keyword)
    } else {
      draft.selectedKeywords.insert(keyword)
    }
  }

  @MainActor
  func updateAlarm(hour: Int, minute: Int) {
    draft.alarmHour = min(max(hour, 0), 23)
    draft.alarmMinute = min(max(minute, 0), 59)
    refreshPreview()
  }

  @MainActor
  func toggleWeekday(_ weekday: Weekday) {
    if draft.selectedWeekdays.contains(weekday) {
      draft.selectedWeekdays.remove(weekday)
    } else {
      draft.selectedWeekdays.insert(weekday)
    }
    refreshPreview()
  }

  @MainActor
  func selectVoice(_ voice: VoiceProfile) {
    guard VoiceProfile.localVoices.contains(voice) else {
      return
    }

    draft.selectedVoice = voice
  }

  @MainActor
  func advance() {
    guard canAdvance else {
      errorMessage = "필수 항목을 확인해 주세요."
      return
    }

    errorMessage = nil

    switch step {
    case .goals:
      refreshPreview()
      step = .suggestedRoutine
    case .freeform:
      step = .organizing
      refreshPreview()
    case .completion:
      completeButtonDidTap()
    default:
      if let next = step.next {
        step = next
      }
    }
  }

  @MainActor
  func goBack() {
    guard !isSaving, let previous = step.previous else {
      return
    }

    errorMessage = nil
    step = previous
  }

  @MainActor
  func refreshPreview() {
    do {
      draft.previewRoutine = try routineSuggestionService.makeRoutine(
        from: draft.suggestionInput
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  func completeButtonDidTap() {
    guard !isSaving, !didComplete else {
      return
    }

    isSaving = true
    errorMessage = nil

    do {
      _ = try completeOnboardingUseCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: draft.suggestionInput,
          selectedVoice: draft.selectedVoice
        )
      )
      didComplete = true
      isSaving = false
      onCompleted()
    } catch {
      isSaving = false
      errorMessage = error.localizedDescription
    }
  }
}
