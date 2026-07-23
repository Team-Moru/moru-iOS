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
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .duration)
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .freeform)

    viewModel.draft.freeformText = "명상과 일기로 차분하게 시작하고 싶어요"
    viewModel.toggleKeyword("명상")
    viewModel.primaryButtonDidTap()
    XCTAssertEqual(viewModel.step, .organizing)
    viewModel.organizingDidFinish()
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
  func testWeekdayConflictCanBeResolvedThroughExistingMutationPath()
    async throws {
    let existingRoutine = makeRoutine(
      name: "기존 루틴",
      weekdays: [.monday, .wednesday]
    )
    let repository = MockRoutineRepository(routines: [existingRoutine])
    let useCase = RecommendedRoutineCreationUseCase(
      routineRepository: repository
    )
    let suggestedRoutine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(
        goalTags: ["health"],
        selectedKeywords: ["스트레칭"],
        weekdays: [.wednesday, .friday]
      )
    )
    let request = RecommendedRoutineCreationRequest(
      routine: suggestedRoutine,
      alarmHour: 7,
      alarmMinute: 20,
      selectedWeekdays: [.wednesday, .friday]
    )

    XCTAssertEqual(
      try useCase.weekdayConflict(for: request),
      [.wednesday]
    )

    _ = try await useCase.execute(
      request,
      resolvingWeekdayConflict: true
    )

    let savedExisting = try XCTUnwrap(
      try repository.routine(id: existingRoutine.id)
    )
    let savedRecommended = try XCTUnwrap(
      try repository.routine(id: suggestedRoutine.id)
    )
    XCTAssertEqual(savedExisting.alarmSchedule?.weekdays, [.monday])
    XCTAssertEqual(
      savedRecommended.alarmSchedule?.weekdays,
      [.wednesday, .friday]
    )
  }

  @MainActor
  func testConflictResolutionIgnoresDuplicateSaveRequests() async {
    let useCase = RecommendedRoutineCreationUseCaseSpy()
    useCase.conflictingWeekdays = [.monday]
    let viewModel = OnboardingViewModel(
      flowMode: .recommendedAddition,
      step: .alarm,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      recommendedRoutineCreationUseCase: useCase
    )

    XCTAssertTrue(viewModel.refreshPreview())
    await viewModel.completeButtonDidTap()
    XCTAssertNotNil(viewModel.weekdayConflict)

    viewModel.resolveWeekdayConflictButtonDidTap()
    viewModel.resolveWeekdayConflictButtonDidTap()
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(useCase.executeRequests.count, 1)
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
      resolvingWeekdayConflict: false
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
        resolvingWeekdayConflict: false
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
      resolvingWeekdayConflict: Bool
    )
  ] = []
  var conflictingWeekdays: Set<Weekday> = []
  let result = RecommendedRoutineCreationResult(
    routineID: UUID(),
    requiresAlarmRepair: false
  )

  func weekdayConflict(
    for request: RecommendedRoutineCreationRequest
  ) throws -> Set<Weekday> {
    conflictRequests.append(request)
    return conflictingWeekdays
  }

  func execute(
    _ request: RecommendedRoutineCreationRequest,
    resolvingWeekdayConflict: Bool
  ) async throws -> RecommendedRoutineCreationResult {
    executeRequests.append((request, resolvingWeekdayConflict))
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
