//
//  SessionEmptyStateTests.swift
//  MoruTests
//

import Foundation
import SwiftData
import XCTest
@testable import Moru

final class SessionEmptyStateTests: XCTestCase {
  @MainActor
  func testProfileWithoutRoutinesLoadsReadyAfterRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let storeURL = directory.appendingPathComponent("Moru.store")

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(modelContext: container.mainContext)
      try dependencies.localProfileRepository.saveProfile(LocalProfile())

      let routine = Routine(
        name: "마지막 루틴",
        steps: [
          RoutineStep(
            type: .confirm,
            title: "물 마시기",
            order: 0
          ),
        ]
      )
      try dependencies.routineRepository.saveRoutine(routine)
      try dependencies.routineRepository.deleteRoutine(id: routine.id)
      XCTAssertEqual(try dependencies.routineRepository.fetchRoutines(), [])
    }

    do {
      let container = try ModelContainer.moruContainer(storeURL: storeURL)
      let dependencies = DependencyContainer.local(modelContext: container.mainContext)
      let sessionStore = dependencies.makeSessionStore()

      sessionStore.load()

      XCTAssertNotNil(sessionStore.profile)
      XCTAssertEqual(sessionStore.phase, .ready)
      XCTAssertEqual(try dependencies.routineRepository.fetchRoutines(), [])
    }
  }

  @MainActor
  func testLastRoutineDeletionImmediatelyProducesMainEmptyStates() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    try dependencies.localProfileRepository.saveProfile(LocalProfile(displayName: "모루"))
    let routine = Routine(
      name: "마지막 루틴",
      steps: [
        RoutineStep(
          type: .confirm,
          title: "물 마시기",
          order: 0
        ),
      ]
    )
    try dependencies.routineRepository.saveRoutine(routine)

    let routineViewModel = RoutineSettingViewModel(dependencies: dependencies)
    routineViewModel.load()
    XCTAssertEqual(routineViewModel.state.routines.count, 1)

    let didDelete = await routineViewModel.deleteRoutine(id: routine.id)
    XCTAssertTrue(didDelete)
    XCTAssertTrue(routineViewModel.state.routines.isEmpty)

    let homeViewModel = HomeViewModel(
      loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
        routineRepository: dependencies.routineRepository,
        routineRunRepository: dependencies.routineRunRepository,
        localProfileRepository: dependencies.localProfileRepository
      )
    )
    homeViewModel.load()

    XCTAssertEqual(homeViewModel.state.loadState, .empty)
    XCTAssertEqual(homeViewModel.state.userName, "모루")

    let sessionStore = dependencies.makeSessionStore()
    sessionStore.load()
    XCTAssertEqual(sessionStore.phase, .ready)
  }

  @MainActor
  func testDisabledRoutineAndMissingAlarmKeepSessionReady() throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    try dependencies.localProfileRepository.saveProfile(LocalProfile())
    try dependencies.routineRepository.saveRoutines([
      Routine(
        name: "비활성 루틴",
        steps: [],
        alarmSchedule: AlarmSchedule(
          hour: 7,
          minute: 0,
          weekdays: [.monday],
          isEnabled: false
        ),
        isActive: false
      ),
      Routine(
        name: "알람 없는 루틴",
        steps: [],
        alarmSchedule: nil,
        isActive: true
      ),
    ])

    let sessionStore = dependencies.makeSessionStore()
    sessionStore.load()

    XCTAssertEqual(sessionStore.phase, .ready)
  }

  @MainActor
  func testWholeResetDeletesProfileAndRequiresOnboarding() async throws {
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let dependencies = DependencyContainer.local(modelContext: container.mainContext)
    try dependencies.localProfileRepository.saveProfile(LocalProfile())

    let resetRepository = try XCTUnwrap(dependencies.localDataResetRepository)
    let resetUseCase = ResetLocalDataUseCase(
      localDataResetRepository: resetRepository,
      alarmService: UnavailableProfileAlarmService()
    )
    try await resetUseCase.execute()

    let sessionStore = dependencies.makeSessionStore()
    sessionStore.load()

    XCTAssertNil(sessionStore.profile)
    XCTAssertEqual(sessionStore.phase, .onboardingRequired)
  }
}
