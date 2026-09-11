//
//  MainTabComposition.swift
//  Moru
//

import SwiftUI

/// 탭 루트를 만드는 빌더와 프로필 유스케이스 묶음.
///
/// 예전에는 `AppRouter.init`이 이걸 전부 직접 만들었다. `AppRouter`는 struct View라
/// 상태가 바뀔 때마다 다시 만들어지고, 그때마다 유스케이스와 빌더가 새로 생겼다.
/// 부팅 때 한 번만 만들어 들고 다닌다.
@MainActor
struct MainTabComposition {
  let homeBuilder: any HomeFlowBuilding
  let historyBuilder: any HistoryFlowBuilding
  let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  let profileAlarmService: any ProfileAlarmServicing
  let profileResetUseCase: (any ResetLocalDataUseCaseProtocol)?
  let profileVoicePreviewPlayer: any VoicePreviewPlaying

  init(
    dependencies: DependencyContainer,
    accountSessionStore: AccountSessionStore,
    homeBuilder: (any HomeFlowBuilding)? = nil,
    historyBuilder: (any HistoryFlowBuilding)? = nil
  ) {
    self.historyBuilder = historyBuilder ?? Self.makeHistoryBuilder(
      dependencies: dependencies,
      accountSessionStore: accountSessionStore
    )
    self.homeBuilder = homeBuilder ?? Self.makeHomeBuilder(
      dependencies: dependencies,
      accountSessionStore: accountSessionStore
    )
    self.profileSettingsUseCase = ProfileSettingsUseCase(
      localProfileRepository: dependencies.localProfileRepository,
      voiceAvailabilityProbe: dependencies.voiceAvailabilityProbe
    )
    let profileAlarmService = dependencies.profileAlarmService
      ?? UnavailableProfileAlarmService()
    self.profileAlarmService = profileAlarmService
    self.profileResetUseCase = dependencies.localDataResetRepository.map {
      ResetLocalDataUseCase(
        localDataResetRepository: $0,
        alarmService: profileAlarmService,
        routineTTSAudioCacheCleaner:
          dependencies.routineTTSAudioCache.map {
            RoutineTTSAudioCacheCleaner(cache: $0)
          }
      )
    }
    self.profileVoicePreviewPlayer = dependencies.makeVoicePreviewPlayer()
  }

  private static func makeHistoryBuilder(
    dependencies: DependencyContainer,
    accountSessionStore: AccountSessionStore
  ) -> any HistoryFlowBuilding {
    DefaultHistoryFlowBuilder(
      loadHistoryUseCase: LoadHistoryUseCase(
        routineRepository: dependencies.routineRepository,
        routineRunRepository: dependencies.routineRunRepository
      ),
      summaryEnricher: dependencies.accountHistoryRemoteService.map {
        AccountHistorySummaryEnricher(
          remoteService: $0,
          signedInMemberProvider: accountSessionStore
        )
      },
      accountDailyReportLoader: dependencies.accountHistoryRemoteService.map {
        LoadAccountHistoryDailyReportUseCase(
          remoteService: $0,
          signedInMemberProvider: accountSessionStore
        )
      },
      signedInMemberProvider: accountSessionStore
    )
  }

  private static func makeHomeBuilder(
    dependencies: DependencyContainer,
    accountSessionStore: AccountSessionStore
  ) -> any HomeFlowBuilding {
    let enrichHomeRoutinesUseCase: (any EnrichHomeRoutinesUseCaseProtocol)?
    if let remoteService = dependencies.accountRoutineGroupRemoteService,
       let syncRepository = dependencies.routineSyncRepository {
      enrichHomeRoutinesUseCase = EnrichHomeRoutinesUseCase(
        remoteService: remoteService,
        sessionIdentityProvider: accountSessionStore,
        syncStateReader: DefaultHomeRoutineSyncStateReader(
          repository: syncRepository
        )
      )
    } else {
      enrichHomeRoutinesUseCase = nil
    }

    return DefaultHomeFlowBuilder(
      loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
        routineRepository: dependencies.routineRepository,
        routineRunRepository: dependencies.routineRunRepository,
        localProfileRepository: dependencies.localProfileRepository,
        alarmPlatformStateRepository: dependencies.alarmPlatformStateRepository
      ),
      enrichHomeRoutinesUseCase: enrichHomeRoutinesUseCase,
      weatherRepository: dependencies.homeWeatherRepository,
      weatherService: dependencies.homeWeatherService,
      sessionIdentityProvider: accountSessionStore,
      routineCreationContentFactory: {
        AnyView(
          RoutineSettingView(
            dependencies: dependencies,
            entryPoint: .newRoutine
          )
        )
      }
    )
  }
}
