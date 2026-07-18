//
//  DependencyContainer.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftData

struct DependencyContainer {

  let routineRepository: any RoutineRepository
  let routineRunRepository: any RoutineRunRepository
  let localProfileRepository: any LocalProfileRepository
  let localSettingsRepository: any LocalSettingsRepository
  let onboardingRepository: any OnboardingRepository
  let routineSuggestionService: any RoutineSuggestionService
  let homeWeatherRepository: (any HomeWeatherRepository)?
  let historyEvidenceRepository: any HistoryEvidenceRepository
  let voiceAvailabilityProbe: any VoiceAvailabilityProbing

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    localSettingsRepository: any LocalSettingsRepository,
    onboardingRepository: any OnboardingRepository,
    routineSuggestionService: any RoutineSuggestionService,
    homeWeatherRepository: (any HomeWeatherRepository)?,
    historyEvidenceRepository: any HistoryEvidenceRepository,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.localSettingsRepository = localSettingsRepository
    self.onboardingRepository = onboardingRepository
    self.routineSuggestionService = routineSuggestionService
    self.homeWeatherRepository = homeWeatherRepository
    self.historyEvidenceRepository = historyEvidenceRepository
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
  }

  static func local(modelContext: ModelContext) -> DependencyContainer {
    let voiceAvailabilityProbe = AVSpeechVoiceAvailabilityProbe()
    let localProfileRepository = SwiftDataLocalProfileRepository(
      modelContext: modelContext,
      availabilityProbe: voiceAvailabilityProbe
    )

    return DependencyContainer(
      routineRepository: SwiftDataRoutineRepository(modelContext: modelContext),
      routineRunRepository: SwiftDataRoutineRunRepository(modelContext: modelContext),
      localProfileRepository: localProfileRepository,
      localSettingsRepository: localProfileRepository,
      onboardingRepository: SwiftDataOnboardingRepository(modelContext: modelContext),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      homeWeatherRepository: SwiftDataHomeWeatherRepository(modelContext: modelContext),
      historyEvidenceRepository: SwiftDataHistoryEvidenceRepository(modelContext: modelContext),
      voiceAvailabilityProbe: voiceAvailabilityProbe
    )
  }

  @MainActor
  func makeSessionStore() -> SessionStore {
    SessionStore()
  }

  @MainActor
  func makeOnboardingBuilder() -> any OnboardingFlowBuilding {
    let completeOnboardingUseCase = CompleteOnboardingUseCase(
      onboardingRepository: onboardingRepository,
      routineSuggestionService: routineSuggestionService
    )

    return DefaultOnboardingFlowBuilder(
      routineSuggestionService: routineSuggestionService,
      completeOnboardingUseCase: completeOnboardingUseCase
    )
  }

  @MainActor
  func makeRoutinePlayerBuilder() -> any RoutinePlayerBuilding {
    let resolver = ResolveRoutineExecutionUseCase(
      routineRepository: routineRepository
    )
    let saveRoutineRunUseCase = SaveRoutineRunUseCase(
      routineRunRepository: routineRunRepository
    )

    return DefaultRoutinePlayerBuilder(
      resolver: resolver,
      saveRoutineRunUseCase: saveRoutineRunUseCase
    )
  }

  #if DEBUG
  static func mock() -> DependencyContainer {
    let routineRepository = MockRoutineRepository()
    let localProfileRepository = MockLocalProfileRepository()

    return DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: MockRoutineRunRepository(),
      localProfileRepository: localProfileRepository,
      localSettingsRepository: localProfileRepository,
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: localProfileRepository,
        routineRepository: routineRepository
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      homeWeatherRepository: nil,
      historyEvidenceRepository: MockHistoryEvidenceRepository(),
      voiceAvailabilityProbe: UnavailableVoiceAvailabilityProbe()
    )
  }
  #endif
}
