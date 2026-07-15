//
//  FoundationSwiftDataTests.swift
//  MoruTests
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class FoundationSwiftDataTests: XCTestCase {
  @MainActor
  func testBootstrapFailureDoesNotCrash() {
    let bootstrapper = AppBootstrapper {
      throw TestBootstrapError.storageUnavailable
    }

    bootstrapper.start()

    switch bootstrapper.state {
    case .failed(let failure):
      XCTAssertEqual(failure.message, "저장소를 초기화할 수 없어요. 다시 시도해 주세요.")
      XCTAssertFalse(failure.message.contains("storage unavailable"))
    case .idle, .loading, .ready:
      XCTFail("Bootstrap should surface storage failures instead of creating runtime.")
    }
  }

  @MainActor
  func testDomainDefaultsUseLocalOnlySync() throws {
    let routine = Routine(name: "Morning", steps: [])
    let run = RoutineRun(routineID: routine.id, routineName: routine.name)

    XCTAssertEqual(routine.sync?.status, .localOnly)
    XCTAssertNil(routine.sync?.remoteID)
    XCTAssertNil(routine.sync?.lastSyncedAt)
    XCTAssertNil(routine.sync?.remoteRevision)
    XCTAssertEqual(run.sync?.status, .localOnly)
    XCTAssertNil(run.sync?.remoteID)
    XCTAssertNil(run.sync?.lastSyncedAt)
    XCTAssertNil(run.sync?.remoteRevision)
    XCTAssertEqual(run.plannedStepCount, 0)
    XCTAssertEqual(run.completionRate, 0)
  }

  @MainActor
  func testRoutineRunCompletionRateUsesPlannedSnapshotForPartialRuns() throws {
    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(routineName: "아침 시작")
    )
    let completedResult = RoutineStepResult(
      stepID: routine.steps[0].id,
      stepTitle: routine.steps[0].title,
      stepType: routine.steps[0].type,
      completedAt: Date()
    )
    let skippedResult = RoutineStepResult(
      stepID: routine.steps[1].id,
      stepTitle: routine.steps[1].title,
      stepType: routine.steps[1].type,
      completedAt: Date(),
      skipped: true
    )
    let strayResult = RoutineStepResult(
      stepID: UUID(),
      stepTitle: "현재 루틴에 없는 스텝",
      stepType: .confirm,
      completedAt: Date()
    )
    let run = RoutineRun(
      routine: routine,
      results: [completedResult, skippedResult, strayResult],
      endedEarly: true
    )

    XCTAssertEqual(run.plannedStepCount, routine.steps.count)
    XCTAssertEqual(run.completionRate, 1.0 / Double(routine.steps.count), accuracy: 0.0001)
  }

  @MainActor
  func testRoutineRunInitializerCapturesRoutineSnapshot() throws {
    let firstStep = RoutineStep(
      type: .confirm,
      title: "첫 스텝",
      order: 0
    )
    let secondStep = RoutineStep(
      type: .timer,
      title: "두 번째 스텝",
      order: 1,
      estimatedSeconds: 60
    )
    let routine = Routine(
      name: "스냅샷 루틴",
      steps: [secondStep, firstStep],
      alarmSchedule: makeAlarm(isEnabled: true)
    )

    let run = RoutineRun(routine: routine)

    XCTAssertEqual(run.routineID, routine.id)
    XCTAssertEqual(run.routineName, routine.name)
    XCTAssertEqual(run.plannedSteps.map(\.stepID), [firstStep.id, secondStep.id])
    XCTAssertEqual(run.plannedSteps.map(\.stepTitle), ["첫 스텝", "두 번째 스텝"])
  }

  @MainActor
  func testSessionStoreRequiresProfileActiveRoutineAndEnabledAlarmBeforeReady() throws {
    let profile = LocalProfile()
    let noAlarmRoutine = makeRoutine(
      name: "알람 없음",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    let disabledAlarmRoutine = makeRoutine(
      name: "꺼진 알람",
      createdAt: Date(timeIntervalSince1970: 2),
      alarmSchedule: makeAlarm(isEnabled: false)
    )
    let readyRoutine = makeRoutine(
      name: "완료 루틴",
      createdAt: Date(timeIntervalSince1970: 3),
      alarmSchedule: makeAlarm(isEnabled: true)
    )

    XCTAssertFalse(
      SessionStore.isOnboardingComplete(
        profile: nil,
        activeRoutines: [readyRoutine]
      )
    )
    XCTAssertFalse(
      SessionStore.isOnboardingComplete(
        profile: profile,
        activeRoutines: []
      )
    )
    XCTAssertFalse(
      SessionStore.isOnboardingComplete(
        profile: profile,
        activeRoutines: [noAlarmRoutine]
      )
    )
    XCTAssertFalse(
      SessionStore.isOnboardingComplete(
        profile: profile,
        activeRoutines: [disabledAlarmRoutine]
      )
    )
    XCTAssertTrue(
      SessionStore.isOnboardingComplete(
        profile: profile,
        activeRoutines: [readyRoutine]
      )
    )

  }

  @MainActor
  func testDefaultProfileAloneDoesNotCompleteOnboarding() throws {
    XCTAssertFalse(
      SessionStore.isOnboardingComplete(
        profile: LocalProfile(),
        activeRoutines: []
      )
    )
  }

  @MainActor
  func testMapperRoundTripKeepsRoutineValuesAndSanitizesSync() throws {
    let routineID = UUID()
    let stepID = UUID()
    let alarmID = UUID()
    let createdAt = Date(timeIntervalSince1970: 100)
    let updatedAt = Date(timeIntervalSince1970: 200)
    let routine = Routine(
      id: routineID,
      name: "출근 전 루틴",
      summary: "짧은 준비 루틴",
      goalTags: ["energy", "habit"],
      steps: [
        RoutineStep(
          id: stepID,
          type: .timer,
          title: "스트레칭",
          instruction: "가볍게 몸을 풀어요.",
          order: 0,
          estimatedSeconds: 90
        )
      ],
      alarmSchedule: AlarmSchedule(
        id: alarmID,
        hour: 7,
        minute: 30,
        weekdays: [.monday, .wednesday],
        soundName: "soft-start"
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
      sync: SyncMetadata(
        remoteID: "server-id",
        status: .localOnly,
        lastSyncedAt: Date(),
        remoteRevision: "rev-1"
      )
    )

    let persisted = SwiftDataMapper.makePersistedRoutine(from: routine)
    let mapped = try SwiftDataMapper.makeDomainRoutine(from: persisted)

    XCTAssertEqual(mapped.id, routineID)
    XCTAssertEqual(mapped.name, "출근 전 루틴")
    XCTAssertEqual(mapped.goalTags, ["energy", "habit"])
    XCTAssertEqual(mapped.steps.first?.id, stepID)
    XCTAssertEqual(mapped.steps.first?.type, .timer)
    XCTAssertEqual(mapped.alarmSchedule?.id, alarmID)
    XCTAssertEqual(mapped.alarmSchedule?.weekdays, [.monday, .wednesday])
    XCTAssertEqual(mapped.sync?.status, .localOnly)
    XCTAssertNil(mapped.sync?.remoteID)
    XCTAssertNil(mapped.sync?.lastSyncedAt)
    XCTAssertNil(mapped.sync?.remoteRevision)
  }

  @MainActor
  func testSwiftDataRoutineRepositorySavesFetchesAndTogglesRoutine() throws {
    let container = try makeContainer()
    let repository = SwiftDataRoutineRepository(modelContext: container.mainContext)
    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(routineName: "아침 시작")
    )

    try repository.saveRoutine(routine)
    let fetched = try XCTUnwrap(repository.routine(id: routine.id))
    XCTAssertEqual(fetched.name, "아침 시작")
    XCTAssertEqual(fetched.steps.count, routine.steps.count)
    XCTAssertEqual(
      fetched.steps.map(\.presetItemID),
      routine.steps.map(\.presetItemID)
    )
    XCTAssertTrue(fetched.isActive)

    try repository.updateRoutineActivation(id: routine.id, isActive: false)
    let toggled = try XCTUnwrap(repository.routine(id: routine.id))
    XCTAssertFalse(toggled.isActive)
  }

  @MainActor
  func testSaveRoutineRunUseCaseKeepsOneRunForRepeatedRequest() throws {
    let container = try makeContainer()
    let repository = SwiftDataRoutineRunRepository(modelContext: container.mainContext)
    let useCase = SaveRoutineRunUseCase(routineRunRepository: repository)
    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(routineName: "재시도 루틴")
    )
    let request = SaveRoutineRunRequest(
      runID: UUID(),
      routine: routine,
      startedAt: Date(timeIntervalSince1970: 100),
      completedAt: Date(timeIntervalSince1970: 200),
      results: [],
      endedEarly: false
    )

    let first = try useCase.execute(request)
    let second = try useCase.execute(request)
    let savedRuns = try repository.fetchRuns()

    XCTAssertEqual(first.id, request.runID)
    XCTAssertEqual(second.id, request.runID)
    XCTAssertEqual(savedRuns.map(\.id), [request.runID])
  }

  @MainActor
  func testDeletingRoutineHardDeletesStepsAndAlarmButKeepsRunSnapshot() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let routineRepository = SwiftDataRoutineRepository(modelContext: context)
    let runRepository = SwiftDataRoutineRunRepository(modelContext: context)
    let routine = try LocalTemplateSuggestionService.shared.makeRoutine(
      from: RoutineSuggestionInput(routineName: "보존할 이름")
    )
    let run = RoutineRun(
      routine: routine,
      completedAt: Date(),
      results: [
        RoutineStepResult(
          stepID: routine.steps[0].id,
          stepTitle: routine.steps[0].title,
          stepType: routine.steps[0].type,
          completedAt: Date()
        )
      ]
    )

    try routineRepository.saveRoutine(routine)
    try runRepository.saveRun(run)
    try routineRepository.deleteRoutine(id: routine.id)

    XCTAssertNil(try routineRepository.routine(id: routine.id))
    XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedRoutineStep>()).count, 0)
    XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedAlarmSchedule>()).count, 0)

    let savedRun = try XCTUnwrap(try runRepository.run(id: run.id))
    XCTAssertEqual(savedRun.routineID, routine.id)
    XCTAssertEqual(savedRun.routineName, "보존할 이름")
    XCTAssertEqual(savedRun.plannedStepCount, routine.steps.count)
    XCTAssertEqual(savedRun.plannedSteps.map(\.stepTitle), routine.steps.map(\.title))
    XCTAssertEqual(savedRun.completionRate, 1.0 / Double(routine.steps.count), accuracy: 0.0001)
  }

  @MainActor
  func testRoutineRunRepositoryRejectsRunsWithoutPlannedSnapshot() throws {
    let container = try makeContainer()
    let runRepository = SwiftDataRoutineRunRepository(modelContext: container.mainContext)
    let runWithoutSnapshot = RoutineRun(
      routineID: UUID(),
      routineName: "스냅샷 없는 실행",
      results: [
        RoutineStepResult(
          stepID: UUID(),
          stepTitle: "저장되면 안 되는 결과",
          stepType: .confirm,
          completedAt: Date()
        )
      ]
    )

    XCTAssertThrowsError(try runRepository.saveRun(runWithoutSnapshot)) {
      XCTAssertEqual($0 as? RepositoryContractError, .routineRunSnapshotRequired)
    }
    XCTAssertEqual(try runRepository.fetchRuns().count, 0)
  }

  @MainActor
  func testRepositoryQueryAPIsUseShapedResults() throws {
    let container = try makeContainer()
    let routineRepository = SwiftDataRoutineRepository(modelContext: container.mainContext)
    let runRepository = SwiftDataRoutineRunRepository(modelContext: container.mainContext)
    var activeRoutine = makeRoutine(
      name: "활성 루틴",
      createdAt: Date(timeIntervalSince1970: 10)
    )
    var inactiveRoutine = makeRoutine(
      name: "비활성 루틴",
      createdAt: Date(timeIntervalSince1970: 20),
      isActive: false
    )
    activeRoutine.updatedAt = activeRoutine.createdAt
    inactiveRoutine.updatedAt = inactiveRoutine.createdAt

    try routineRepository.saveRoutine(activeRoutine)
    try routineRepository.saveRoutine(inactiveRoutine)

    let activeRoutines = try routineRepository.fetchActiveRoutines()
    XCTAssertEqual(activeRoutines.map(\.id), [activeRoutine.id])

    let activeOldRun = makeRun(
      routine: activeRoutine,
      startedAt: Date(timeIntervalSince1970: 100)
    )
    let inactiveRun = makeRun(
      routine: inactiveRoutine,
      startedAt: Date(timeIntervalSince1970: 200)
    )
    let activeLatestRun = makeRun(
      routine: activeRoutine,
      startedAt: Date(timeIntervalSince1970: 300)
    )

    try runRepository.saveRun(activeOldRun)
    try runRepository.saveRun(inactiveRun)
    try runRepository.saveRun(activeLatestRun)

    let recentRuns = try runRepository.fetchRecentRuns(limit: 2)
    XCTAssertEqual(recentRuns.map(\.id), [activeLatestRun.id, inactiveRun.id])

    let rangeRuns = try runRepository.fetchRuns(
      from: Date(timeIntervalSince1970: 150),
      to: Date(timeIntervalSince1970: 350)
    )
    XCTAssertEqual(rangeRuns.map(\.id), [activeLatestRun.id, inactiveRun.id])

    let routineRangeRuns = try runRepository.fetchRuns(
      for: activeRoutine.id,
      from: Date(timeIntervalSince1970: 50),
      to: Date(timeIntervalSince1970: 350)
    )
    XCTAssertEqual(routineRangeRuns.map(\.id), [activeLatestRun.id, activeOldRun.id])

    let latestRun = try XCTUnwrap(try runRepository.latestRun(for: activeRoutine.id))
    XCTAssertEqual(latestRun.id, activeLatestRun.id)
  }

  @MainActor
  func testMapperThrowsForMalformedRawValues() throws {
    let malformedGoalsRoutine = makePersistedRoutine(goalTagsRawValue: "not-json")
    XCTAssertThrowsError(try SwiftDataMapper.makeDomainRoutine(from: malformedGoalsRoutine)) {
      XCTAssertEqual(
        $0 as? SwiftDataMappingError,
        .malformedStringArray(
          field: "PersistedRoutine.goalTagsRawValue",
          rawValue: "not-json"
        )
      )
    }

    let unknownStepRoutine = makePersistedRoutine(
      steps: [
        PersistedRoutineStep(
          id: UUID(),
          presetItemID: nil,
          typeRawValue: "voice",
          title: "잘못된 스텝",
          instruction: "",
          order: 0,
          estimatedSeconds: nil,
          isRequired: true
        )
      ]
    )
    XCTAssertThrowsError(try SwiftDataMapper.makeDomainRoutine(from: unknownStepRoutine)) {
      XCTAssertEqual(
        $0 as? SwiftDataMappingError,
        .unknownStepType(field: "PersistedRoutineStep.typeRawValue", rawValue: "voice")
      )
    }

    let unknownSyncRoutine = makePersistedRoutine(syncStatusRawValue: "pendingDelete")
    XCTAssertThrowsError(try SwiftDataMapper.makeDomainRoutine(from: unknownSyncRoutine)) {
      XCTAssertEqual(
        $0 as? SwiftDataMappingError,
        .unknownSyncStatus(rawValue: "pendingDelete")
      )
    }

    let remoteSyncRoutine = makePersistedRoutine(remoteID: "server-id")
    XCTAssertThrowsError(try SwiftDataMapper.makeDomainRoutine(from: remoteSyncRoutine)) {
      XCTAssertEqual(
        $0 as? SwiftDataMappingError,
        .nonLocalSyncMetadata(field: "remoteID")
      )
    }

    let malformedAlarmRoutine = makePersistedRoutine(
      alarmSchedule: PersistedAlarmSchedule(
        id: UUID(),
        hour: 7,
        minute: 0,
        weekdaysRawValue: "not-json",
        soundName: "moru-default",
        isEnabled: true,
        includeWeather: false,
        includeFortune: false
      )
    )
    XCTAssertThrowsError(try SwiftDataMapper.makeDomainRoutine(from: malformedAlarmRoutine)) {
      XCTAssertEqual(
        $0 as? SwiftDataMappingError,
        .malformedIntArray(
          field: "PersistedAlarmSchedule.weekdaysRawValue",
          rawValue: "not-json"
        )
      )
    }

    let invalidWeekdayRoutine = makePersistedRoutine(
      alarmSchedule: PersistedAlarmSchedule(
        id: UUID(),
        hour: 7,
        minute: 0,
        weekdaysRawValue: "[1,9]",
        soundName: "moru-default",
        isEnabled: true,
        includeWeather: false,
        includeFortune: false
      )
    )
    XCTAssertThrowsError(try SwiftDataMapper.makeDomainRoutine(from: invalidWeekdayRoutine)) {
      XCTAssertEqual(
        $0 as? SwiftDataMappingError,
        .invalidWeekdayRawValue(
          field: "PersistedAlarmSchedule.weekdaysRawValue",
          rawValue: 9
        )
      )
    }
  }

  @MainActor
  func testLocalTemplateSuggestionCreatesThreeStepTypes() throws {
    let service = LocalTemplateSuggestionService.shared
    let routine = try service.makeRoutine(
      from: RoutineSuggestionInput(
        routineName: "",
        goalTags: ["mind"],
        wakeUpHour: 6,
        wakeUpMinute: 45,
        weekdays: [.saturday]
      )
    )

    XCTAssertEqual(routine.name, "마음 안정 루틴")
    XCTAssertEqual(routine.goalTags, ["mind"])
    XCTAssertEqual(routine.alarmSchedule?.hour, 6)
    XCTAssertEqual(routine.alarmSchedule?.minute, 45)
    XCTAssertEqual(routine.alarmSchedule?.weekdays, [.saturday])
    XCTAssertEqual(Set(routine.steps.map(\.type)), Set(RoutineStepType.allCases))
  }

  @MainActor
  func testDependencyContainerExposesRepositoryContractsInsteadOfSwiftDataContext() throws {
    let modelContainer = try makeContainer()
    let dependencyContainer = DependencyContainer.local(modelContext: modelContainer.mainContext)

    assertRoutineRepository(dependencyContainer.routineRepository)
    assertRoutineRunRepository(dependencyContainer.routineRunRepository)
    assertLocalProfileRepository(dependencyContainer.localProfileRepository)
    assertOnboardingRepository(dependencyContainer.onboardingRepository)
    assertRoutineSuggestionService(dependencyContainer.routineSuggestionService)
  }

  private func assertRoutineRepository(_ dependency: any RoutineRepository) {}

  private func assertRoutineRunRepository(_ dependency: any RoutineRunRepository) {}

  private func assertLocalProfileRepository(_ dependency: any LocalProfileRepository) {}

  private func assertOnboardingRepository(_ dependency: any OnboardingRepository) {}

  private func assertRoutineSuggestionService(_ dependency: any RoutineSuggestionService) {}

  @MainActor
  private func makeContainer() throws -> ModelContainer {
    try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
  }

  @MainActor
  private func makeRoutine(
    name: String,
    createdAt: Date,
    isActive: Bool = true,
    alarmSchedule: AlarmSchedule? = nil
  ) -> Routine {
    Routine(
      name: name,
      steps: [
        RoutineStep(
          type: .confirm,
          title: "\(name) 확인",
          order: 0
        )
      ],
      alarmSchedule: alarmSchedule,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: createdAt
    )
  }

  @MainActor
  private func makeRun(routine: Routine, startedAt: Date) -> RoutineRun {
    RoutineRun(
      routine: routine,
      startedAt: startedAt,
      completedAt: startedAt.addingTimeInterval(60),
      results: [
        RoutineStepResult(
          stepID: routine.steps[0].id,
          stepTitle: routine.steps[0].title,
          stepType: routine.steps[0].type,
          completedAt: startedAt.addingTimeInterval(60)
        )
      ]
    )
  }

  @MainActor
  private func makeAlarm(isEnabled: Bool) -> AlarmSchedule {
    AlarmSchedule(
      hour: 7,
      minute: 0,
      weekdays: [.monday],
      isEnabled: isEnabled
    )
  }

  private func makePersistedRoutine(
    goalTagsRawValue: String = "[]",
    steps: [PersistedRoutineStep] = [],
    alarmSchedule: PersistedAlarmSchedule? = nil,
    syncStatusRawValue: String = SyncStatus.localOnly.rawValue,
    remoteID: String? = nil,
    lastSyncedAt: Date? = nil,
    remoteRevision: String? = nil
  ) -> PersistedRoutine {
    PersistedRoutine(
      id: UUID(),
      name: "저장된 루틴",
      summary: "",
      goalTagsRawValue: goalTagsRawValue,
      steps: steps,
      alarmSchedule: alarmSchedule,
      isActive: true,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      remoteID: remoteID,
      syncStatusRawValue: syncStatusRawValue,
      lastSyncedAt: lastSyncedAt,
      remoteRevision: remoteRevision
    )
  }

}

private enum TestBootstrapError: LocalizedError {
  case storageUnavailable

  var errorDescription: String? {
    "storage unavailable"
  }
}
