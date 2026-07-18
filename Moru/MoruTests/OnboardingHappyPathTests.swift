//
//  OnboardingHappyPathTests.swift
//  MoruTests
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class OnboardingHappyPathTests: XCTestCase {
  @MainActor
  func testCompleteOnboardingUseCaseSavesDefaultYunaProfileActiveRoutineAndEnabledAlarm() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService
    )

    let defaultVoice = OnboardingDraft().selectedVoice

    let result = try useCase.execute(
      CompleteOnboardingRequest(
        suggestionInput: RoutineSuggestionInput(
          experience: .wantsRecommendation,
          goalTags: ["health"],
          selectedKeywords: ["물 마시기", "스트레칭"],
          freeformText: "아침에 물을 마시고 가볍게 몸을 풀고 싶어요",
          wakeUpHour: 6,
          wakeUpMinute: 30,
          weekdays: [.monday, .wednesday]
        ),
        selectedVoice: defaultVoice
      )
    )

    let savedProfile = try XCTUnwrap(try dependencies.localProfileRepository.fetchProfile())
    let activeRoutines = try dependencies.routineRepository.fetchActiveRoutines()
    let savedRoutine = try XCTUnwrap(activeRoutines.first)

    XCTAssertEqual(result.profile.selectedVoice, .yuna)
    XCTAssertEqual(savedProfile.selectedVoice, .yuna)
    XCTAssertEqual(activeRoutines.count, 1)
    XCTAssertEqual(savedRoutine.id, result.routine.id)
    XCTAssertTrue(savedRoutine.isActive)
    XCTAssertEqual(savedRoutine.alarmSchedule?.hour, 6)
    XCTAssertEqual(savedRoutine.alarmSchedule?.minute, 30)
    XCTAssertEqual(savedRoutine.alarmSchedule?.weekdays, [.monday, .wednesday])
    XCTAssertEqual(savedRoutine.alarmSchedule?.isEnabled, true)
    XCTAssertEqual(Set(savedRoutine.steps.map(\.type)), Set(RoutineStepType.allCases))
    XCTAssertEqual(savedRoutine.sync?.status, .localOnly)
    XCTAssertNil(savedRoutine.sync?.remoteID)
    XCTAssertNil(savedRoutine.sync?.lastSyncedAt)
    XCTAssertNil(savedRoutine.sync?.remoteRevision)
  }

  @MainActor
  func testCompleteOnboardingUseCaseRejectsInvalidAlarmAndUnavailableVoiceBeforeSaving() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService
    )

    XCTAssertThrowsError(
      try useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(
            wakeUpHour: 24,
            wakeUpMinute: 0,
            weekdays: [.monday]
          ),
          selectedVoice: .yuna
        )
      )
    ) {
      XCTAssertEqual(
        $0 as? CompleteOnboardingError,
        .invalidAlarmTime(hour: 24, minute: 0)
      )
    }

    XCTAssertThrowsError(
      try useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(weekdays: []),
          selectedVoice: .yuna
        )
      )
    ) {
      XCTAssertEqual($0 as? CompleteOnboardingError, .emptyWeekdays)
    }

    XCTAssertThrowsError(
      try useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(),
          selectedVoice: VoiceProfile(
            id: "remote-pro-voice",
            displayName: "서버 목소리",
            localeIdentifier: "ko-KR"
          )
        )
      )
    ) {
      XCTAssertEqual(
        $0 as? CompleteOnboardingError,
        .unavailableVoice("remote-pro-voice")
      )
    }

    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())
    XCTAssertEqual(try dependencies.routineRepository.fetchActiveRoutines(), [])
  }

  @MainActor
  func testOnboardingDefaultsToYunaAndExcludesLegacyVoiceFromCatalogue() {
    let draft = OnboardingDraft()

    XCTAssertEqual(draft.selectedVoice, .yuna)
    XCTAssertEqual(VoiceProfile.localVoices, [.yuna, .sora])
    XCTAssertFalse(VoiceProfile.localVoices.contains { $0.id == "moru-local" })
  }

  @MainActor
  func testLocalTemplateSuggestionIsDeterministicForNormalizedInput() throws {
    let service = LocalTemplateSuggestionService.shared
    let input = RoutineSuggestionInput(
      experience: .firstTime,
      goalTags: ["mind"],
      selectedKeywords: ["명상", "일기"],
      freeformText: "  명상으로 마음 안정  ",
      wakeUpHour: 7,
      wakeUpMinute: 5,
      weekdays: [.tuesday, .thursday]
    )

    let first = try service.makeRoutine(from: input)
    let second = try service.makeRoutine(from: input)

    XCTAssertEqual(first.name, second.name)
    XCTAssertEqual(first.summary, second.summary)
    XCTAssertEqual(first.goalTags, second.goalTags)
    XCTAssertEqual(first.alarmSchedule?.hour, second.alarmSchedule?.hour)
    XCTAssertEqual(first.alarmSchedule?.minute, second.alarmSchedule?.minute)
    XCTAssertEqual(first.alarmSchedule?.weekdays, second.alarmSchedule?.weekdays)
    XCTAssertEqual(first.steps.map(\.type), second.steps.map(\.type))
    XCTAssertEqual(first.steps.map(\.title), second.steps.map(\.title))
    XCTAssertEqual(first.steps.map(\.estimatedSeconds), second.steps.map(\.estimatedSeconds))
    XCTAssertTrue(
      Set(first.steps.map(\.id)).isDisjoint(with: Set(second.steps.map(\.id)))
    )
    XCTAssertEqual(Set(first.steps.map(\.type)), Set(RoutineStepType.allCases))
    XCTAssertEqual(first.sync?.status, .localOnly)
    XCTAssertNil(first.sync?.remoteID)
  }

  @MainActor
  func testOnboardingViewModelMovesThroughStepsAndSavesExactlyOnce() throws {
    let useCase = SpyCompleteOnboardingUseCase()
    var completionCount = 0
    var completedRoutineID: UUID?
    let viewModel = OnboardingViewModel(
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: useCase
    ) { routineID in
      completionCount += 1
      completedRoutineID = routineID
    }

    XCTAssertEqual(viewModel.step, .experience)
    XCTAssertEqual(viewModel.draft.selectedVoice, .yuna)

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .goals)
    viewModel.backButtonDidTap()
    XCTAssertEqual(viewModel.step, .experience)

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .goals)

    viewModel.toggleGoal(tag: "mind")
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .suggestedRoutine)
    XCTAssertNotNil(viewModel.draft.previewRoutine)

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .duration)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .freeform)

    viewModel.draft.freeformText = "명상하고 일기를 쓰고 싶어요"
    viewModel.toggleKeyword("명상")
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .organizing)
    XCTAssertFalse(
      viewModel.draft.previewRoutine?.summary.localizedCaseInsensitiveContains("AI") ?? true
    )

    viewModel.organizingDidFinish()
    XCTAssertEqual(viewModel.step, .review)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .alarm)

    viewModel.updateAlarm(hour: 6, minute: 40)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .voice)

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .completion)

    viewModel.primaryButtonDidTap()
    viewModel.primaryButtonDidTap()

    XCTAssertEqual(useCase.executeCallCount, 1)
    XCTAssertEqual(completionCount, 1)
    XCTAssertEqual(completedRoutineID, useCase.resultRoutineIDs.first)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpHour, 6)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpMinute, 40)
    XCTAssertEqual(useCase.requests.first?.selectedVoice, .yuna)
  }

  @MainActor
  func testOnboardingViewModelRetriesPreviewBeforeAdvancing() {
    let suggestionService = RetriableSuggestionService()
    let viewModel = OnboardingViewModel(
      routineSuggestionService: suggestionService,
      completeOnboardingUseCase: SpyCompleteOnboardingUseCase(),
      onCompleted: { _ in }
    )

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    viewModel.toggleGoal(tag: "mind")
    viewModel.primaryButtonDidTap()

    XCTAssertEqual(viewModel.step, .goals)
    XCTAssertNil(viewModel.draft.previewRoutine)
    XCTAssertEqual(viewModel.errorMessage, RetriableSuggestionError.unavailable.errorDescription)

    suggestionService.shouldFail = false
    viewModel.primaryButtonDidTap()

    XCTAssertEqual(viewModel.step, .suggestedRoutine)
    XCTAssertNotNil(viewModel.draft.previewRoutine)
    XCTAssertNil(viewModel.errorMessage)

    viewModel.primaryButtonDidTap()
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .freeform)

    suggestionService.shouldFail = true
    viewModel.primaryButtonDidTap()

    XCTAssertEqual(viewModel.step, .freeform)
    XCTAssertNil(viewModel.draft.previewRoutine)
    XCTAssertEqual(viewModel.errorMessage, RetriableSuggestionError.unavailable.errorDescription)

    suggestionService.shouldFail = false
    viewModel.primaryButtonDidTap()

    XCTAssertEqual(viewModel.step, .organizing)
    XCTAssertNotNil(viewModel.draft.previewRoutine)
    XCTAssertNil(viewModel.errorMessage)
  }

  @MainActor
  func testOnboardingViewModelRejectsEmptyPreviewRoutine() {
    let suggestionService = EmptyPreviewSuggestionService()
    let completionUseCase = SpyCompleteOnboardingUseCase()
    let viewModel = OnboardingViewModel(
      routineSuggestionService: suggestionService,
      completeOnboardingUseCase: completionUseCase,
      onCompleted: { _ in }
    )

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    viewModel.toggleGoal(tag: "mind")
    viewModel.primaryButtonDidTap()

    XCTAssertEqual(viewModel.step, .goals)
    XCTAssertNil(viewModel.draft.previewRoutine)
    XCTAssertNil(viewModel.validatedPreviewRoutine)
    XCTAssertEqual(viewModel.errorMessage, "루틴 항목을 불러올 수 없어요.")

    let emptyRoutine = Routine(name: "빈 루틴", steps: [])
    for step in [
      OnboardingStep.suggestedRoutine,
      .duration,
      .review,
      .alarm,
      .voice
    ] {
      var draft = OnboardingDraft()
      draft.previewRoutine = emptyRoutine
      let invalidPreviewViewModel = OnboardingViewModel(
        draft: draft,
        step: step,
        routineSuggestionService: suggestionService,
        completeOnboardingUseCase: completionUseCase,
        onCompleted: { _ in }
      )

      XCTAssertNil(invalidPreviewViewModel.validatedPreviewRoutine)
      XCTAssertFalse(invalidPreviewViewModel.canAdvance)
    }
  }

  @MainActor
  func testOnboardingDurationRoundsStepAndTotalMinutesConsistently() {
    let routine = Routine(
      name: "검증 루틴",
      steps: [
        RoutineStep(type: .timer, title: "첫 번째", order: 0, estimatedSeconds: 61),
        RoutineStep(type: .timer, title: "두 번째", order: 1, estimatedSeconds: 1)
      ]
    )

    XCTAssertEqual(OnboardingDuration.roundedMinutes(for: routine.steps[0].estimatedSeconds), 2)
    XCTAssertEqual(OnboardingDuration.roundedMinutes(for: routine.steps[1].estimatedSeconds), 1)
    XCTAssertEqual(OnboardingDuration.totalMinutes(for: routine), 3)
  }
  @MainActor
  func testDiskReopenSnapshotPreservesOnboardingCompletionFacts() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let storeURL = temporaryDirectory.appendingPathComponent("Moru.store")
    var routineID: UUID?

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(modelContext: container.mainContext)
      let useCase = CompleteOnboardingUseCase(
        onboardingRepository: dependencies.onboardingRepository,
        routineSuggestionService: dependencies.routineSuggestionService
      )

      let result = try useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(
            goalTags: ["habit"],
            selectedKeywords: ["독서"],
            freeformText: "독서 습관을 만들고 싶어요",
            wakeUpHour: 7,
            wakeUpMinute: 10,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
          ),
          selectedVoice: .yuna
        )
      )
      routineID = result.routine.id
    }

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let loader = SessionSnapshotLoading(modelContainer: container)
      let snapshot = try await loader.loadSnapshot()
      let sessionStore = SessionStore()

      sessionStore.apply(snapshot: snapshot)

      let profile = try XCTUnwrap(sessionStore.profile)
      let activeRoutine = try XCTUnwrap(snapshot.activeRoutines.first)

      XCTAssertEqual(sessionStore.phase, .onboardingRequired)
      XCTAssertFalse(SessionStore.isOnboardingComplete(snapshot: snapshot))
      XCTAssertEqual(profile.selectedVoice, .yuna)
      XCTAssertEqual(activeRoutine.id, routineID)
      XCTAssertTrue(activeRoutine.isActive)
      XCTAssertEqual(activeRoutine.alarmSchedule?.isEnabled, true)
      XCTAssertEqual(activeRoutine.steps.count, 10)
      XCTAssertEqual(snapshot.platformStates, [])
    }
  }
}

@MainActor
private final class SpyCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  private(set) var executeCallCount = 0
  private(set) var requests: [CompleteOnboardingRequest] = []
  private(set) var resultRoutineIDs: [UUID] = []

  func execute(_ request: CompleteOnboardingRequest) throws -> CompleteOnboardingResult {
    executeCallCount += 1
    requests.append(request)

    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: request.suggestionInput
    )
    resultRoutineIDs.append(routine.id)

    return CompleteOnboardingResult(
      profile: LocalProfile(selectedVoice: request.selectedVoice),
      routine: routine
    )
  }
}
private enum RetriableSuggestionError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "루틴 미리보기를 생성할 수 없어요."
  }
}

@MainActor
private final class RetriableSuggestionService: RoutineSuggestionService {
  var shouldFail = true

  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    guard !shouldFail else {
      throw RetriableSuggestionError.unavailable
    }

    return try LocalTemplateSuggestionService.shared.makeRoutine(from: input)
  }
}
@MainActor
private final class EmptyPreviewSuggestionService: RoutineSuggestionService {
  func makeRoutine(from input: RoutineSuggestionInput) throws -> Routine {
    Routine(name: "빈 루틴", steps: [])
  }
}
