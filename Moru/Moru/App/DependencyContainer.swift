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
  let routineSuggestionCoordinator: any RoutineSuggestionCoordinating
  let onboardingRecommendationCoordinator: any RoutineSuggestionCoordinating
  let homeWeatherRepository: (any HomeWeatherRepository)?
  let homeWeatherService: (any HomeWeatherService)?
  let localDataResetRepository: (any LocalDataResetRepository)?
  let accountHistoryRemoteService: (any AccountHistoryRemoteServing)?
  let accountServerRemoteService: (any AccountServerRemoteServing)?
  let accountRoutineGroupRemoteService:
    (any AccountRoutineGroupRemoteServing)?
  let accountRoutineExecutionRemoteService:
    (any AccountRoutineExecutionRemoteServing)?
  let accountRoutineTTSRemoteService: (any AccountRoutineTTSRemoteServing)?
  let signedInMemberProvider: (any SignedInMemberProviding)?
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
    onboardingRecommendationCoordinator:
      (any RoutineSuggestionCoordinating)? = nil,
    homeWeatherRepository: (any HomeWeatherRepository)? = nil,
    homeWeatherService: (any HomeWeatherService)? = nil,
    localDataResetRepository: (any LocalDataResetRepository)? = nil,
    accountHistoryRemoteService: (any AccountHistoryRemoteServing)? = nil,
    accountServerRemoteService: (any AccountServerRemoteServing)? = nil,
    accountRoutineGroupRemoteService:
      (any AccountRoutineGroupRemoteServing)? = nil,
    accountRoutineExecutionRemoteService:
      (any AccountRoutineExecutionRemoteServing)? = nil,
    accountRoutineTTSRemoteService:
      (any AccountRoutineTTSRemoteServing)? = nil,
    signedInMemberProvider: (any SignedInMemberProviding)? = nil,
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
    let resolvedRoutineSuggestionCoordinator = routineSuggestionCoordinator
      ?? RoutineSuggestionCoordinator(
        serverService: nil,
        localService: routineSuggestionService,
        signedInMemberProvider: nil
      )
    self.routineSuggestionCoordinator = resolvedRoutineSuggestionCoordinator
    self.onboardingRecommendationCoordinator =
      onboardingRecommendationCoordinator
      ?? resolvedRoutineSuggestionCoordinator
    self.homeWeatherRepository = homeWeatherRepository
    self.homeWeatherService = homeWeatherService
    self.localDataResetRepository = localDataResetRepository
    self.accountHistoryRemoteService = accountHistoryRemoteService
    self.accountServerRemoteService = accountServerRemoteService
    self.accountRoutineGroupRemoteService =
      accountRoutineGroupRemoteService
    self.accountRoutineExecutionRemoteService =
      accountRoutineExecutionRemoteService
    self.accountRoutineTTSRemoteService = accountRoutineTTSRemoteService
    self.signedInMemberProvider = signedInMemberProvider
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
    routineSuggestionRemoteDataSource:
      (any RoutineSuggestionRemoteDataSource)? = nil,
    onboardingRecommendationRemoteDataSource:
      (any OnboardingRecommendationRemoteDataSource)? = nil,
    signedInMemberProvider: (any SignedInMemberProviding)? = nil,
    accountHistoryRemoteService:
      (any AccountHistoryRemoteServing)? = nil,
    accountServerRemoteService:
      (any AccountServerRemoteServing)? = nil,
    accountRoutineGroupRemoteService:
      (any AccountRoutineGroupRemoteServing)? = nil,
    accountRoutineExecutionRemoteService:
      (any AccountRoutineExecutionRemoteServing)? = nil,
    accountRoutineTTSRemoteService:
      (any AccountRoutineTTSRemoteServing)? = nil
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
      signedInMemberProvider: signedInMemberProvider
    )
    let serverOnboardingRecommendationService =
      onboardingRecommendationRemoteDataSource.map {
        ServerOnboardingRecommendationService(remoteDataSource: $0)
      }
    let onboardingRecommendationCoordinator =
      OnboardingRecommendationCoordinator(
        serverService: serverOnboardingRecommendationService,
        localService: localSuggestionService,
        signedInMemberProvider: signedInMemberProvider
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
      onboardingRecommendationCoordinator:
        onboardingRecommendationCoordinator,
      homeWeatherRepository: SwiftDataHomeWeatherRepository(modelContext: modelContext),
      homeWeatherService: CoreLocationWeatherService(),
      localDataResetRepository: SwiftDataLocalDataResetRepository(
        modelContext: modelContext
      ),
      accountHistoryRemoteService: accountHistoryRemoteService,
      accountServerRemoteService: accountServerRemoteService,
      accountRoutineGroupRemoteService:
        accountRoutineGroupRemoteService,
      accountRoutineExecutionRemoteService:
        accountRoutineExecutionRemoteService,
      accountRoutineTTSRemoteService: accountRoutineTTSRemoteService,
      signedInMemberProvider: signedInMemberProvider,
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
      onboardingRecommendationCoordinator:
        onboardingRecommendationCoordinator,
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
    let remoteReporter: (any RoutineRemoteReporting)?
    if let routineGroupService = accountRoutineGroupRemoteService,
       let executionService = accountRoutineExecutionRemoteService,
       let signedInMemberProvider {
      remoteReporter = DefaultRoutineRemoteReporter(
        routineRepository: routineRepository,
        routineGroupService: routineGroupService,
        executionService: executionService,
        signedInMemberProvider: signedInMemberProvider
      )
    } else {
      remoteReporter = nil
    }

    return DefaultRoutinePlayerBuilder(
      resolver: resolver,
      saveRoutineRunUseCase: saveRoutineRunUseCase,
      routineRunRepository: routineRunRepository,
      localProfileRepository: localProfileRepository,
      guidancePlayer: guidancePlayer,
      guidancePlaybackState: playbackState,
      audioSessionCoordinator: audioSessionCoordinator,
      remoteReporter: remoteReporter
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
