//
//  OnboardingViewModel.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation

// Client-side presentation phases. They pace onboarding UI and are not server telemetry.
enum RoutineOrganizingPresentationPhase: Int, CaseIterable, Equatable {
  case preparingRoutine
  case organizingRecommendation
  case preparingReview
  case completed
}

enum RoutineOrganizingPresentationTiming {
  static let statusAnimationDuration = 0.28
  static let phaseDwell: Duration = .seconds(1)
  static let completedDwell: Duration = .seconds(1)
}

@MainActor
final class OnboardingViewModel: ObservableObject {
  static let freeformTextCharacterLimit = 200

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

  private(set) var organizingProgress: RoutineOrganizingPresentationPhase =
    .preparingRoutine {
    willSet {
      objectWillChange.send()
    }
  }

  private(set) var errorMessage: String? {
    willSet {
      objectWillChange.send()
    }
  }

  private(set) var activeRoutineConflict: RoutineActivationConflictState? {
    willSet {
      objectWillChange.send()
    }
  }

  /// The goal-specific cards shown while a user adjusts either a Moru
  /// recommendation or an analyzed existing routine. Their selected subset
  /// is persisted in `draft.previewRoutine.steps` in every guided creation flow.
  private(set) var recommendedRoutineStepCandidates: [RoutineStep] = [] {
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
  private var organizingPresentationTask: Task<Void, Never>?
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
    var normalizedDraft = draft
    if flowMode == .onboarding, normalizedDraft.selectedGoalTags.count > 1 {
      normalizedDraft.selectedGoalTags = Set(
        normalizedDraft.orderedGoalTags.prefix(1)
      )
    }
    normalizedDraft.freeformText = String(
      normalizedDraft.freeformText.prefix(Self.freeformTextCharacterLimit)
    )
    if flowMode == .onboarding,
       let previewRoutine = normalizedDraft.previewRoutine {
      normalizedDraft.previewRoutine = OnboardingTrialRoutineStepLimit
        .normalized(previewRoutine)
    }

    self.flowMode = flowMode
    self.draft = normalizedDraft
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

    if shouldConfigureRecommendedRoutineStepCandidates(for: step) {
      configureRecommendedRoutineStepCandidates()
    }
  }

  var progressTotal: Int {
    flowMode == .onboarding ? onboardingProgressSteps.count : 8
  }

  var progressIndex: Int? {
    guard flowMode == .onboarding else {
      return step.progressIndex
    }

    return onboardingProgressSteps.firstIndex(of: step).map { $0 + 1 }
  }

  var canCancel: Bool {
    flowMode != .onboarding && !isSaving
  }

  var canNavigateBack: Bool {
    previousStep != nil
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

  var freeformText: String {
    draft.freeformText
  }

  var previewRoutineStepCount: Int {
    validatedPreviewRoutine?.steps.count ?? 0
  }

  var previewRoutineDurationMinutes: Int {
    guard let routine = validatedPreviewRoutine else {
      return 0
    }

    return OnboardingDuration.totalMinutes(for: routine)
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

  var hasRecommendedRoutineStepCandidates: Bool {
    flowMode.supportsRecommendedRoutineStepEditing
      && !recommendedRoutineStepCandidates.isEmpty
  }

  var recommendedRoutineSelectionLimitText: String? {
    guard flowMode == .onboarding,
          hasRecommendedRoutineStepCandidates else {
      return nil
    }

    return "선택한 루틴 \(previewRoutineStepCount)/"
      + "\(OnboardingTrialRoutineStepLimit.maximum)"
  }

  var showsRecommendedRoutineStepEditor: Bool {
    guard hasRecommendedRoutineStepCandidates else {
      return false
    }

    switch (step, draft.experience) {
    case (.suggestedRoutine, _), (.review, .hasRoutine):
      return true
    default:
      return false
    }
  }

  var canAdvance: Bool {
    guard !isSuggesting else {
      return false
    }

    switch step {
    case .goals:
      return flowMode != .onboarding || !draft.selectedGoalTags.isEmpty
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
    case .experience, .freeform, .organizing:
      return true
    }
  }

  func selectExperience(_ experience: RoutineExperience) {
    draft.experience = experience
  }

  func toggleGoal(tag: String) {
    if flowMode == .onboarding {
      guard draft.selectedGoalTags != [tag] else {
        return
      }

      draft.selectedGoalTags = [tag]
      recommendedRoutineStepCandidates = []
      return
    }

    if draft.selectedGoalTags.contains(tag) {
      draft.selectedGoalTags.remove(tag)
    } else {
      draft.selectedGoalTags.insert(tag)
    }
  }

  func isRecommendedRoutineStepSelected(_ candidate: RoutineStep) -> Bool {
    draft.previewRoutine?.steps.contains {
      representsSameRecommendedRoutineStep($0, as: candidate)
    } ?? false
  }

  func canToggleRecommendedRoutineStep(_ candidate: RoutineStep) -> Bool {
    guard hasRecommendedRoutineStepCandidates,
          let routine = validatedPreviewRoutine else {
      return false
    }

    if isRecommendedRoutineStepSelected(candidate) {
      return routine.steps.count > OnboardingTrialRoutineStepLimit.minimum
    }

    return flowMode != .onboarding
      || routine.steps.count < OnboardingTrialRoutineStepLimit.maximum
  }

  func toggleRecommendedRoutineStep(_ candidate: RoutineStep) {
    guard flowMode.supportsRecommendedRoutineStepEditing,
          recommendedRoutineStepCandidates.contains(where: {
            representsSameRecommendedRoutineStep($0, as: candidate)
          }),
          var routine = draft.previewRoutine,
          !routine.steps.isEmpty else {
      return
    }

    if let index = routine.steps.firstIndex(where: {
      representsSameRecommendedRoutineStep($0, as: candidate)
    }) {
      guard routine.steps.count > OnboardingTrialRoutineStepLimit.minimum else {
        return
      }
      routine.steps.remove(at: index)
    } else {
      guard flowMode != .onboarding
        || routine.steps.count < OnboardingTrialRoutineStepLimit.maximum else {
        return
      }
      routine.steps.append(candidate)
    }

    routine.steps = routine.steps
      .sorted { $0.order < $1.order }
      .enumerated()
      .map { index, step in
        var normalizedStep = step
        normalizedStep.order = index
        return normalizedStep
      }
    draft.previewRoutine = routine
  }

  func toggleKeyword(_ keyword: String) {
    if draft.selectedKeywords.contains(keyword) {
      draft.selectedKeywords.remove(keyword)
    } else {
      draft.selectedKeywords.insert(keyword)
      appendKeywordToFreeformText(keyword)
    }
  }

  func updateFreeformText(_ text: String) {
    draft.freeformText = String(text.prefix(Self.freeformTextCharacterLimit))
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
    case .experience where flowMode.supportsRecommendedRoutineStepEditing:
      step = draft.experience == .hasRoutine ? .freeform : .goals
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
        configureRecommendedRoutineStepCandidates()
        step = .suggestedRoutine
      }
    case .suggestedRoutine where flowMode == .onboarding:
      step = .duration
    case .suggestedRoutine where flowMode.supportsRecommendedRoutineStepEditing:
      step = .review
    case .duration where flowMode == .onboarding
      && draft.experience != .hasRoutine:
      step = .alarm
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
        configureRecommendedRoutineStepCandidates()
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
    guard !isSaving, let previous = previousStep else {
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

  func keepExistingActiveRoutineButtonDidTap() {
    activeRoutineConflict = nil
  }

  func replaceActiveRoutineButtonDidTap() {
    guard flowMode == .recommendedAddition, !isSaving, !didComplete else {
      return
    }

    Task {
      await saveRecommendedRoutine(replacingActiveRoutine: true)
    }
  }

  func organizingDidFinish() {
    guard step == .organizing else {
      return
    }

    if shouldConfigureRecommendedRoutineStepCandidates(for: .review) {
      configureRecommendedRoutineStepCandidates()
    }
    step = .review
  }

  @discardableResult
  func refreshPreview() -> Bool {
    cancelSuggestion()
    recommendedRoutineStepCandidates = []
    draft.previewRoutine = nil
    draft.suggestionSource = nil

    do {
      draft.previewRoutine = normalizedPreviewRoutine(
        routinePreparedForUserDescription(
          try routineSuggestionService.makeRoutine(from: draft.suggestionInput)
        )
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
    if step == .organizing {
      startOrganizingPresentation(requestID: requestID)
    }
    recommendedRoutineStepCandidates = []
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

      draft.previewRoutine = normalizedPreviewRoutine(
        routinePreparedForUserDescription(result.routine)
      )
      draft.suggestionSource = result.source

      guard hasValidatedPreviewRoutine else {
        finishSuggestion(requestID: requestID)
        draft.previewRoutine = nil
        draft.suggestionSource = nil
        errorMessage = "루틴 항목을 불러올 수 없어요."
        return false
      }

      try await completeOrganizingPresentation(requestID: requestID)
      finishSuggestion(requestID: requestID)

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
      await saveRecommendedRoutine(replacingActiveRoutine: false)
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

  private var onboardingProgressSteps: [OnboardingStep] {
    switch draft.experience {
    case .firstTime, .wantsRecommendation:
      return [
        .experience,
        .goals,
        .suggestedRoutine,
        .duration,
        .alarm,
        .voice,
        .completion,
      ]
    case .hasRoutine:
      return [
        .experience,
        .freeform,
        .organizing,
        .review,
        .alarm,
        .voice,
        .completion,
      ]
    }
  }

  private var previousStep: OnboardingStep? {
    if flowMode == .onboarding {
      switch (step, draft.experience) {
      case (.freeform, .hasRoutine):
        return .experience
      case (.organizing, .hasRoutine), (.review, .hasRoutine):
        return .freeform
      case (.alarm, .firstTime), (.alarm, .wantsRecommendation):
        return .duration
      case (.duration, .firstTime), (.duration, .wantsRecommendation):
        return .suggestedRoutine
      case (.suggestedRoutine, .firstTime),
           (.suggestedRoutine, .wantsRecommendation):
        return .goals
      default:
        guard let index = onboardingProgressSteps.firstIndex(of: step),
              index > onboardingProgressSteps.startIndex else {
          return nil
        }
        return onboardingProgressSteps[index - 1]
      }
    }

    guard flowMode.supportsRecommendedRoutineStepEditing else {
      return step.previous
    }

    switch (step, draft.experience) {
    case (.freeform, .hasRoutine) where flowMode == .recommendedAddition:
      return nil
    case (.freeform, .hasRoutine):
      return .experience
    case (.review, .hasRoutine):
      return .freeform
    case (.review, .firstTime), (.review, .wantsRecommendation):
      return .suggestedRoutine
    default:
      return step.previous
    }
  }

  private func appendKeywordToFreeformText(_ keyword: String) {
    guard !draft.freeformText.contains(keyword) else {
      return
    }

    let separator = draft.freeformText.isEmpty
      || draft.freeformText.last?.isWhitespace == true
      ? ""
      : " "
    let appendedText = draft.freeformText + separator + keyword
    guard appendedText.count <= Self.freeformTextCharacterLimit else {
      return
    }

    updateFreeformText(appendedText)
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

  private func configureRecommendedRoutineStepCandidates() {
    guard flowMode.supportsRecommendedRoutineStepEditing,
          let routine = validatedPreviewRoutine else {
      recommendedRoutineStepCandidates = []
      return
    }

    var candidates = routine.steps.sorted { $0.order < $1.order }

    if let itemProvider = routineSuggestionService as? any RoutineSuggestionItemProviding,
       let presetItems = try? itemProvider.recommendationItems(
         from: draft.suggestionInput
       ) {
      for item in presetItems {
        let candidate = item.makeStep(order: candidates.count)
        guard !candidates.contains(where: {
          representsSameRecommendedRoutineStep($0, as: candidate)
        }) else {
          continue
        }
        candidates.append(candidate)
      }
    }

    recommendedRoutineStepCandidates = Array(candidates.prefix(6))
  }

  private func shouldConfigureRecommendedRoutineStepCandidates(
    for targetStep: OnboardingStep
  ) -> Bool {
    guard flowMode.supportsRecommendedRoutineStepEditing else {
      return false
    }

    return targetStep == .suggestedRoutine
      || (targetStep == .review && draft.experience == .hasRoutine)
  }

  private func routinePreparedForUserDescription(_ routine: Routine) -> Routine {
    var editableRoutine = routine
    editableRoutine.summary = ""
    return editableRoutine
  }

  private func normalizedPreviewRoutine(_ routine: Routine) -> Routine {
    guard flowMode == .onboarding else {
      return routine
    }

    return OnboardingTrialRoutineStepLimit.normalized(routine)
  }

  private func representsSameRecommendedRoutineStep(
    _ lhs: RoutineStep,
    as rhs: RoutineStep
  ) -> Bool {
    if let lhsPresetItemID = lhs.presetItemID,
       let rhsPresetItemID = rhs.presetItemID {
      return lhsPresetItemID == rhsPresetItemID
    }

    return lhs.id == rhs.id
  }

  private func saveRecommendedRoutine(
    replacingActiveRoutine: Bool
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

    if !replacingActiveRoutine {
      do {
        if let conflict = try recommendedRoutineCreationUseCase
          .activeRoutineConflict(for: request) {
          activeRoutineConflict = conflict
          return
        }
      } catch {
        errorMessage = error.localizedDescription
        return
      }
    }

    isSaving = true
    errorMessage = nil
    activeRoutineConflict = nil

    do {
      let result = try await recommendedRoutineCreationUseCase.execute(
        request,
        replacingActiveRoutine: replacingActiveRoutine
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
        if shouldConfigureRecommendedRoutineStepCandidates(for: nextStep) {
          configureRecommendedRoutineStepCandidates()
        }
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
    organizingPresentationTask?.cancel()
    organizingPresentationTask = nil
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
    organizingPresentationTask?.cancel()
    organizingPresentationTask = nil
    suggestionRequestID = nil
    isSuggesting = false
  }

  private func startOrganizingPresentation(requestID: UUID) {
    organizingPresentationTask?.cancel()
    organizingProgress = .preparingRoutine
    organizingPresentationTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      do {
        try await self.pauseOrganizingPresentation(
          requestID: requestID,
          for: RoutineOrganizingPresentationTiming.phaseDwell
        )
        try self.updateOrganizingPresentation(
          .organizingRecommendation,
          requestID: requestID
        )
        try await self.pauseOrganizingPresentation(
          requestID: requestID,
          for: RoutineOrganizingPresentationTiming.phaseDwell
        )
        try self.updateOrganizingPresentation(
          .preparingReview,
          requestID: requestID
        )
        try await self.pauseOrganizingPresentation(
          requestID: requestID,
          for: RoutineOrganizingPresentationTiming.phaseDwell
        )
      } catch is CancellationError {
        return
      } catch {
        return
      }
    }
  }

  private func completeOrganizingPresentation(requestID: UUID) async throws {
    guard step == .organizing else {
      return
    }

    if let organizingPresentationTask {
      await organizingPresentationTask.value
    }

    try updateOrganizingPresentation(
      .completed,
      requestID: requestID
    )
    try await pauseOrganizingPresentation(
      requestID: requestID,
      for: RoutineOrganizingPresentationTiming.completedDwell
    )
  }

  private func updateOrganizingPresentation(
    _ progress: RoutineOrganizingPresentationPhase,
    requestID: UUID
  ) throws {
    try Task.checkCancellation()
    guard suggestionRequestID == requestID, step == .organizing else {
      throw CancellationError()
    }

    organizingProgress = progress
  }

  private func pauseOrganizingPresentation(
    requestID: UUID,
    for duration: Duration
  ) async throws {
    try Task.checkCancellation()
    guard suggestionRequestID == requestID, step == .organizing else {
      throw CancellationError()
    }

    try await _Concurrency.Task<Never, Never>.sleep(for: duration)
  }
}
