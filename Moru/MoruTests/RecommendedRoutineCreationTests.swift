//
//  RecommendedRoutineCreationTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class RecommendedRoutineCreationTests: XCTestCase {
  @MainActor
  func testFlowModesHaveDistinctCompletionDestinations() {
    XCTAssertEqual(
      RoutineCreationFlowMode.onboarding.completionDestination,
      .routineTrial
    )
    XCTAssertEqual(
      RoutineCreationFlowMode.recommendedAddition.completionDestination,
      .routineList
    )
    XCTAssertEqual(
      RoutineCreationFlowMode.directAddition.completionDestination,
      .routineList
    )
    XCTAssertTrue(RoutineCreationFlowMode.onboarding.includesVoiceSelection)
    XCTAssertTrue(RoutineCreationFlowMode.onboarding.includesCompletionTrial)
    XCTAssertFalse(
      RoutineCreationFlowMode.recommendedAddition.includesVoiceSelection
    )
    XCTAssertFalse(
      RoutineCreationFlowMode.recommendedAddition.includesCompletionTrial
    )
    XCTAssertTrue(
      RoutineCreationFlowMode.onboarding.supportsRecommendedRoutineStepEditing
    )
    XCTAssertTrue(
      RoutineCreationFlowMode.recommendedAddition
        .supportsRecommendedRoutineStepEditing
    )
    XCTAssertFalse(
      RoutineCreationFlowMode.directAddition.supportsRecommendedRoutineStepEditing
    )
  }

  @MainActor
  func testRecommendedCancellationDoesNotWriteData() {
    let useCase = RecommendedRoutineCreationUseCaseSpy()
    var cancellationCount = 0
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      recommendedRoutineCreationUseCase: useCase,
      onCancelled: {
        cancellationCount += 1
      }
    )

    XCTAssertTrue(viewModel.refreshPreview())
    viewModel.cancelButtonDidTap()

    XCTAssertEqual(cancellationCount, 1)
    XCTAssertEqual(useCase.conflictRequests.count, 0)
    XCTAssertEqual(useCase.executeRequests.count, 0)
  }

  @MainActor
  func testRecommendedFlowSavesAtAlarmWithoutVoiceOrTrial() async throws {
    let useCase = RecommendedRoutineCreationUseCaseSpy()
    let voicePreviewPlayer = RecommendedVoicePreviewPlayerSpy()
    var savedResults: [RecommendedRoutineCreationResult] = []
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      recommendedRoutineCreationUseCase: useCase,
      voicePreviewPlayer: voicePreviewPlayer,
      onRecommendedRoutineSaved: { result in
        savedResults.append(result)
      }
    )

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .goals)

    viewModel.toggleGoal(tag: "mind")
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .suggestedRoutine)
    XCTAssertTrue(viewModel.showsRecommendedRoutineStepEditor)
    XCTAssertEqual(viewModel.previewSummary, "")

    let selectedCandidate = try XCTUnwrap(
      viewModel.recommendedRoutineStepCandidates.first(
        where: viewModel.isRecommendedRoutineStepSelected
      )
    )
    let additionalCandidate = try XCTUnwrap(
      viewModel.recommendedRoutineStepCandidates.first {
        !viewModel.isRecommendedRoutineStepSelected($0)
      }
    )
    viewModel.toggleRecommendedRoutineStep(selectedCandidate)
    viewModel.toggleRecommendedRoutineStep(additionalCandidate)

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .review)

    let preview = try XCTUnwrap(viewModel.validatedPreviewRoutine)
    let editedStepID = try XCTUnwrap(preview.steps.first?.id)
    let presetItemID = try XCTUnwrap(preview.steps.first?.presetItemID)
    viewModel.updatePreviewName("편집한 마음 루틴")
    viewModel.updatePreviewSummary("검토 화면에서 수정한 설명")
    viewModel.updatePreviewStepTitle(
      id: editedStepID,
      title: "편집한 첫 루틴 항목"
    )

    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .alarm)
    viewModel.updateAlarm(hour: 6, minute: 35)
    viewModel.toggleWeekday(.friday)
    await viewModel.completeButtonDidTap()

    let request = try XCTUnwrap(useCase.executeRequests.first?.request)
    XCTAssertEqual(useCase.executeRequests.count, 1)
    XCTAssertEqual(request.routine.name, "편집한 마음 루틴")
    XCTAssertEqual(request.routine.summary, "검토 화면에서 수정한 설명")
    XCTAssertEqual(request.routine.steps.first?.id, editedStepID)
    XCTAssertEqual(request.routine.steps.first?.presetItemID, presetItemID)
    XCTAssertEqual(request.routine.steps.first?.title, "편집한 첫 루틴 항목")
    XCTAssertEqual(request.alarmHour, 6)
    XCTAssertEqual(request.alarmMinute, 35)
    XCTAssertEqual(savedResults, [useCase.result])
    XCTAssertEqual(viewModel.step, .alarm)
    XCTAssertEqual(voicePreviewPlayer.previewedVoices, [])
    XCTAssertEqual(voicePreviewPlayer.stopCallCount, 0)
  }

  @MainActor
  func testRecommendedAdditionOffersStepEditingForEveryExperience() throws {
    for experience in [
      RoutineExperience.firstTime,
      .wantsRecommendation,
    ] {
      let viewModel = OnboardingViewModel(
        flowMode: .recommendedAddition,
        routineSuggestionService: LocalTemplateSuggestionService.shared
      )

      viewModel.selectExperience(experience)
      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .goals)

      viewModel.toggleGoal(tag: "energy")
      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .suggestedRoutine)
      XCTAssertTrue(viewModel.showsRecommendedRoutineStepEditor)
      XCTAssertEqual(viewModel.previewSummary, "")

      let selectedCandidate = try XCTUnwrap(
        viewModel.recommendedRoutineStepCandidates.first(
          where: viewModel.isRecommendedRoutineStepSelected
        )
      )
      viewModel.toggleRecommendedRoutineStep(selectedCandidate)
      XCTAssertFalse(
        viewModel.isRecommendedRoutineStepSelected(selectedCandidate)
      )

      viewModel.primaryButtonDidTap()
      XCTAssertEqual(viewModel.step, .review)
      viewModel.backButtonDidTap()
      XCTAssertEqual(viewModel.step, .suggestedRoutine)
    }

    let existingRoutineViewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
    existingRoutineViewModel.selectExperience(.hasRoutine)
    existingRoutineViewModel.primaryButtonDidTap()
    XCTAssertEqual(existingRoutineViewModel.step, .freeform)

    existingRoutineViewModel.draft.freeformText =
      "건강 루틴: 물, 스트레칭, 오늘 할 일을 정리하고 싶어요"
    existingRoutineViewModel.primaryButtonDidTap()
    XCTAssertEqual(existingRoutineViewModel.step, .organizing)
    existingRoutineViewModel.organizingDidFinish()
    XCTAssertEqual(existingRoutineViewModel.step, .review)
    XCTAssertTrue(existingRoutineViewModel.showsRecommendedRoutineStepEditor)
    XCTAssertEqual(existingRoutineViewModel.previewSummary, "")

    let selectedCandidate = try XCTUnwrap(
      existingRoutineViewModel.recommendedRoutineStepCandidates.first(
        where: existingRoutineViewModel.isRecommendedRoutineStepSelected
      )
    )
    existingRoutineViewModel.toggleRecommendedRoutineStep(selectedCandidate)
    XCTAssertFalse(
      existingRoutineViewModel.isRecommendedRoutineStepSelected(selectedCandidate)
    )

    existingRoutineViewModel.backButtonDidTap()
    XCTAssertEqual(existingRoutineViewModel.step, .freeform)
  }

  @MainActor
  func testNonOverlappingActiveRoutineRequiresConfirmationAndPreservesExistingSchedule()
    async throws {
    let existingRoutine = makeRoutine(
      name: "기존 루틴",
      weekdays: [.monday]
    )
    let repository = MockRoutineRepository(routines: [existingRoutine])
    let useCase = RecommendedRoutineCreationUseCase(
      routineRepository: repository
    )
    let suggestedRoutine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(
        goalTags: ["health"],
        selectedKeywords: ["스트레칭"],
        weekdays: [.friday]
      )
    )
    let request = RecommendedRoutineCreationRequest(
      routine: suggestedRoutine,
      alarmHour: 7,
      alarmMinute: 20,
      selectedWeekdays: [.friday]
    )

    let conflict = try XCTUnwrap(try useCase.activeRoutineConflict(for: request))
    XCTAssertEqual(conflict.activeRoutineIDs, [existingRoutine.id])

    do {
      _ = try await useCase.execute(request)
      XCTFail("An active routine replacement must be confirmed.")
    } catch let error as RoutineSettingError {
      XCTAssertEqual(error, .activeRoutineReplacementRequired)
    }

    _ = try await useCase.execute(
      request,
      replacingActiveRoutine: true
    )

    let savedExisting = try XCTUnwrap(
      try repository.routine(id: existingRoutine.id)
    )
    let savedRecommended = try XCTUnwrap(
      try repository.routine(id: suggestedRoutine.id)
    )
    XCTAssertFalse(savedExisting.isActive)
    XCTAssertFalse(savedExisting.alarmSchedule?.isEnabled ?? true)
    XCTAssertEqual(savedExisting.alarmSchedule?.weekdays, [.monday])
    XCTAssertTrue(savedRecommended.isActive)
    XCTAssertEqual(
      savedRecommended.alarmSchedule?.weekdays,
      [.friday]
    )
  }

  @MainActor
  func testConflictResolutionIgnoresDuplicateSaveRequests() async {
    let useCase = RecommendedRoutineCreationUseCaseSpy()
    useCase.activeRoutineConflict = RoutineActivationConflictState(
      activeRoutineIDs: [UUID()]
    )
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      recommendedRoutineCreationUseCase: useCase
    )

    XCTAssertTrue(viewModel.refreshPreview())
    await viewModel.completeButtonDidTap()
    XCTAssertNotNil(viewModel.activeRoutineConflict)

    viewModel.replaceActiveRoutineButtonDidTap()
    viewModel.replaceActiveRoutineButtonDidTap()
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(useCase.executeRequests.count, 1)
  }

  @MainActor
  func testKeepingExistingActiveRoutineDoesNotWriteRecommendedRoutine() async {
    let useCase = RecommendedRoutineCreationUseCaseSpy()
    useCase.activeRoutineConflict = RoutineActivationConflictState(
      activeRoutineIDs: [UUID()]
    )
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      recommendedRoutineCreationUseCase: useCase
    )

    XCTAssertTrue(viewModel.refreshPreview())
    await viewModel.completeButtonDidTap()
    XCTAssertNotNil(viewModel.activeRoutineConflict)

    viewModel.keepExistingActiveRoutineButtonDidTap()

    XCTAssertNil(viewModel.activeRoutineConflict)
    XCTAssertEqual(useCase.executeRequests.count, 0)
  }

  @MainActor
  func testSchedulingFailureKeepsRoutineAndReturnsRepairState() async throws {
    let repository = MockRoutineRepository()
    let alarmMutator = RepairRequiredAlarmMutator()
    let useCase = RecommendedRoutineCreationUseCase(
      routineRepository: repository,
      alarmScheduleMutator: alarmMutator
    )
    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(
        goalTags: ["energy"],
        weekdays: [.monday, .tuesday]
      )
    )
    let request = RecommendedRoutineCreationRequest(
      routine: routine,
      alarmHour: 6,
      alarmMinute: 50,
      selectedWeekdays: [.monday, .tuesday]
    )

    let result = try await useCase.execute(
      request,
      replacingActiveRoutine: false
    )

    XCTAssertTrue(result.requiresAlarmRepair)
    XCTAssertNotNil(try repository.routine(id: routine.id))
    XCTAssertEqual(alarmMutator.synchronizedRoutineIDs, [routine.id])
    XCTAssertEqual(
      RoutineSettingItemState(
        id: routine.id,
        title: routine.name,
        stepCountText: "",
        estimatedDurationText: "",
        isActive: true,
        alarmDeliveryState: .repairRequired
      ).alarmDeliveryText,
      "예약 필요"
    )
  }

  @MainActor
  func testRelaunchPreservesProfilePresetStepsAndAlarmSchedule() async throws {
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
    let originalProfile = LocalProfile(
      displayName: "기존 사용자",
      selectedVoice: .kore
    )
    var expectedRoutine: Routine?

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(
        modelContext: container.mainContext
      )
      try dependencies.localProfileRepository.saveProfile(originalProfile)
      var routine = try dependencies.routineSuggestionService.makeRoutine(
        from: RoutineSuggestionInput(
          experience: .wantsRecommendation,
          goalTags: ["habit"],
          selectedKeywords: ["독서"],
          freeformText: "독서 습관",
          wakeUpHour: 6,
          wakeUpMinute: 25,
          weekdays: [.tuesday, .thursday]
        )
      )
      routine.name = "출근 전 독서 루틴"
      routine.steps[0].title = "책 한 쪽 펼치기"
      expectedRoutine = routine

      let useCase = RecommendedRoutineCreationUseCase(
        routineRepository: dependencies.routineRepository
      )
      _ = try await useCase.execute(
        RecommendedRoutineCreationRequest(
          routine: routine,
          alarmHour: 6,
          alarmMinute: 25,
          selectedWeekdays: [.tuesday, .thursday]
        ),
        replacingActiveRoutine: false
      )
    }

    do {
      let expectedRoutine = try XCTUnwrap(expectedRoutine)
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(
        modelContext: container.mainContext
      )
      let savedProfile = try XCTUnwrap(
        try dependencies.localProfileRepository.fetchProfile()
      )
      let savedRoutine = try XCTUnwrap(
        try dependencies.routineRepository.routine(id: expectedRoutine.id)
      )

      XCTAssertEqual(savedProfile.id, originalProfile.id)
      XCTAssertEqual(savedProfile.displayName, originalProfile.displayName)
      XCTAssertEqual(savedProfile.selectedVoice, .kore)
      XCTAssertEqual(savedRoutine.name, "출근 전 독서 루틴")
      XCTAssertEqual(savedRoutine.steps.first?.title, "책 한 쪽 펼치기")
      XCTAssertEqual(
        savedRoutine.steps.map(\.presetItemID),
        expectedRoutine.steps.map(\.presetItemID)
      )
      XCTAssertEqual(savedRoutine.goalTags, expectedRoutine.goalTags)
      XCTAssertEqual(
        savedRoutine.steps.map(\.isRequired),
        expectedRoutine.steps.map(\.isRequired)
      )
      XCTAssertEqual(
        savedRoutine.alarmSchedule?.id,
        expectedRoutine.alarmSchedule?.id
      )
      XCTAssertEqual(savedRoutine.alarmSchedule?.hour, 6)
      XCTAssertEqual(savedRoutine.alarmSchedule?.minute, 25)
      XCTAssertEqual(
        savedRoutine.alarmSchedule?.weekdays,
        [.tuesday, .thursday]
      )
      XCTAssertEqual(
        try dependencies.routineRunRepository.fetchRuns(),
        []
      )
    }
  }

  @MainActor
  private func makeRoutine(
    name: String,
    weekdays: [Weekday]
  ) -> Routine {
    Routine(
      name: name,
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 마시기",
          order: 0,
          estimatedSeconds: 60
        ),
      ],
      alarmSchedule: AlarmSchedule(
        hour: 7,
        minute: 0,
        weekdays: weekdays
      )
    )
  }
}

@MainActor
private final class RecommendedRoutineCreationUseCaseSpy:
  RecommendedRoutineCreationUseCaseProtocol {
  private(set) var conflictRequests: [RecommendedRoutineCreationRequest] = []
  private(set) var executeRequests: [
    (
      request: RecommendedRoutineCreationRequest,
      replacingActiveRoutine: Bool
    )
  ] = []
  var activeRoutineConflict: RoutineActivationConflictState?
  let result = RecommendedRoutineCreationResult(
    routineID: UUID(),
    requiresAlarmRepair: false
  )

  func activeRoutineConflict(
    for request: RecommendedRoutineCreationRequest
  ) throws -> RoutineActivationConflictState? {
    conflictRequests.append(request)
    return activeRoutineConflict
  }

  func execute(
    _ request: RecommendedRoutineCreationRequest,
    replacingActiveRoutine: Bool
  ) async throws -> RecommendedRoutineCreationResult {
    executeRequests.append((request, replacingActiveRoutine))
    return result
  }
}

@MainActor
private final class RecommendedVoicePreviewPlayerSpy: VoicePreviewPlaying {
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

@MainActor
private final class RepairRequiredAlarmMutator: AlarmScheduleMutating {
  private(set) var synchronizedRoutineIDs: [UUID] = []

  func apply(_ mutation: AlarmScheduleMutation) async throws -> AlarmMutationResult {
    guard case .synchronize(let routines) = mutation else {
      return .empty
    }

    synchronizedRoutineIDs = routines.map(\.id)
    return AlarmMutationResult(
      records: routines.compactMap { routine in
        guard let request = AlarmScheduleRequest(routine: routine) else {
          return nil
        }

        return AlarmDeliveryRecord(
          request: request,
          backend: nil,
          state: .repairRequired,
          platformIdentifiers: [],
          lastErrorMessage: "test-scheduling-failure",
          updatedAt: Date()
        )
      }
    )
  }

  func reconcile() async {}

  func cancelAllForReset() async throws {}
}
