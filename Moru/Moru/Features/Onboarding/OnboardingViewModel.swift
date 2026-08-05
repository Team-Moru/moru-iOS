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

  private(set) var isSuggesting: Bool = false {
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
  private let routineSuggestionCoordinator:
    (any RoutineSuggestionCoordinating)?
  private let onboardingRecommendationCoordinator:
    (any RoutineSuggestionCoordinating)?
  private let completeOnboardingUseCase: (any CompleteOnboardingUseCaseProtocol)?
  private let recommendedRoutineCreationUseCase:
    (any RecommendedRoutineCreationUseCaseProtocol)?
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let onCompleted: OnboardingCompletionHandler
  private let onRecommendedRoutineSaved:
    @MainActor (RecommendedRoutineCreationResult) -> Void
  private let onCancelled: @MainActor () -> Void
  private var didComplete = false
  private var suggestionRequestID: UUID?
  private var suggestionTask: Task<RoutineSuggestionResult, Error>?
  private var suggestionFlowID: UUID?
  private var suggestionFlowTask: Task<Void, Never>?

  init(
    flowMode: RoutineCreationFlowMode = .onboarding,
    draft: OnboardingDraft = OnboardingDraft(),
    step: OnboardingStep = .experience,
    routineSuggestionService: any RoutineSuggestionService,
    routineSuggestionCoordinator:
      (any RoutineSuggestionCoordinating)? = nil,
    onboardingRecommendationCoordinator:
      (any RoutineSuggestionCoordinating)? = nil,
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
    self.routineSuggestionCoordinator = routineSuggestionCoordinator
    self.onboardingRecommendationCoordinator =
      onboardingRecommendationCoordinator
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
    step.progressIndex
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
    case .alarm:
      return allowsReviewEditing ? "저장" : "다음"
    case .suggestedRoutine, .freeform:
      return "이 루틴으로 시작하기"
    case .review:
      return "알람 설정하기"
    case .voice:
      return OnboardingCopy.voiceCTA(for: draft.selectedVoice)
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
    guard !isSuggesting else {
      return false
    }

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

  func setIncludeWeather(_ isIncluded: Bool) {
    draft.includeWeather = isIncluded
    updatePreviewAlarm()
  }

  func setIncludeFortune(_ isIncluded: Bool) {
    draft.includeFortune = isIncluded
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
    guard canAdvance, !isSuggesting else {
      errorMessage = "필수 항목을 확인해 주세요."
      return
    }

    errorMessage = nil

    switch step {
    case .goals:
      let coordinator: (any RoutineSuggestionCoordinating)?
      if flowMode == .onboarding {
        coordinator = onboardingRecommendationCoordinator
          ?? routineSuggestionCoordinator
      } else {
        coordinator = routineSuggestionCoordinator
      }
      if let coordinator {
        startSuggestion(
          using: coordinator,
          advancingTo: .suggestedRoutine
        )
      } else {
        guard refreshPreview() else {
          return
        }
        step = .suggestedRoutine
      }
    case .freeform:
      if let routineSuggestionCoordinator {
        step = .organizing
        startSuggestion(
          using: routineSuggestionCoordinator,
          advancingTo: .review,
          returningTo: .freeform
        )
      } else {
        guard refreshPreview() else {
          return
        }
        step = .organizing
      }
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

    cancelSuggestion()
    errorMessage = nil
    step = previous
  }

  func cancelButtonDidTap() {
    guard canCancel else {
      return
    }

    cancelSuggestion()
    onCancelled()
  }

  func viewDidDisappear() {
    cancelSuggestion()
  }

  func keepExistingWeekdayScheduleButtonDidTap() {
    weekdayConflict = nil
  }

  func resolveWeekdayConflictButtonDidTap() {
    guard flowMode == .recommendedAddition, !isSaving, !didComplete else {
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
    cancelSuggestion()
    draft.previewRoutine = nil
    draft.suggestionSource = nil

    do {
      draft.previewRoutine = try routineSuggestionService.makeRoutine(
        from: draft.suggestionInput
      )
      draft.suggestionSource = .localFallback(.signedOut)

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

  @discardableResult
  func refreshPreviewAsync() async throws -> Bool {
    cancelSuggestion()
    guard let routineSuggestionCoordinator else {
      return refreshPreview()
    }

    return try await loadPreviewAsync(
      using: routineSuggestionCoordinator
    )
  }

  private func loadPreviewAsync(
    using coordinator: any RoutineSuggestionCoordinating
  ) async throws -> Bool {
    try Task.checkCancellation()

    let input = draft.suggestionInput
    let requestID = UUID()
    let requestTask = Task {
      try await coordinator.suggest(from: input)
    }
    suggestionRequestID = requestID
    suggestionTask = requestTask
    isSuggesting = true
    draft.previewRoutine = nil
    draft.suggestionSource = nil
    errorMessage = nil

    do {
      let result = try await withTaskCancellationHandler {
        try await requestTask.value
      } onCancel: {
        requestTask.cancel()
      }

      guard suggestionRequestID == requestID,
            draft.suggestionInput == input else {
        if suggestionRequestID == requestID {
          finishSuggestion(requestID: requestID)
        }
        return false
      }

      draft.previewRoutine = result.routine
      draft.suggestionSource = result.source
      finishSuggestion(requestID: requestID)

      guard hasValidatedPreviewRoutine else {
        draft.previewRoutine = nil
        draft.suggestionSource = nil
        errorMessage = "루틴 항목을 불러올 수 없어요."
        return false
      }

      return true
    } catch is CancellationError {
      finishSuggestion(requestID: requestID)
      throw CancellationError()
    } catch {
      guard suggestionRequestID == requestID else {
        return false
      }
      finishSuggestion(requestID: requestID)
      errorMessage = "루틴 추천을 불러올 수 없어요."
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
          selectedVoice: draft.selectedVoice,
          previewRoutine: validatedPreviewRoutine,
          includeWeather: draft.includeWeather,
          includeFortune: draft.includeFortune
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
      schedule.includeWeather = draft.includeWeather
      schedule.includeFortune = draft.includeFortune
      routine.alarmSchedule = schedule
    } else {
      routine.alarmSchedule = AlarmSchedule(
        hour: draft.alarmHour,
        minute: draft.alarmMinute,
        weekdays: draft.orderedWeekdays,
        includeWeather: draft.includeWeather,
        includeFortune: draft.includeFortune
      )
    }

    draft.previewRoutine = routine
  }

  private func saveRecommendedRoutine(
    resolvingWeekdayConflict: Bool
  ) async {
    guard !isSaving, !didComplete else {
      return
    }

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
      selectedWeekdays: draft.selectedWeekdays,
      includeWeather: draft.includeWeather,
      includeFortune: draft.includeFortune
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

  private func startSuggestion(
    using coordinator: any RoutineSuggestionCoordinating,
    advancingTo nextStep: OnboardingStep,
    returningTo failureStep: OnboardingStep? = nil
  ) {
    cancelSuggestion()
    let flowID = UUID()
    suggestionFlowID = flowID
    suggestionFlowTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      defer {
        finishSuggestionFlow(flowID: flowID)
      }

      do {
        try Task.checkCancellation()
        guard try await loadPreviewAsync(using: coordinator) else {
          if let failureStep {
            step = failureStep
          }
          return
        }
        try Task.checkCancellation()
        step = nextStep
      } catch is CancellationError {
        return
      } catch {
        errorMessage = "루틴 추천을 불러올 수 없어요."
        if let failureStep {
          step = failureStep
        }
      }
    }
  }

  private func cancelSuggestion() {
    suggestionFlowTask?.cancel()
    suggestionFlowTask = nil
    suggestionFlowID = nil
    suggestionTask?.cancel()
    suggestionTask = nil
    suggestionRequestID = nil
    isSuggesting = false
  }

  private func finishSuggestionFlow(flowID: UUID) {
    guard suggestionFlowID == flowID else {
      return
    }

    suggestionFlowTask = nil
    suggestionFlowID = nil
  }

  private func finishSuggestion(requestID: UUID) {
    guard suggestionRequestID == requestID else {
      return
    }

    suggestionTask = nil
    suggestionRequestID = nil
    isSuggesting = false
  }
}
