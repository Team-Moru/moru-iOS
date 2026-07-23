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
  let onboardingRepository: any OnboardingRepository
  let routineSuggestionService: any RoutineSuggestionService
  let homeWeatherRepository: (any HomeWeatherRepository)?
  let homeWeatherService: (any HomeWeatherService)?
  let localDataResetRepository: (any LocalDataResetRepository)?
  let alarmPlatformStateRepository: (any AlarmPlatformStateRepository)?
  let alarmScheduleMutator: (any AlarmScheduleMutating)?
  let alarmRuntimeHandler: (any AlarmRuntimeHandling)?
  let alarmNotificationDelegate: AlarmNotificationDelegate?
  let voiceAvailabilityProbe: any VoiceAvailabilityProbing
  let profileAlarmService: (any ProfileAlarmServicing)?

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    onboardingRepository: any OnboardingRepository,
    routineSuggestionService: any RoutineSuggestionService,
    homeWeatherRepository: (any HomeWeatherRepository)? = nil,
    homeWeatherService: (any HomeWeatherService)? = nil,
    localDataResetRepository: (any LocalDataResetRepository)? = nil,
    alarmPlatformStateRepository: (any AlarmPlatformStateRepository)? = nil,
    alarmScheduleMutator: (any AlarmScheduleMutating)? = nil,
    alarmRuntimeHandler: (any AlarmRuntimeHandling)? = nil,
    alarmNotificationDelegate: AlarmNotificationDelegate? = nil,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing =
      UnavailableVoiceAvailabilityProbe(),
    profileAlarmService: (any ProfileAlarmServicing)? = nil
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.onboardingRepository = onboardingRepository
    self.routineSuggestionService = routineSuggestionService
    self.homeWeatherRepository = homeWeatherRepository
    self.homeWeatherService = homeWeatherService
    self.localDataResetRepository = localDataResetRepository
    self.alarmPlatformStateRepository = alarmPlatformStateRepository
    self.alarmScheduleMutator = alarmScheduleMutator
    self.alarmRuntimeHandler = alarmRuntimeHandler
    self.alarmNotificationDelegate = alarmNotificationDelegate
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
    self.profileAlarmService = profileAlarmService
  }

  @MainActor
  static func local(modelContext: ModelContext) -> DependencyContainer {
    let voiceAvailabilityProbe = AVSpeechVoiceAvailabilityProbe()
    let routineRepository = SwiftDataRoutineRepository(modelContext: modelContext)
    let swiftDataRoutineRunRepository = SwiftDataRoutineRunRepository(
      modelContext: modelContext
    )
    let alarmStateRepository = SwiftDataAlarmPlatformStateRepository(
      modelContext: modelContext
    )
    let alarmKitScheduler = AlarmKitSchedulingAdapter()
    let notificationDelegate = AlarmNotificationDelegate()
    let notificationScheduler = UserNotificationAlarmSchedulingAdapter()
    let alarmMutationGate = AlarmMutationGate()
    let alarmScheduleMutator = DefaultAlarmScheduleMutationCoordinator(
      routineRepository: routineRepository,
      stateRepository: alarmStateRepository,
      primaryScheduler: alarmKitScheduler,
      fallbackScheduler: notificationScheduler,
      gate: alarmMutationGate
    )
    let profileAlarmService = AlarmProfileService(
      primaryScheduler: alarmKitScheduler,
      fallbackScheduler: notificationScheduler,
      stateRepository: alarmStateRepository,
      mutationCoordinator: alarmScheduleMutator
    )
    let alarmRuntimeHandler = DefaultAlarmRuntimeCoordinator(
      routineRepository: routineRepository,
      stateRepository: alarmStateRepository,
      primaryScheduler: alarmKitScheduler,
      fallbackScheduler: notificationScheduler,
      gate: alarmMutationGate
    )

    return DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: swiftDataRoutineRunRepository,
      localProfileRepository: SwiftDataLocalProfileRepository(modelContext: modelContext),
      onboardingRepository: SwiftDataOnboardingRepository(modelContext: modelContext),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      homeWeatherRepository: SwiftDataHomeWeatherRepository(modelContext: modelContext),
      homeWeatherService: CoreLocationWeatherService(),
      localDataResetRepository: SwiftDataLocalDataResetRepository(
        modelContext: modelContext
      ),
      alarmPlatformStateRepository: alarmStateRepository,
      alarmScheduleMutator: alarmScheduleMutator,
      alarmRuntimeHandler: alarmRuntimeHandler,
      alarmNotificationDelegate: notificationDelegate,
      voiceAvailabilityProbe: voiceAvailabilityProbe,
      profileAlarmService: profileAlarmService
    )
  }

  @MainActor
  func makeSessionStore() -> SessionStore {
    SessionStore(
      localProfileRepository: localProfileRepository,
      routineRepository: routineRepository
    )
  }

  @MainActor
  func makeOnboardingBuilder() -> any OnboardingFlowBuilding {
    let completeOnboardingUseCase = CompleteOnboardingUseCase(
      onboardingRepository: onboardingRepository,
      routineSuggestionService: routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
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
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: localProfileRepository,
        routineRepository: routineRepository
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared
    )
  }
  #endif
}
