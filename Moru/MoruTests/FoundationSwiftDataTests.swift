//
//  FoundationSwiftDataTests.swift
//  MoruTests
//
//  Created by Codex on 7/6/26.
//

import SwiftData
import XCTest
@testable import Moru

final class FoundationSwiftDataTests: XCTestCase {
  @MainActor
  func testDomainDefaultsUseLocalOnlySync() throws {
    let routine = Routine(name: "Morning", steps: [])

    XCTAssertEqual(routine.sync?.status, .localOnly)
    XCTAssertNil(routine.sync?.remoteID)
    XCTAssertNil(routine.sync?.lastSyncedAt)
    XCTAssertNil(routine.sync?.remoteRevision)
  }

  @MainActor
  func testRoutineRunCompletionRateUsesResults() throws {
    let completedResult = RoutineStepResult(
      stepID: UUID(),
      stepTitle: "물 마시기",
      stepType: .confirm,
      completedAt: Date()
    )
    let skippedResult = RoutineStepResult(
      stepID: UUID(),
      stepTitle: "명상",
      stepType: .timer,
      completedAt: Date(),
      skipped: true
    )
    let pendingResult = RoutineStepResult(
      stepID: UUID(),
      stepTitle: "다짐 말하기",
      stepType: .input
    )
    let run = RoutineRun(
      routineID: UUID(),
      routineName: "Morning",
      results: [completedResult, skippedResult, pendingResult]
    )

    XCTAssertEqual(run.completionRate, 1.0 / 3.0, accuracy: 0.0001)
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
        status: .pendingUpload,
        lastSyncedAt: Date(),
        remoteRevision: "rev-1"
      )
    )

    let persisted = SwiftDataMapper.makePersistedRoutine(from: routine)
    let mapped = SwiftDataMapper.makeDomainRoutine(from: persisted)

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
    let routine = try LocalTemplateSuggestionService().makeRoutine(
      from: RoutineSuggestionInput(routineName: "아침 시작")
    )

    try repository.saveRoutine(routine)
    let fetched = try XCTUnwrap(repository.routine(id: routine.id))
    XCTAssertEqual(fetched.name, "아침 시작")
    XCTAssertEqual(fetched.steps.count, 3)
    XCTAssertTrue(fetched.isActive)

    try repository.updateRoutineActivation(id: routine.id, isActive: false)
    let toggled = try XCTUnwrap(repository.routine(id: routine.id))
    XCTAssertFalse(toggled.isActive)
  }

  @MainActor
  func testDeletingRoutineCascadesStepsAndAlarmButKeepsRunSnapshot() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let routineRepository = SwiftDataRoutineRepository(modelContext: context)
    let runRepository = SwiftDataRoutineRunRepository(modelContext: context)
    let routine = try LocalTemplateSuggestionService().makeRoutine(
      from: RoutineSuggestionInput(routineName: "보존할 이름")
    )
    let run = RoutineRun(
      routineID: routine.id,
      routineName: routine.name,
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
  }

  @MainActor
  func testLocalTemplateSuggestionCreatesThreeStepTypes() throws {
    let service = LocalTemplateSuggestionService()
    let routine = try service.makeRoutine(
      from: RoutineSuggestionInput(
        routineName: "",
        goalTags: ["mind"],
        wakeUpHour: 6,
        wakeUpMinute: 45,
        weekdays: [.saturday]
      )
    )

    XCTAssertEqual(routine.name, "상쾌한 아침 루틴")
    XCTAssertEqual(routine.goalTags, ["mind"])
    XCTAssertEqual(routine.alarmSchedule?.hour, 6)
    XCTAssertEqual(routine.alarmSchedule?.minute, 45)
    XCTAssertEqual(routine.alarmSchedule?.weekdays, [.saturday])
    XCTAssertEqual(Set(routine.steps.map(\.type)), Set(RoutineStepType.allCases))
  }

  @MainActor
  private func makeContainer() throws -> ModelContainer {
    try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
  }
}
