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
  func testCompleteOnboardingUseCaseSavesProfileActiveRoutineAndEnabledAlarm()
    async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService
    )

    let result = try await useCase.execute(
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
        selectedVoice: .aoede,
        includeWeather: false,
        includeFortune: true
      )
    )

    let savedProfile = try XCTUnwrap(try dependencies.localProfileRepository.fetchProfile())
    let activeRoutines = try dependencies.routineRepository.fetchActiveRoutines()
    let savedRoutine = try XCTUnwrap(activeRoutines.first)

    XCTAssertEqual(result.profile.selectedVoice, .aoede)
    XCTAssertEqual(savedProfile.selectedVoice, .aoede)
    XCTAssertEqual(activeRoutines.count, 1)
    XCTAssertEqual(savedRoutine.id, result.routine.id)
    XCTAssertTrue(savedRoutine.isActive)
    XCTAssertEqual(savedRoutine.alarmSchedule?.hour, 6)
    XCTAssertEqual(savedRoutine.alarmSchedule?.minute, 30)
    XCTAssertEqual(savedRoutine.alarmSchedule?.weekdays, [.monday, .wednesday])
    XCTAssertEqual(savedRoutine.alarmSchedule?.isEnabled, true)
    XCTAssertEqual(savedRoutine.alarmSchedule?.includeWeather, false)
    XCTAssertEqual(savedRoutine.alarmSchedule?.includeFortune, true)
    XCTAssertEqual(
      savedRoutine.steps.count,
      OnboardingTrialRoutineStepLimit.maximum
    )
    XCTAssertEqual(savedRoutine.steps.map(\.order), [0, 1])
    XCTAssertEqual(savedRoutine.sync?.status, .localOnly)
    XCTAssertNil(savedRoutine.sync?.remoteID)
    XCTAssertNil(savedRoutine.sync?.lastSyncedAt)
    XCTAssertNil(savedRoutine.sync?.remoteRevision)
    XCTAssertTrue(
      SessionStore.isSessionReady(profile: savedProfile)
    )
  }

  @MainActor
  func testCompleteOnboardingUseCaseRejectsInvalidAlarmAndUnavailableVoiceBeforeSaving()
    async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService
    )

    await assertCompleteOnboardingError(.invalidAlarmTime(hour: 24, minute: 0)) {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(
            wakeUpHour: 24,
            wakeUpMinute: 0,
            weekdays: [.monday]
          ),
          selectedVoice: .aoede
        )
      )
    }
    await assertCompleteOnboardingError(.emptyWeekdays) {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(weekdays: []),
          selectedVoice: .aoede
        )
      )
    }
    await assertCompleteOnboardingError(.unavailableVoice("remote-pro-voice")) {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(),
          selectedVoice: VoiceProfile(
            id: "remote-pro-voice",
            displayName: "서버 목소리",
            assetVoiceCode: "Remote"
          )
        )
      )
    }

    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())
    XCTAssertEqual(try dependencies.routineRepository.fetchActiveRoutines(), [])
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
  func testOnboardingLimitsRecommendedRoutineSelectionToTwoSteps()
    throws
  {
    let viewModel = OnboardingViewModel(
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .goals)
    XCTAssertFalse(viewModel.canAdvance)

    viewModel.toggleGoal(tag: "energy")
    viewModel.toggleGoal(tag: "mind")
    XCTAssertEqual(viewModel.draft.selectedGoalTags, ["mind"])
    XCTAssertTrue(viewModel.canAdvance)

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .suggestedRoutine)

    let candidates = viewModel.recommendedRoutineStepCandidates
    XCTAssertEqual(candidates.count, 6)
    XCTAssertTrue(
      candidates.allSatisfy { $0.presetItemID?.hasPrefix("CALM-") == true }
    )
    XCTAssertEqual(
      viewModel.validatedPreviewRoutine?.steps.count,
      OnboardingTrialRoutineStepLimit.maximum
    )
    XCTAssertEqual(
      viewModel.previewRoutineStepCount,
      OnboardingTrialRoutineStepLimit.maximum
    )
    XCTAssertEqual(viewModel.recommendedRoutineSelectionLimitText, "선택한 루틴 2/2")
    XCTAssertEqual(
      viewModel.previewRoutineDurationMinutes,
      OnboardingDuration.totalMinutes(
        for: try XCTUnwrap(viewModel.validatedPreviewRoutine)
      )
    )

    let selectedCandidate = try XCTUnwrap(candidates.first)
    let additionalCandidate = try XCTUnwrap(
      candidates.first { !viewModel.isRecommendedRoutineStepSelected($0) }
    )

    XCTAssertFalse(viewModel.canToggleRecommendedRoutineStep(additionalCandidate))
    viewModel.toggleRecommendedRoutineStep(additionalCandidate)
    XCTAssertFalse(viewModel.isRecommendedRoutineStepSelected(additionalCandidate))
    XCTAssertEqual(
      viewModel.validatedPreviewRoutine?.steps.count,
      OnboardingTrialRoutineStepLimit.maximum
    )

    viewModel.toggleRecommendedRoutineStep(selectedCandidate)
    XCTAssertFalse(viewModel.isRecommendedRoutineStepSelected(selectedCandidate))
    XCTAssertEqual(viewModel.validatedPreviewRoutine?.steps.count, 1)
    XCTAssertEqual(viewModel.previewRoutineStepCount, 1)
    XCTAssertEqual(viewModel.recommendedRoutineSelectionLimitText, "선택한 루틴 1/2")
    XCTAssertEqual(
      viewModel.previewRoutineDurationMinutes,
      OnboardingDuration.totalMinutes(
        for: try XCTUnwrap(viewModel.validatedPreviewRoutine)
      )
    )

    viewModel.toggleRecommendedRoutineStep(additionalCandidate)
    XCTAssertTrue(viewModel.isRecommendedRoutineStepSelected(additionalCandidate))
    XCTAssertEqual(
      viewModel.validatedPreviewRoutine?.steps.count,
      OnboardingTrialRoutineStepLimit.maximum
    )

    let selectedAfterEditing = candidates.filter {
      viewModel.isRecommendedRoutineStepSelected($0)
    }
    for candidate in selectedAfterEditing.dropFirst() {
      viewModel.toggleRecommendedRoutineStep(candidate)
    }

    let finalSelectedCandidate = try XCTUnwrap(
      candidates.first { viewModel.isRecommendedRoutineStepSelected($0) }
    )
    XCTAssertEqual(viewModel.validatedPreviewRoutine?.steps.count, 1)
    XCTAssertFalse(viewModel.canToggleRecommendedRoutineStep(finalSelectedCandidate))

    viewModel.toggleRecommendedRoutineStep(finalSelectedCandidate)
    XCTAssertEqual(viewModel.validatedPreviewRoutine?.steps.count, 1)
  }

  @MainActor
  func testOnboardingUsesTheSelectedTwoStepsForSavingAndTrial() async throws {
    let useCase = SpyCompleteOnboardingUseCase()
    var completedRoutineIDs: [UUID] = []
    let viewModel = OnboardingViewModel(
      draft: OnboardingDraft(
        previewRoutine: try LocalTemplateSuggestionService.shared.makeRoutine(
          from: RoutineSuggestionInput(goalTags: ["health"])
        )
      ),
      step: .completion,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: useCase,
      onCompleted: { routineID in
        completedRoutineIDs.append(routineID)
      }
    )

    let selectedSteps = try XCTUnwrap(viewModel.validatedPreviewRoutine?.steps)
    XCTAssertEqual(selectedSteps.count, OnboardingTrialRoutineStepLimit.maximum)

    await viewModel.completeButtonDidTap()

    let savedSteps = try XCTUnwrap(useCase.requests.first?.previewRoutine?.steps)
    XCTAssertEqual(savedSteps.map(\.id), selectedSteps.map(\.id))
    XCTAssertEqual(completedRoutineIDs, [try XCTUnwrap(useCase.resultRoutineIDs.first)])
  }

  @MainActor
  func testRecommendedAdditionDoesNotApplyOnboardingStepLimit() throws {
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    viewModel.toggleGoal(tag: "health")
    viewModel.primaryButtonDidTap()

    let selectedCandidate = try XCTUnwrap(
      viewModel.recommendedRoutineStepCandidates.first(
        where: viewModel.isRecommendedRoutineStepSelected
      )
    )
    viewModel.toggleRecommendedRoutineStep(selectedCandidate)
    XCTAssertEqual(viewModel.validatedPreviewRoutine?.steps.count, 3)

    viewModel.toggleRecommendedRoutineStep(selectedCandidate)
    let additionalCandidate = try XCTUnwrap(
      viewModel.recommendedRoutineStepCandidates.first {
        !viewModel.isRecommendedRoutineStepSelected($0)
      }
    )
    XCTAssertTrue(viewModel.canToggleRecommendedRoutineStep(additionalCandidate))
    viewModel.toggleRecommendedRoutineStep(additionalCandidate)
    XCTAssertEqual(viewModel.validatedPreviewRoutine?.steps.count, 5)
  }

  @MainActor
  func testRecommendedAdditionRetainsMultiGoalSelection() {
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )

    viewModel.toggleGoal(tag: "energy")
    viewModel.toggleGoal(tag: "health")

    XCTAssertEqual(viewModel.draft.selectedGoalTags, ["energy", "health"])
  }

  @MainActor
  func testOnboardingViewModelMovesThroughStepsAndSavesExactlyOnce() async throws {
    let useCase = SpyCompleteOnboardingUseCase()
    let voicePreviewPlayer = OnboardingVoicePreviewPlayerSpy()
    var completionCount = 0
    var completedRoutineID: UUID?
    let viewModel = OnboardingViewModel(
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: useCase,
      voicePreviewPlayer: voicePreviewPlayer
    ) { routineID in
      completionCount += 1
      completedRoutineID = routineID
    }

    XCTAssertEqual(viewModel.step, .experience)
    XCTAssertEqual(viewModel.progressIndex, 1)
    XCTAssertEqual(viewModel.progressTotal, 7)

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .goals)
    XCTAssertEqual(viewModel.progressIndex, 2)
    viewModel.backButtonDidTap()
    XCTAssertEqual(viewModel.step, .experience)

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .goals)

    viewModel.toggleGoal(tag: "mind")
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .suggestedRoutine)
    XCTAssertEqual(viewModel.progressIndex, 3)
    XCTAssertNotNil(viewModel.draft.previewRoutine)
    XCTAssertEqual(viewModel.previewSummary, "")

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .duration)
    XCTAssertEqual(viewModel.progressIndex, 4)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .alarm)
    XCTAssertEqual(viewModel.progressIndex, 5)

    viewModel.updateAlarm(hour: 6, minute: 40)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .voice)
    XCTAssertEqual(viewModel.progressIndex, 6)

    viewModel.selectVoice(.aoede)
    XCTAssertEqual(voicePreviewPlayer.previewedVoices, [.aoede])
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .completion)
    XCTAssertEqual(viewModel.progressIndex, 7)
    XCTAssertEqual(voicePreviewPlayer.stopCallCount, 0)
    viewModel.voiceSelectionViewDidDisappear()
    XCTAssertEqual(voicePreviewPlayer.stopCallCount, 1)

    await viewModel.completeButtonDidTap()
    await viewModel.completeButtonDidTap()

    XCTAssertEqual(useCase.executeCallCount, 1)
    XCTAssertEqual(completionCount, 1)
    XCTAssertEqual(completedRoutineID, useCase.resultRoutineIDs.first)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpHour, 6)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpMinute, 40)
    XCTAssertEqual(useCase.requests.first?.selectedVoice, .aoede)
    XCTAssertEqual(useCase.requests.first?.previewRoutine?.summary, "")
  }

  @MainActor
  func testRecommendedOnboardingSkipsFreeformAndAnalysisAfterSuggestion() {
    for experience in [
      RoutineExperience.firstTime,
      .wantsRecommendation,
    ] {
      let viewModel = OnboardingViewModel(
        routineSuggestionService: LocalTemplateSuggestionService.shared
      )

      viewModel.selectExperience(experience)
      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .goals)

      viewModel.toggleGoal(tag: "mind")
      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .suggestedRoutine)

      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .duration)
      XCTAssertEqual(viewModel.progressIndex, 4)

      viewModel.backButtonDidTap()
      XCTAssertEqual(viewModel.step, .suggestedRoutine)

      viewModel.primaryButtonDidTap()
      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .alarm)
      XCTAssertEqual(viewModel.progressIndex, 5)

      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .voice)
      XCTAssertEqual(viewModel.progressIndex, 6)
    }
  }

  @MainActor
  func testExistingRoutineOnboardingRoutesThroughEditableAnalysisAndSharedTail()
    async throws
  {
    let useCase = SpyCompleteOnboardingUseCase()
    let viewModel = OnboardingViewModel(
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: useCase
    )

    viewModel.selectExperience(.hasRoutine)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .freeform)
    XCTAssertEqual(viewModel.progressIndex, 2)

    viewModel.draft.freeformText =
      "건강 루틴: 물, 스트레칭, 오늘 할 일을 정리하고 싶어요"
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .organizing)
    XCTAssertEqual(viewModel.progressIndex, 3)

    viewModel.organizingDidFinish()
    XCTAssertEqual(viewModel.step, .review)
    XCTAssertEqual(viewModel.progressIndex, 4)
    XCTAssertTrue(viewModel.showsRecommendedRoutineStepEditor)

    let candidates = viewModel.recommendedRoutineStepCandidates
    XCTAssertEqual(candidates.count, 6)
    XCTAssertTrue(
      candidates.allSatisfy { $0.presetItemID?.hasPrefix("HEALTH-") == true }
    )
    XCTAssertEqual(
      candidates.filter(viewModel.isRecommendedRoutineStepSelected).count,
      OnboardingTrialRoutineStepLimit.maximum
    )

    let selectedCandidate = try XCTUnwrap(
      candidates.first(where: viewModel.isRecommendedRoutineStepSelected)
    )
    let additionalCandidate = try XCTUnwrap(
      candidates.first { !viewModel.isRecommendedRoutineStepSelected($0) }
    )

    viewModel.toggleRecommendedRoutineStep(selectedCandidate)
    XCTAssertFalse(viewModel.isRecommendedRoutineStepSelected(selectedCandidate))
    XCTAssertEqual(viewModel.validatedPreviewRoutine?.steps.count, 1)

    viewModel.toggleRecommendedRoutineStep(additionalCandidate)
    XCTAssertTrue(viewModel.isRecommendedRoutineStepSelected(additionalCandidate))
    XCTAssertEqual(
      viewModel.validatedPreviewRoutine?.steps.count,
      OnboardingTrialRoutineStepLimit.maximum
    )

    viewModel.previewName = "사용자가 고친 건강 루틴"
    viewModel.previewSummary = "사용자가 고친 루틴 설명"

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .alarm)
    XCTAssertEqual(viewModel.progressIndex, 5)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .voice)
    XCTAssertEqual(viewModel.progressIndex, 6)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .completion)
    XCTAssertEqual(viewModel.progressIndex, 7)

    await viewModel.completeButtonDidTap()

    XCTAssertEqual(
      useCase.requests.first?.previewRoutine?.name,
      "사용자가 고친 건강 루틴"
    )
    XCTAssertEqual(
      useCase.requests.first?.previewRoutine?.summary,
      "사용자가 고친 루틴 설명"
    )
  }

  @MainActor
  func testBackButtonSkipsNonInteractiveOrganizingStepFromExistingRoutineReview() {
    var draft = OnboardingDraft()
    draft.experience = .hasRoutine
    let viewModel = OnboardingViewModel(
      draft: draft,
      step: .review,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )

    viewModel.backButtonDidTap()

    XCTAssertEqual(viewModel.step, .freeform)
    viewModel.backButtonDidTap()
    XCTAssertEqual(viewModel.step, .experience)
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
    XCTAssertEqual(viewModel.step, .duration)

    let freeformViewModel = OnboardingViewModel(
      routineSuggestionService: suggestionService,
      completeOnboardingUseCase: SpyCompleteOnboardingUseCase(),
      onCompleted: { _ in }
    )
    freeformViewModel.selectExperience(.hasRoutine)
    freeformViewModel.primaryButtonDidTap()
    XCTAssertEqual(freeformViewModel.step, .freeform)

    suggestionService.shouldFail = true
    freeformViewModel.primaryButtonDidTap()

    XCTAssertEqual(freeformViewModel.step, .freeform)
    XCTAssertNil(freeformViewModel.draft.previewRoutine)
    XCTAssertEqual(
      freeformViewModel.errorMessage,
      RetriableSuggestionError.unavailable.errorDescription
    )

    suggestionService.shouldFail = false
    freeformViewModel.primaryButtonDidTap()

    XCTAssertEqual(freeformViewModel.step, .organizing)
    XCTAssertNotNil(freeformViewModel.draft.previewRoutine)
    XCTAssertNil(freeformViewModel.errorMessage)
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
  func testFreeformInputEnforcesCharacterLimitAndAppendsSelectedKeyword() {
    let viewModel = OnboardingViewModel(
      draft: OnboardingDraft(
        freeformText: String(repeating: "😀", count: 201)
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )

    XCTAssertEqual(viewModel.freeformText.count, 200)

    viewModel.updateFreeformText("")
    viewModel.toggleKeyword("물 마시기")
    XCTAssertEqual(viewModel.freeformText, "물 마시기")

    viewModel.updateFreeformText("아침에")
    viewModel.toggleKeyword("스트레칭")
    XCTAssertEqual(viewModel.freeformText, "아침에 스트레칭")

    viewModel.updateFreeformText(String(repeating: "한", count: 201))
    XCTAssertEqual(viewModel.freeformText.count, 200)
  }

  @MainActor
  func testOnboardingClockProgressReflectsExpectedRoutineMinutes() {
    XCTAssertEqual(OnboardingDuration.clockProgress(forMinutes: 24), 0.4)
    XCTAssertEqual(OnboardingDuration.clockProgress(forMinutes: 60), 1)
    XCTAssertEqual(OnboardingDuration.clockProgress(forMinutes: 90), 1)
    XCTAssertEqual(OnboardingDuration.clockProgress(forMinutes: -1), 0)
  }

  @MainActor
  func testSwiftDataRelaunchPersistenceAfterOnboardingCompletion() async throws {
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

      let result = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(
            goalTags: ["habit"],
            selectedKeywords: ["독서"],
            freeformText: "독서 습관을 만들고 싶어요",
            wakeUpHour: 7,
            wakeUpMinute: 10,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
          ),
          selectedVoice: .aoede
        )
      )
      routineID = result.routine.id
    }

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(modelContext: container.mainContext)
      let sessionStore = SessionStore(
        localProfileRepository: dependencies.localProfileRepository
      )

      sessionStore.load()

      let profile = try XCTUnwrap(sessionStore.profile)
      let activeRoutine = try XCTUnwrap(
        try dependencies.routineRepository.fetchActiveRoutines().first
      )

      XCTAssertEqual(sessionStore.phase, .ready)
      XCTAssertEqual(profile.selectedVoice, .aoede)
      XCTAssertEqual(activeRoutine.id, routineID)
      XCTAssertTrue(activeRoutine.isActive)
      XCTAssertEqual(activeRoutine.alarmSchedule?.isEnabled, true)
      XCTAssertEqual(
        activeRoutine.steps.count,
        OnboardingTrialRoutineStepLimit.maximum
      )
    }
  }

  @MainActor
  private func assertCompleteOnboardingError(
    _ expected: CompleteOnboardingError,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected onboarding completion to fail.")
    } catch {
      XCTAssertEqual(error as? CompleteOnboardingError, expected)
    }
  }
}

@MainActor
private final class SpyCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  private(set) var executeCallCount = 0
  private(set) var requests: [CompleteOnboardingRequest] = []
  private(set) var resultRoutineIDs: [UUID] = []

  func execute(
    _ request: CompleteOnboardingRequest
  ) async throws -> CompleteOnboardingResult {
    executeCallCount += 1
    requests.append(request)

    let routine: Routine
    if let previewRoutine = request.previewRoutine {
      routine = previewRoutine
    } else {
      routine = try LocalTemplateSuggestionService.shared.makeRoutine(
        from: request.suggestionInput
      )
    }
    resultRoutineIDs.append(routine.id)

    return CompleteOnboardingResult(
      profile: LocalProfile(selectedVoice: request.selectedVoice),
      routine: routine
    )
  }
}

@MainActor
private final class OnboardingVoicePreviewPlayerSpy: VoicePreviewPlaying {
  private(set) var previewedVoices: [VoiceProfile] = []
  private(set) var stopCallCount = 0

  func previewVoice(_ voice: VoiceProfile) -> Bool {
    previewedVoices.append(voice)
    return true
  }

  func stopVoicePreview() {
    stopCallCount += 1
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
