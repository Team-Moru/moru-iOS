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
  func testCompleteOnboardingUseCaseSavesProfileActiveRoutineAndEnabledAlarm() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let useCase = CompleteOnboardingUseCase(
      localProfileRepository: dependencies.localProfileRepository,
      routineRepository: dependencies.routineRepository,
      routineSuggestionService: dependencies.routineSuggestionService
    )

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
        selectedVoice: .moru
      )
    )

    let savedProfile = try XCTUnwrap(try dependencies.localProfileRepository.fetchProfile())
    let activeRoutines = try dependencies.routineRepository.fetchActiveRoutines()
    let savedRoutine = try XCTUnwrap(activeRoutines.first)

    XCTAssertEqual(result.profile.selectedVoice, .moru)
    XCTAssertEqual(savedProfile.selectedVoice, .moru)
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
    XCTAssertTrue(
      SessionStore.isOnboardingComplete(
        profile: savedProfile,
        activeRoutines: activeRoutines
      )
    )
  }

  @MainActor
  func testCompleteOnboardingUseCaseRejectsInvalidAlarmAndUnavailableVoiceBeforeSaving() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    let useCase = CompleteOnboardingUseCase(
      localProfileRepository: dependencies.localProfileRepository,
      routineRepository: dependencies.routineRepository,
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
          selectedVoice: .moru
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
          selectedVoice: .moru
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
    XCTAssertEqual(Set(first.steps.map(\.type)), Set(RoutineStepType.allCases))
    XCTAssertEqual(first.sync?.status, .localOnly)
    XCTAssertNil(first.sync?.remoteID)
  }

  @MainActor
  func testOnboardingViewModelMovesThroughStepsAndSavesExactlyOnce() throws {
    let useCase = SpyCompleteOnboardingUseCase()
    var completionCount = 0
    let viewModel = OnboardingViewModel(
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      completeOnboardingUseCase: useCase
    ) {
      completionCount += 1
    }

    XCTAssertEqual(viewModel.step, .experience)

    viewModel.selectExperience(.wantsRecommendation)
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .goals)

    viewModel.toggleGoal(tag: "mind")
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .suggestedRoutine)
    XCTAssertNotNil(viewModel.draft.previewRoutine)

    viewModel.advance()
    XCTAssertEqual(viewModel.step, .duration)
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .freeform)

    viewModel.draft.freeformText = "명상하고 일기를 쓰고 싶어요"
    viewModel.toggleKeyword("명상")
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .organizing)
    XCTAssertFalse(
      viewModel.draft.previewRoutine?.summary.localizedCaseInsensitiveContains("AI") ?? true
    )

    viewModel.advance()
    XCTAssertEqual(viewModel.step, .review)
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .alarm)

    viewModel.updateAlarm(hour: 6, minute: 40)
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .voice)

    viewModel.selectVoice(.moru)
    viewModel.advance()
    XCTAssertEqual(viewModel.step, .completion)

    viewModel.advance()
    viewModel.advance()

    XCTAssertEqual(useCase.executeCallCount, 1)
    XCTAssertEqual(completionCount, 1)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpHour, 6)
    XCTAssertEqual(useCase.requests.first?.suggestionInput.wakeUpMinute, 40)
    XCTAssertEqual(useCase.requests.first?.selectedVoice, .moru)
  }

  @MainActor
  func testSwiftDataRelaunchPersistenceAfterOnboardingCompletion() throws {
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
        localProfileRepository: dependencies.localProfileRepository,
        routineRepository: dependencies.routineRepository,
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
          selectedVoice: .moru
        )
      )
      routineID = result.routine.id
    }

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(modelContext: container.mainContext)
      let sessionStore = SessionStore(
        localProfileRepository: dependencies.localProfileRepository,
        routineRepository: dependencies.routineRepository
      )

      sessionStore.load()

      let profile = try XCTUnwrap(sessionStore.profile)
      let activeRoutine = try XCTUnwrap(try dependencies.routineRepository.fetchActiveRoutines().first)

      XCTAssertEqual(sessionStore.phase, .ready)
      XCTAssertEqual(profile.selectedVoice, .moru)
      XCTAssertEqual(activeRoutine.id, routineID)
      XCTAssertTrue(activeRoutine.isActive)
      XCTAssertEqual(activeRoutine.alarmSchedule?.isEnabled, true)
      XCTAssertEqual(activeRoutine.steps.count, 3)
    }
  }
}

@MainActor
private final class SpyCompleteOnboardingUseCase: CompleteOnboardingUseCaseProtocol {
  private(set) var executeCallCount = 0
  private(set) var requests: [CompleteOnboardingRequest] = []

  func execute(_ request: CompleteOnboardingRequest) throws -> CompleteOnboardingResult {
    executeCallCount += 1
    requests.append(request)

    return CompleteOnboardingResult(
      profile: LocalProfile(selectedVoice: request.selectedVoice),
      routine: try LocalTemplateSuggestionService.shared.makeRoutine(from: request.suggestionInput)
    )
  }
}
