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
  let flowMode: RoutineCreationFlowMode

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

  private(set) var weekdayConflict: RoutineWeekdayConflictState? {
    willSet {
      objectWillChange.send()
    }
  }

  private let routineSuggestionService: any RoutineSuggestionService
  private let completeOnboardingUseCase: (any CompleteOnboardingUseCaseProtocol)?
  private let recommendedRoutineCreationUseCase:
    (any RecommendedRoutineCreationUseCaseProtocol)?
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let onCompleted: OnboardingCompletionHandler
  private let onRecommendedRoutineSaved:
    @MainActor (RecommendedRoutineCreationResult) -> Void
  private let onCancelled: @MainActor () -> Void
  private var didComplete = false

  init(
    flowMode: RoutineCreationFlowMode = .onboarding,
    draft: OnboardingDraft = OnboardingDraft(),
    step: OnboardingStep = .experience,
    routineSuggestionService: any RoutineSuggestionService,
    completeOnboardingUseCase: (any CompleteOnboardingUseCaseProtocol)? = nil,
    recommendedRoutineCreationUseCase:
      (any RecommendedRoutineCreationUseCaseProtocol)? = nil,
    voicePreviewPlayer: any VoicePreviewPlaying = UnavailableVoicePreviewPlayer(),
    onCompleted: @escaping OnboardingCompletionHandler = { _ in },
    onRecommendedRoutineSaved:
      @escaping @MainActor (RecommendedRoutineCreationResult) -> Void = { _ in },
    onCancelled: @escaping @MainActor () -> Void = {}
  ) {
    self.flowMode = flowMode
    self.draft = draft
    self.step = step
    self.routineSuggestionService = routineSuggestionService
    self.completeOnboardingUseCase = completeOnboardingUseCase
    self.recommendedRoutineCreationUseCase = recommendedRoutineCreationUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.onCompleted = onCompleted
    self.onRecommendedRoutineSaved = onRecommendedRoutineSaved
    self.onCancelled = onCancelled
  }

  var progressTotal: Int {
    flowMode == .onboarding ? OnboardingStep.progressTotal : 8
  }

  var progressIndex: Int? {
    guard step != .completion else {
      return nil
    }

    return min(step.rawValue + 1, progressTotal)
  }

  var canCancel: Bool {
    flowMode != .onboarding && !isSaving
  }

  var allowsReviewEditing: Bool {
    flowMode == .recommendedAddition
  }

  var previewName: String {
    get {
      draft.previewRoutine?.name ?? ""
    }
    set {
      updatePreviewName(newValue)
    }
  }

  var previewSummary: String {
    get {
      draft.previewRoutine?.summary ?? ""
    }
    set {
      updatePreviewSummary(newValue)
    }
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
    case .suggestedRoutine, .duration:
      return hasValidatedPreviewRoutine
    case .review:
      return hasValidReview
    case .alarm:
      return hasValidReview && !draft.selectedWeekdays.isEmpty && !isSaving
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
    updatePreviewAlarm()
  }

  func toggleWeekday(_ weekday: Weekday) {
    if draft.selectedWeekdays.contains(weekday) {
      draft.selectedWeekdays.remove(weekday)
    } else {
      draft.selectedWeekdays.insert(weekday)
    }
    updatePreviewAlarm()
  }

  func updatePreviewName(_ name: String) {
    guard var routine = draft.previewRoutine else {
      return
    }

    routine.name = name
    draft.previewRoutine = routine
  }

  func updatePreviewSummary(_ summary: String) {
    guard var routine = draft.previewRoutine else {
      return
    }

    routine.summary = summary
    draft.previewRoutine = routine
  }

  func updatePreviewStepTitle(id: UUID, title: String) {
    guard var routine = draft.previewRoutine,
          let index = routine.steps.firstIndex(where: { $0.id == id }) else {
      return
    }

    routine.steps[index].title = title
    draft.previewRoutine = routine
  }

  func previewStepTitle(id: UUID) -> String {
    draft.previewRoutine?.steps
      .first(where: { $0.id == id })?.title ?? ""
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
    case .alarm where flowMode == .recommendedAddition:
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

  func cancelButtonDidTap() {
    guard canCancel else {
      return
    }

    onCancelled()
  }

  func keepExistingWeekdayScheduleButtonDidTap() {
    weekdayConflict = nil
  }

  func resolveWeekdayConflictButtonDidTap() {
    guard flowMode == .recommendedAddition else {
      return
    }

    Task {
      await saveRecommendedRoutine(resolvingWeekdayConflict: true)
    }
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

    guard flowMode == .onboarding else {
      await saveRecommendedRoutine(resolvingWeekdayConflict: false)
      return
    }

    guard let completeOnboardingUseCase else {
      errorMessage = "온보딩 저장 기능을 사용할 수 없어요."
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

  private var hasValidReview: Bool {
    guard let routine = validatedPreviewRoutine else {
      return false
    }

    return !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && routine.steps.allSatisfy {
        !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  private func updatePreviewAlarm() {
    guard var routine = draft.previewRoutine else {
      return
    }

    if var schedule = routine.alarmSchedule {
      schedule.hour = draft.alarmHour
      schedule.minute = draft.alarmMinute
      schedule.weekdays = draft.orderedWeekdays
      schedule.isEnabled = true
      routine.alarmSchedule = schedule
    } else {
      routine.alarmSchedule = AlarmSchedule(
        hour: draft.alarmHour,
        minute: draft.alarmMinute,
        weekdays: draft.orderedWeekdays
      )
    }

    draft.previewRoutine = routine
  }

  private func saveRecommendedRoutine(
    resolvingWeekdayConflict: Bool
  ) async {
    guard flowMode == .recommendedAddition,
          let routine = validatedPreviewRoutine,
          let recommendedRoutineCreationUseCase else {
      errorMessage = "추천 루틴 저장 기능을 사용할 수 없어요."
      return
    }

    let request = RecommendedRoutineCreationRequest(
      routine: routine,
      alarmHour: draft.alarmHour,
      alarmMinute: draft.alarmMinute,
      selectedWeekdays: draft.selectedWeekdays
    )

    if !resolvingWeekdayConflict {
      do {
        let conflictingWeekdays = try recommendedRoutineCreationUseCase
          .weekdayConflict(for: request)
        if !conflictingWeekdays.isEmpty {
          weekdayConflict = RoutineWeekdayConflictState(
            conflictingWeekdays: conflictingWeekdays
          )
          return
        }
      } catch {
        errorMessage = error.localizedDescription
        return
      }
    }

    isSaving = true
    errorMessage = nil
    weekdayConflict = nil

    do {
      let result = try await recommendedRoutineCreationUseCase.execute(
        request,
        resolvingWeekdayConflict: resolvingWeekdayConflict
      )
      didComplete = true
      isSaving = false
      onRecommendedRoutineSaved(result)
    } catch {
      isSaving = false
      errorMessage = error.localizedDescription
    }
  }
}
