//
//  DependencyContainer.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import SwiftData

struct ServerPreferenceDependencies {
  let mutationRepository: any ServerMutationRepository
  let voiceCatalogRepository: any ServerVoiceCatalogRepository
  let voiceRemoteService: (any AccountVoiceRemoteServing)?
  let synchronizer: any ServerSynchronizing
  let accountScopedDataCleaner: any AccountScopedDataCleaning
}

struct DependencyContainer {
  let routineRepository: any RoutineRepository
  let routineRunRepository: any RoutineRunRepository
  let localProfileRepository: any LocalProfileRepository
  let onboardingRepository: any OnboardingRepository
  let routineSuggestionService: any RoutineSuggestionService
  let routineSuggestionCoordinator: any RoutineSuggestionCoordinating
  let homeWeatherRepository: (any HomeWeatherRepository)?
  let homeWeatherService: (any HomeWeatherService)?
  let localDataResetRepository: (any LocalDataResetRepository)?
  let serverPreferences: ServerPreferenceDependencies?
  let alarmPlatformStateRepository: (any AlarmPlatformStateRepository)?
  let alarmScheduleMutator: (any AlarmScheduleMutating)?
  let alarmRuntimeHandler: (any AlarmRuntimeHandling)?
  let voiceAvailabilityProbe: any VoiceAvailabilityProbing
  let profileAlarmService: (any ProfileAlarmServicing)?
  let routineGuidancePlayer: (any RoutineGuidancePlaying)?
  let routineGuidancePlaybackState: RoutineGuidancePlaybackState?
  let routineAudioSessionCoordinator: RoutineAudioSessionCoordinator?

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    onboardingRepository: any OnboardingRepository,
    routineSuggestionService: any RoutineSuggestionService,
    routineSuggestionCoordinator: (any RoutineSuggestionCoordinating)? = nil,
    homeWeatherRepository: (any HomeWeatherRepository)? = nil,
    homeWeatherService: (any HomeWeatherService)? = nil,
    localDataResetRepository: (any LocalDataResetRepository)? = nil,
    serverPreferences: ServerPreferenceDependencies? = nil,
    alarmPlatformStateRepository: (any AlarmPlatformStateRepository)? = nil,
    alarmScheduleMutator: (any AlarmScheduleMutating)? = nil,
    alarmRuntimeHandler: (any AlarmRuntimeHandling)? = nil,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing =
      UnavailableVoiceAvailabilityProbe(),
    profileAlarmService: (any ProfileAlarmServicing)? = nil,
    routineGuidancePlayer: (any RoutineGuidancePlaying)? = nil,
    routineGuidancePlaybackState: RoutineGuidancePlaybackState? = nil,
    routineAudioSessionCoordinator: RoutineAudioSessionCoordinator? = nil
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.onboardingRepository = onboardingRepository
    self.routineSuggestionService = routineSuggestionService
    self.routineSuggestionCoordinator = routineSuggestionCoordinator
      ?? RoutineSuggestionCoordinator(
        serverService: nil,
        localService: routineSuggestionService,
        accountProvider: nil
      )
    self.homeWeatherRepository = homeWeatherRepository
    self.homeWeatherService = homeWeatherService
    self.localDataResetRepository = localDataResetRepository
    self.serverPreferences = serverPreferences
    self.alarmPlatformStateRepository = alarmPlatformStateRepository
    self.alarmScheduleMutator = alarmScheduleMutator
    self.alarmRuntimeHandler = alarmRuntimeHandler
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
    self.profileAlarmService = profileAlarmService
    self.routineGuidancePlayer = routineGuidancePlayer
    self.routineGuidancePlaybackState = routineGuidancePlaybackState
    self.routineAudioSessionCoordinator = routineAudioSessionCoordinator
  }

  @MainActor
  static func local(
    modelContext: ModelContext,
    voiceRemoteService: (any AccountVoiceRemoteServing)? = nil,
    routineSuggestionRemoteDataSource:
      (any RoutineSuggestionRemoteDataSource)? = nil,
    accountSessionStore: AccountSessionStore? = nil
  ) -> DependencyContainer {
    let audioResourceLoader = RoutineAudioResourceLoader()
    let guidancePlaybackState = RoutineGuidancePlaybackState()
    let guidancePlayer = BundledRoutineGuidancePlayer(
      resourceLoader: audioResourceLoader,
      playbackState: guidancePlaybackState
    )
    let audioSessionCoordinator = RoutineAudioSessionCoordinator(
      guidancePlayback: guidancePlayer
    )
    let voiceAvailabilityProbe = BundledVoiceAvailabilityProbe(
      resourceLoader: audioResourceLoader
    )
    let routineRepository = SwiftDataRoutineRepository(modelContext: modelContext)
    let serverPreferenceRepository = SwiftDataServerPreferenceRepository(
      modelContext: modelContext
    )
    let mutationExecutor: any ServerMutationExecuting
    if let voiceRemoteService {
      mutationExecutor = VoiceSelectionMutationExecutor(
        remoteService: voiceRemoteService,
        catalogueRepository: serverPreferenceRepository
      )
    } else {
      mutationExecutor = DeferredServerMutationExecutor()
    }
    let syncCoordinator = SyncCoordinator(
      mutationRepository: serverPreferenceRepository,
      executor: mutationExecutor
    )
    let swiftDataRoutineRunRepository = SwiftDataRoutineRunRepository(
      modelContext: modelContext
    )
    let alarmStateRepository = SwiftDataAlarmPlatformStateRepository(
      modelContext: modelContext
    )
    let alarmKitScheduler = AlarmKitSchedulingAdapter()
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
    let localSuggestionService = LocalTemplateSuggestionService.shared
    let serverSuggestionService = routineSuggestionRemoteDataSource.map {
      ServerRoutineSuggestionService(remoteDataSource: $0)
    }
    let routineSuggestionCoordinator = RoutineSuggestionCoordinator(
      serverService: serverSuggestionService,
      localService: localSuggestionService,
      accountProvider: accountSessionStore
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
      routineSuggestionService: localSuggestionService,
      routineSuggestionCoordinator: routineSuggestionCoordinator,
      homeWeatherRepository: SwiftDataHomeWeatherRepository(modelContext: modelContext),
      homeWeatherService: CoreLocationWeatherService(),
      localDataResetRepository: SwiftDataLocalDataResetRepository(
        modelContext: modelContext
      ),
      serverPreferences: ServerPreferenceDependencies(
        mutationRepository: serverPreferenceRepository,
        voiceCatalogRepository: serverPreferenceRepository,
        voiceRemoteService: voiceRemoteService,
        synchronizer: syncCoordinator,
        accountScopedDataCleaner: SwiftDataAccountScopedDataCleaner(
          repository: serverPreferenceRepository
        )
      ),
      alarmPlatformStateRepository: alarmStateRepository,
      alarmScheduleMutator: alarmScheduleMutator,
      alarmRuntimeHandler: alarmRuntimeHandler,
      voiceAvailabilityProbe: voiceAvailabilityProbe,
      profileAlarmService: profileAlarmService,
      routineGuidancePlayer: guidancePlayer,
      routineGuidancePlaybackState: guidancePlaybackState,
      routineAudioSessionCoordinator: audioSessionCoordinator
    )
  }

  var serverMutationRepository: (any ServerMutationRepository)? {
    serverPreferences?.mutationRepository
  }

  var serverVoiceCatalogRepository: (any ServerVoiceCatalogRepository)? {
    serverPreferences?.voiceCatalogRepository
  }

  var voiceRemoteService: (any AccountVoiceRemoteServing)? {
    serverPreferences?.voiceRemoteService
  }

  var serverSynchronizer: (any ServerSynchronizing)? {
    serverPreferences?.synchronizer
  }

  var accountScopedDataCleaner: any AccountScopedDataCleaning {
    serverPreferences?.accountScopedDataCleaner
      ?? NoAccountScopedDataCleaner()
  }

  @MainActor
  func makeSessionStore() -> SessionStore {
    SessionStore(
      localProfileRepository: localProfileRepository
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
      routineSuggestionCoordinator: routineSuggestionCoordinator,
      completeOnboardingUseCase: completeOnboardingUseCase,
      voicePreviewPlayer: makeVoicePreviewPlayer()
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
    let guidancePlayer = routineGuidancePlayer ?? NoopRoutineGuidancePlayer()
    let playbackState = routineGuidancePlaybackState ?? RoutineGuidancePlaybackState()
    let audioSessionCoordinator = routineAudioSessionCoordinator
      ?? RoutineAudioSessionCoordinator(guidancePlayback: guidancePlayer)

    return DefaultRoutinePlayerBuilder(
      resolver: resolver,
      saveRoutineRunUseCase: saveRoutineRunUseCase,
      routineRunRepository: routineRunRepository,
      localProfileRepository: localProfileRepository,
      guidancePlayer: guidancePlayer,
      guidancePlaybackState: playbackState,
      audioSessionCoordinator: audioSessionCoordinator
    )
  }

  @MainActor
  func makeVoicePreviewPlayer() -> any VoicePreviewPlaying {
    guard let routineGuidancePlayer else {
      return UnavailableVoicePreviewPlayer()
    }

    return BundledVoicePreviewPlayer(
      availabilityProbe: voiceAvailabilityProbe,
      guidancePlayer: routineGuidancePlayer
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
