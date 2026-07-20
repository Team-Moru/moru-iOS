//
//  DependencyContainer.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftData

struct DependencyContainer {
  static let featureVisibleDependencyKeys: Set<String> = [
    "routineRepository",
    "routineRunRepository",
    "localProfileRepository",
    "localDataResetRepository",
    "onboardingRepository",
    "routineSuggestionService",
  ]

  let routineRepository: any RoutineRepository
  let routineRunRepository: any RoutineRunRepository
  let localProfileRepository: any LocalProfileRepository
  let localDataResetRepository: any LocalDataResetRepository
  let onboardingRepository: any OnboardingRepository
  let routineSuggestionService: any RoutineSuggestionService

  static func local(modelContext: ModelContext) -> DependencyContainer {
    DependencyContainer(
      routineRepository: SwiftDataRoutineRepository(modelContext: modelContext),
      routineRunRepository: SwiftDataRoutineRunRepository(modelContext: modelContext),
      localProfileRepository: SwiftDataLocalProfileRepository(modelContext: modelContext),
      localDataResetRepository: SwiftDataLocalDataResetRepository(modelContext: modelContext),
      onboardingRepository: SwiftDataOnboardingRepository(modelContext: modelContext),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }

  #if DEBUG
  static func mock() -> DependencyContainer {
    let routineRepository = MockRoutineRepository()
    let routineRunRepository = MockRoutineRunRepository()
    let localProfileRepository = MockLocalProfileRepository()
    let localDataResetRepository = MockLocalDataResetRepository(
      routineRepository: routineRepository,
      routineRunRepository: routineRunRepository,
      localProfileRepository: localProfileRepository
    )

    return DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: routineRunRepository,
      localProfileRepository: localProfileRepository,
      localDataResetRepository: localDataResetRepository,
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: localProfileRepository,
        routineRepository: routineRepository
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }
  #endif
}
