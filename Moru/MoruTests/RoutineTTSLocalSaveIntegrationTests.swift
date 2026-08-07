//
//  RoutineTTSLocalSaveIntegrationTests.swift
//  MoruTests
//

import XCTest

@testable import Moru

@MainActor
final class RoutineTTSLocalSaveIntegrationTests: XCTestCase {
  func testRoutineSettingSchedulesTTSOnlyAfterLocalSaveSucceeds()
    async throws {
    let repository = TTSLocalSaveRoutineRepository()
    let scheduler = TTSPreparationSchedulerSpy(
      routineRepository: repository
    )
    let routineID = UUID()
    let useCase = RoutineSettingUseCase(
      routineRepository: repository,
      routineTTSPreparationScheduler: scheduler
    )

    _ = try await useCase.saveRoutine(
      from: mutation(routineID: routineID)
    )

    XCTAssertEqual(scheduler.savedRoutineIDs, [routineID])
    XCTAssertTrue(scheduler.wasRoutinePersistedAtSaveCallback)

    repository.saveError = TTSLocalSaveTestError.persistence
    do {
      _ = try await useCase.saveRoutine(
        from: mutation(routineID: UUID())
      )
      XCTFail("Expected local persistence failure.")
    } catch {
      XCTAssertEqual(scheduler.savedRoutineIDs, [routineID])
    }
  }

  func testRoutineSettingInvalidatesTTSOnlyAfterLocalDeleteSucceeds()
    async throws {
    let routine = makeRoutine()
    let repository = TTSLocalSaveRoutineRepository(
      routines: [routine]
    )
    let scheduler = TTSPreparationSchedulerSpy(
      routineRepository: repository
    )
    let useCase = RoutineSettingUseCase(
      routineRepository: repository,
      routineTTSPreparationScheduler: scheduler
    )

    try await useCase.deleteRoutine(id: routine.id)

    XCTAssertEqual(scheduler.deletedRoutineIDs, [routine.id])
    XCTAssertTrue(scheduler.wasRoutineDeletedAtDeleteCallback)

    let failingRoutine = makeRoutine()
    repository.routines = [failingRoutine]
    repository.deleteError = TTSLocalSaveTestError.persistence
    do {
      try await useCase.deleteRoutine(id: failingRoutine.id)
      XCTFail("Expected local deletion failure.")
    } catch {
      XCTAssertEqual(scheduler.deletedRoutineIDs, [routine.id])
    }
  }

  func testOnboardingSchedulesTTSAfterAtomicLocalCompletion()
    async throws {
    let repository = TTSOnboardingRepositorySpy()
    let scheduler = TTSPreparationSchedulerSpy(
      completionRepository: repository
    )
    let preview = makeRoutine()
    let useCase = CompleteOnboardingUseCase(
      onboardingRepository: repository,
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      routineTTSPreparationScheduler: scheduler
    )
    let request = CompleteOnboardingRequest(
      suggestionInput: RoutineSuggestionInput(
        experience: .firstTime,
        routineName: "",
        goalTags: ["energy"],
        selectedKeywords: [],
        freeformText: "",
        wakeUpHour: 7,
        wakeUpMinute: 0,
        weekdays: [.monday]
      ),
      selectedVoice: .aoede,
      previewRoutine: preview
    )

    _ = try await useCase.execute(request)

    XCTAssertEqual(scheduler.savedRoutineIDs, [preview.id])
    XCTAssertTrue(scheduler.wasCompletionPersistedAtSaveCallback)
  }

  private func mutation(
    routineID: UUID
  ) -> RoutineSettingMutation {
    RoutineSettingMutation(
      routineID: routineID,
      name: "아침",
      summary: "",
      hour: 7,
      minute: 0,
      selectedWeekdays: [.monday],
      steps: [
        RoutineStepMutation(
          id: UUID(),
          type: .confirm,
          title: "물 마시기",
          estimatedMinutes: 1
        ),
      ],
      isActive: true
    )
  }

  private func makeRoutine() -> Routine {
    Routine(
      name: "아침",
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
        weekdays: [.monday]
      )
    )
  }
}

private enum TTSLocalSaveTestError: Error {
  case persistence
}

@MainActor
private final class TTSLocalSaveRoutineRepository:
  RoutineRepository {
  var routines: [Routine]
  var saveError: Error?
  var deleteError: Error?

  init(routines: [Routine] = []) {
    self.routines = routines
  }

  func fetchRoutines() throws -> [Routine] {
    routines
  }

  func fetchActiveRoutines() throws -> [Routine] {
    routines.filter(\.isActive)
  }

  func routine(id: UUID) throws -> Routine? {
    routines.first { $0.id == id }
  }

  func saveRoutine(_ routine: Routine) throws {
    if let saveError {
      throw saveError
    }
    try saveRoutines([routine])
  }

  func saveRoutines(_ routines: [Routine]) throws {
    if let saveError {
      throw saveError
    }
    for routine in routines {
      if let index = self.routines.firstIndex(
        where: { $0.id == routine.id }
      ) {
        self.routines[index] = routine
      } else {
        self.routines.append(routine)
      }
    }
  }

  func updateRoutineActivation(
    id: UUID,
    isActive: Bool
  ) throws {
    guard let index = routines.firstIndex(
      where: { $0.id == id }
    ) else {
      return
    }
    routines[index].isActive = isActive
  }

  func deleteRoutine(id: UUID) throws {
    if let deleteError {
      throw deleteError
    }
    routines.removeAll { $0.id == id }
  }
}

@MainActor
private final class TTSOnboardingRepositorySpy:
  OnboardingRepository {
  private(set) var profile: LocalProfile?
  private(set) var routine: Routine?

  func fetchProfile() throws -> LocalProfile? {
    profile
  }

  func saveCompletion(
    profile: LocalProfile,
    routine: Routine
  ) throws {
    self.profile = profile
    self.routine = routine
  }
}

@MainActor
private final class TTSPreparationSchedulerSpy:
  RoutineTTSPreparationScheduling {
  private weak var routineRepository: TTSLocalSaveRoutineRepository?
  private weak var completionRepository: TTSOnboardingRepositorySpy?

  private(set) var savedRoutineIDs: [UUID] = []
  private(set) var deletedRoutineIDs: [UUID] = []
  private(set) var wasRoutinePersistedAtSaveCallback = false
  private(set) var wasRoutineDeletedAtDeleteCallback = false
  private(set) var wasCompletionPersistedAtSaveCallback = false

  init(routineRepository: TTSLocalSaveRoutineRepository) {
    self.routineRepository = routineRepository
  }

  init(completionRepository: TTSOnboardingRepositorySpy) {
    self.completionRepository = completionRepository
  }

  func routineDidSave(_ routine: Routine) {
    savedRoutineIDs.append(routine.id)
    if let routineRepository {
      wasRoutinePersistedAtSaveCallback =
        (try? routineRepository.routine(id: routine.id)) != nil
    }
    if let completionRepository {
      wasCompletionPersistedAtSaveCallback =
        completionRepository.routine?.id == routine.id
    }
  }

  func routineDidDelete(localRoutineID: UUID) {
    deletedRoutineIDs.append(localRoutineID)
    if let routineRepository {
      wasRoutineDeletedAtDeleteCallback =
        (try? routineRepository.routine(id: localRoutineID)) == nil
    }
  }
}
