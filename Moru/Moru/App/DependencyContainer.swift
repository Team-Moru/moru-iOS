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
    "routineSuggestionService",
  ]

  let routineRepository: any RoutineRepository
  let routineRunRepository: any RoutineRunRepository
  let localProfileRepository: any LocalProfileRepository
  let routineSuggestionService: any RoutineSuggestionService

  static func local(modelContext: ModelContext) -> DependencyContainer {
    DependencyContainer(
      routineRepository: SwiftDataRoutineRepository(modelContext: modelContext),
      routineRunRepository: SwiftDataRoutineRunRepository(modelContext: modelContext),
      localProfileRepository: SwiftDataLocalProfileRepository(modelContext: modelContext),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }

  #if DEBUG
  static func mock() -> DependencyContainer {
    DependencyContainer(
      routineRepository: MockRoutineRepository(),
      routineRunRepository: MockRoutineRunRepository(),
      localProfileRepository: MockLocalProfileRepository(),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }
  #endif
}
