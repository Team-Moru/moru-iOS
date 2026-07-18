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
  func testCompleteOnboardingUseCaseSchedulesBeforeSavingProfileAndRoutine() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let alarmScheduleMutator = SpyAlarmScheduleMutator()
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
    )

    let defaultVoice = OnboardingDraft().selectedVoice

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
    XCTAssertEqual(
      alarmScheduleMutator.events,
      [.commitStarted, .platformSucceeded, .localCommitStarted, .localCommitFinished]
    )
    XCTAssertEqual(alarmScheduleMutator.committedRoutineIDs, [result.routine.id])
  }

  @MainActor
  func testOnboardingRejectsInvalidAlarmAndUnavailableVoiceBeforeScheduling() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let alarmScheduleMutator = SpyAlarmScheduleMutator()
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
    )

    await assertCompleteOnboardingError(
      .invalidAlarmTime(hour: 24, minute: 0),
      from: useCase,
      request: CompleteOnboardingRequest(
        suggestionInput: RoutineSuggestionInput(
          wakeUpHour: 24,
          wakeUpMinute: 0,
          weekdays: [.monday]
        ),
        selectedVoice: .moru
      )
    )
    await assertCompleteOnboardingError(
      .emptyWeekdays,
      from: useCase,
      request: CompleteOnboardingRequest(
        suggestionInput: RoutineSuggestionInput(weekdays: []),
        selectedVoice: .moru
      )
    )
    await assertCompleteOnboardingError(
      .unavailableVoice("remote-pro-voice"),
      from: useCase,
      request: CompleteOnboardingRequest(
        suggestionInput: RoutineSuggestionInput(),
        selectedVoice: VoiceProfile(
          id: "remote-pro-voice",
          displayName: "서버 목소리",
          localeIdentifier: "ko-KR"
        )
      )
    )

    XCTAssertTrue(alarmScheduleMutator.events.isEmpty)
    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())
    XCTAssertEqual(try dependencies.routineRepository.fetchActiveRoutines(), [])
  }

  @MainActor
  func testCompleteOnboardingUseCaseDoesNotSaveWhenNotificationSchedulingIsDenied() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let alarmScheduleMutator = SpyAlarmScheduleMutator(outcome: .permissionDenied)
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
    )

    do {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(weekdays: [.monday]),
          selectedVoice: .yuna
        )
      )
      XCTFail("Expected notification permission denial.")
    } catch {
      XCTAssertEqual(error as? NotificationAlarmMutationError, .permissionDenied)
    }

    XCTAssertEqual(alarmScheduleMutator.events, [.commitStarted, .permissionDenied])
    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())
    XCTAssertEqual(try dependencies.routineRepository.fetchActiveRoutines(), [])
  }

  @MainActor
  func testCompleteOnboardingUseCaseDoesNotSaveWhenNotificationSchedulingFails() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let alarmScheduleMutator = SpyAlarmScheduleMutator(outcome: .schedulingFailure)
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
    )

    do {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(weekdays: [.monday]),
          selectedVoice: .yuna
        )
      )
      XCTFail("Expected notification scheduling failure.")
    } catch {
      XCTAssertEqual(error as? NotificationAlarmMutationError, .platformFailure)
    }

    XCTAssertEqual(alarmScheduleMutator.events, [.commitStarted, .schedulingFailed])
    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())
    XCTAssertEqual(try dependencies.routineRepository.fetchActiveRoutines(), [])
  }

  @MainActor
  func testFrozenMutationDoesNotSaveOnboardingLocally() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let alarmScheduleMutator = SpyAlarmScheduleMutator()
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: dependencies.onboardingRepository,
      routineSuggestionService: dependencies.routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
    )
    let token = try await alarmScheduleMutator.freezeAndDrain()
    defer {
      alarmScheduleMutator.thaw(token)
    }

    do {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(weekdays: [.monday]),
          selectedVoice: .yuna
        )
      )
      XCTFail("Expected frozen notification mutation.")
    } catch {
      XCTAssertEqual(error as? NotificationAlarmMutationError, .mutationFrozen)
    }

    XCTAssertTrue(alarmScheduleMutator.events.isEmpty)
    XCTAssertNil(try dependencies.localProfileRepository.fetchProfile())
    XCTAssertEqual(try dependencies.routineRepository.fetchActiveRoutines(), [])
  }

  @MainActor
  func testCompleteOnboardingUseCaseDoesNotCompleteWhenLocalSaveFails() async throws {
    let onboardingRepository = FailingOnboardingRepository()
    let alarmScheduleMutator = SpyAlarmScheduleMutator()
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: onboardingRepository,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      alarmScheduleMutator: alarmScheduleMutator
    )

    do {
      _ = try await useCase.execute(
        CompleteOnboardingRequest(
          suggestionInput: RoutineSuggestionInput(weekdays: [.monday]),
          selectedVoice: .yuna
        )
      )
      XCTFail("Expected local save failure.")
    } catch {
      XCTAssertEqual(error as? NotificationAlarmMutationError, .localCommitFailure)
    }

    XCTAssertEqual(onboardingRepository.saveCompletionCallCount, 1)
    XCTAssertEqual(
      alarmScheduleMutator.events,
      [.commitStarted, .platformSucceeded, .localCommitStarted, .localCommitFailed]
    )
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
  func testOnboardingViewModelCompletesExactlyOnceWithTheSavedRoutineID() async throws {
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
    XCTAssertTrue(viewModel.isSaving)
    XCTAssertFalse(viewModel.canAdvance)
    viewModel.primaryButtonDidTap()
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(useCase.executeCallCount, 1)
    XCTAssertEqual(completionCount, 1)
    XCTAssertEqual(completedRoutineID, useCase.resultRoutineIDs.first)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpHour, 6)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpMinute, 40)
    XCTAssertEqual(useCase.requests.first?.selectedVoice, .yuna)
  }

  @MainActor
  func testOnboardingViewModelLeavesCompletionAvailableAfterFailure() async {
    let useCase = SpyCompleteOnboardingUseCase(outcome: .notificationDenied)
    var completionCount = 0
    let viewModel = OnboardingViewModel(
      step: .completion,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: useCase
    ) { _ in
      completionCount += 1
    }

    viewModel.completeButtonDidTap()
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(useCase.executeCallCount, 1)
    XCTAssertEqual(completionCount, 0)
    XCTAssertFalse(viewModel.isSaving)
    XCTAssertTrue(viewModel.canAdvance)
    XCTAssertEqual(
      viewModel.errorMessage,
      OnboardingCompletionTestError.notificationDenied.errorDescription
    )
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
        routineSuggestionService: dependencies.routineSuggestionService,
        alarmScheduleMutator: SpyAlarmScheduleMutator()
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

      XCTAssertEqual(sessionStore.phase, .alarmRepairRequired)
      XCTAssertFalse(SessionStore.isOnboardingComplete(snapshot: snapshot))
      XCTAssertEqual(profile.selectedVoice, .yuna)
      XCTAssertEqual(activeRoutine.id, routineID)
      XCTAssertTrue(activeRoutine.isActive)
      XCTAssertEqual(activeRoutine.alarmSchedule?.isEnabled, true)
      XCTAssertEqual(activeRoutine.steps.count, 10)
      XCTAssertEqual(snapshot.platformStates, [])
    }
  }
  @MainActor
  private func assertCompleteOnboardingError(
    _ expected: CompleteOnboardingError,
    from useCase: CompleteOnboardingUseCase,
    request: CompleteOnboardingRequest
  ) async {
    do {
      _ = try await useCase.execute(request)
      XCTFail("Expected onboarding validation failure.")
    } catch {
      XCTAssertEqual(error as? CompleteOnboardingError, expected)
    }
  }

}

@MainActor
private final class SpyCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  enum Outcome {
    case success
    case notificationDenied
  }

  private let outcome: Outcome
  private(set) var executeCallCount = 0
  private(set) var requests: [CompleteOnboardingRequest] = []
  private(set) var resultRoutineIDs: [UUID] = []

  init(outcome: Outcome = .success) {
    self.outcome = outcome
  }

  func execute(_ request: CompleteOnboardingRequest) async throws -> CompleteOnboardingResult {
    executeCallCount += 1
    requests.append(request)

    if case .notificationDenied = outcome {
      throw OnboardingCompletionTestError.notificationDenied
    }

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

private enum OnboardingCompletionTestError: LocalizedError {
  case notificationDenied

  var errorDescription: String? {
    "알림 권한을 허용해 주세요."
  }
}


private enum TestOnboardingRepositoryError: Error, Equatable {
  case saveFailed
}

@MainActor
private final class SpyAlarmScheduleMutator: AlarmScheduleMutating {
  enum Outcome {
    case success
    case permissionDenied
    case schedulingFailure
  }

  enum Event: Equatable {
    case commitStarted
    case permissionDenied
    case schedulingFailed
    case platformSucceeded
    case localCommitStarted
    case localCommitFinished
    case localCommitFailed
  }

  var outcome: Outcome
  private(set) var events: [Event] = []
  private(set) var committedRoutineIDs: [UUID] = []
  private var freezeToken: AlarmMutationFreezeToken?

  init(outcome: Outcome = .success) {
    self.outcome = outcome
  }

  func commit(
    routines: [Routine],
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try ensureMutationAllowed()
    events.append(.commitStarted)
    committedRoutineIDs.append(contentsOf: routines.map(\.id))

    switch outcome {
    case .permissionDenied:
      events.append(.permissionDenied)
      throw NotificationAlarmMutationError.permissionDenied
    case .schedulingFailure:
      events.append(.schedulingFailed)
      throw NotificationAlarmMutationError.platformFailure
    case .success:
      events.append(.platformSucceeded)
    }

    events.append(.localCommitStarted)
    do {
      try localCommit()
      events.append(.localCommitFinished)
    } catch {
      events.append(.localCommitFailed)
      throw NotificationAlarmMutationError.localCommitFailure
    }
  }

  private func ensureMutationAllowed() throws {
    guard freezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
  }

  func delete(
    routineID: UUID,
    scheduleID: UUID?,
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try ensureMutationAllowed()
    try localCommit()
  }

  func reconcile(routines: [Routine]) async throws {
    try ensureMutationAllowed()
  }

  func freezeAndDrain() async throws -> AlarmMutationFreezeToken {
    guard freezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }

    let token = AlarmMutationFreezeToken()
    freezeToken = token
    return token
  }

  func cancelAll(
    scheduleIDs: [UUID],
    using token: AlarmMutationFreezeToken
  ) async throws {
    guard freezeToken == token else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
  }

  func thaw(_ token: AlarmMutationFreezeToken) {
    guard freezeToken == token else {
      return
    }

    freezeToken = nil
  }

  func permissionState() async -> AlarmNotificationPermissionState {
    .authorized
  }
}

@MainActor
private final class FailingOnboardingRepository: OnboardingRepository {
  private(set) var saveCompletionCallCount = 0

  func fetchProfile() throws -> LocalProfile? {
    nil
  }

  func saveCompletion(profile: LocalProfile, routine: Routine) throws {
    saveCompletionCallCount += 1
    throw TestOnboardingRepositoryError.saveFailed
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
