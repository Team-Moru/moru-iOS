//
//  AppBootstrapper.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation
import SwiftData

struct BootstrappedApp {
  let modelContainer: ModelContainer
  let dependencies: DependencyContainer
  let sessionStore: SessionStore
  let accountSessionStore: AccountSessionStore
  let appleCredentialMonitor: AppleCredentialMonitor
  let socialLoginCoordinator: any SocialLoginCoordinating
  let googleAuthorizationSession: GoogleSignInSession
  let kakaoAuthorizationSession: KakaoSignInSession
  let accountLifecycleService: any AccountLifecycleManaging
  let appCapabilities: AppCapabilities
  let authCallbackRouter: AuthCallbackRouter
  let navigationCoordinator: AppNavigationCoordinator
  let onboardingBuilder: any OnboardingFlowBuilding
  let routinePlayerBuilder: any RoutinePlayerBuilding
  let onboardingStatusRuntimeCoordinator:
    OnboardingStatusRuntimeCoordinator?
  let routineSyncRuntimeCoordinator: RoutineSyncRuntimeCoordinator?
}

struct AppBootstrapFailure: Equatable {
  let message: String
}

enum AppBootstrapState {
  case idle
  case loading
  case ready(BootstrappedApp)
  case failed(AppBootstrapFailure)
}

@MainActor
protocol AppBootstrapPreflightPreparing {
  func prepare(dependencies: DependencyContainer) async
}

@MainActor
struct DefaultAppBootstrapPreflight: AppBootstrapPreflightPreparing {
  func prepare(dependencies: DependencyContainer) async {
    // Repair happens before account restoration. The repository therefore sees
    // no signed-in member and can only perform a local SwiftData batch save.
    _ = try? RoutineActivationBootstrapRepair.repairIfNeeded(
      in: dependencies.routineRepository
    )

    guard let alarmPlatformStateRepository =
            dependencies.alarmPlatformStateRepository,
          let alarmScheduleMutator = dependencies.alarmScheduleMutator else {
      return
    }
    await Self.cancelDisabledAlarmRecordsIfNeeded(
      routineRepository: dependencies.routineRepository,
      alarmPlatformStateRepository: alarmPlatformStateRepository,
      alarmScheduleMutator: alarmScheduleMutator
    )
  }

  static func cancelDisabledAlarmRecordsIfNeeded(
    routineRepository: any RoutineRepository,
    alarmPlatformStateRepository: any AlarmPlatformStateRepository,
    alarmScheduleMutator: any AlarmScheduleMutating
  ) async {
    guard let routines = try? routineRepository.fetchRoutines(),
          let records = try? alarmPlatformStateRepository.fetchRecords() else {
      return
    }

    let retainedScheduleIDs = Set(records.map(\.scheduleID))
    let routinesNeedingCancellation = routines.filter { routine in
      guard let schedule = routine.alarmSchedule,
            retainedScheduleIDs.contains(schedule.id) else {
        return false
      }
      return !routine.isActive || !schedule.isEnabled
    }
    guard !routinesNeedingCancellation.isEmpty else {
      return
    }

    // Unlike full reconcile, this never requests authorization or schedules a
    // winner while launch UI is loading. Cancellation failure is persisted by
    // the normal mutation coordinator as repairRequired and retried next boot.
    _ = try? await alarmScheduleMutator.apply(
      .synchronize(routines: routinesNeedingCancellation)
    )
  }
}

@MainActor
final class AppBootstrapper: ObservableObject {
  @Published private(set) var state: AppBootstrapState = .idle

  private let modelContainerFactory: () throws -> ModelContainer
  private let accountSessionStoreFactory: () -> AccountSessionStore
  private let appCapabilities: AppCapabilities
  private let preflight: any AppBootstrapPreflightPreparing

  init(
    modelContainerFactory: @escaping () throws -> ModelContainer = {
      try ModelContainer.moruContainer()
    },
    accountSessionStoreFactory: @escaping () -> AccountSessionStore = {
      AccountSessionStore(
        credentialStore: KeychainCredentialStore(),
        accessTokenProvider: MemoryAccessTokenProvider(),
        restorationGuard: UserDefaultsAccountSessionRestorationGuard()
      )
    },
    appCapabilities: AppCapabilities = .production,
    preflight: any AppBootstrapPreflightPreparing = DefaultAppBootstrapPreflight()
  ) {
    self.modelContainerFactory = modelContainerFactory
    self.accountSessionStoreFactory = accountSessionStoreFactory
    self.appCapabilities = appCapabilities
    self.preflight = preflight
  }

  func start() {
    guard case .idle = state else {
      return
    }

    constructReadyGraph()
  }

  func retry() {
    guard case .failed = state else {
      return
    }

    constructReadyGraph()
  }

  private func constructReadyGraph() {
    state = .loading

    do {
      let accountSessionStore = accountSessionStoreFactory()
      if appCapabilities.shouldRestoreAccountSession {
        // Publish this synchronously with start(). Credential loading still
        // waits for pending-cleanup recovery below.
        accountSessionStore.prepareForRestoration()
      }
      let modelContainer = try modelContainerFactory()
      let tokenRefreshRemoteDataSource = DefaultAuthRemoteDataSource(
        apiClient: DefaultAPIClient(
          serverRequestsEnabled: appCapabilities.shouldAllowServerRequests
        )
      )
      let tokenRefreshCoordinator = TokenRefreshCoordinator(
        authRemoteDataSource: tokenRefreshRemoteDataSource,
        accountSessionStore: accountSessionStore
      )
      let authenticatedAPIClient = DefaultAPIClient(
        tokenProvider: accountSessionStore.accessTokenProvider,
        accessTokenRefresher: tokenRefreshCoordinator,
        serverRequestsEnabled: appCapabilities.shouldAllowServerRequests
      )
      let authRemoteDataSource = DefaultAuthRemoteDataSource(
        apiClient: authenticatedAPIClient
      )
      let routineSuggestionRemoteDataSource:
        (any RoutineSuggestionRemoteDataSource)?
      let onboardingRecommendationRemoteDataSource:
        (any OnboardingRecommendationRemoteDataSource)?
      if appCapabilities.shouldAllowServerRequests {
        routineSuggestionRemoteDataSource =
          DefaultRoutineSuggestionRemoteDataSource(
            apiClient: authenticatedAPIClient
          )
        onboardingRecommendationRemoteDataSource =
          DefaultOnboardingRecommendationRemoteDataSource(
            apiClient: authenticatedAPIClient
          )
      } else {
        routineSuggestionRemoteDataSource = nil
        onboardingRecommendationRemoteDataSource = nil
      }
      let accountHistoryRemoteService:
        (any AccountHistoryRemoteServing)?
      let accountServerRemoteService:
        (any AccountServerRemoteServing)?
      let accountRoutineGroupRemoteService:
        (any AccountRoutineGroupRemoteServing)?
      let routineTTSRemoteService: (any RoutineTTSRemoteServing)?
      if appCapabilities.shouldAllowServerRequests {
        accountHistoryRemoteService = DefaultAccountHistoryRemoteService(
          apiClient: authenticatedAPIClient
        )
        accountServerRemoteService = DefaultAccountServerRemoteService(
          apiClient: authenticatedAPIClient
        )
        accountRoutineGroupRemoteService =
          DefaultAccountRoutineGroupRemoteService(
            apiClient: authenticatedAPIClient
          )
        routineTTSRemoteService = DefaultRoutineTTSRemoteService(
          apiClient: authenticatedAPIClient
        )
      } else {
        accountHistoryRemoteService = nil
        accountServerRemoteService = nil
        accountRoutineGroupRemoteService = nil
        routineTTSRemoteService = nil
      }
      let routineSyncWakeupRelay = RoutineSyncWakeupRelay()
      let dependencies = DependencyContainer.local(
        modelContext: modelContainer.mainContext,
        routineSuggestionRemoteDataSource:
          routineSuggestionRemoteDataSource,
        onboardingRecommendationRemoteDataSource:
          onboardingRecommendationRemoteDataSource,
        signedInMemberProvider: accountSessionStore,
        accountHistoryRemoteService: accountHistoryRemoteService,
        accountServerRemoteService: accountServerRemoteService,
        accountRoutineGroupRemoteService:
          accountRoutineGroupRemoteService,
        routineTTSRemoteService: routineTTSRemoteService,
        sessionIdentityProvider: accountSessionStore,
        routineSyncWakeupRelay: routineSyncWakeupRelay
      )
      // Recovery changes no request identity. The sender can only replay a
      // complete stored wire artifact inside the server's retention window.
      try? dependencies.routineSyncRepository?.recoverInterruptedAttempts(at: Date())
      let routineSyncRuntimeCoordinator: RoutineSyncRuntimeCoordinator?
      if appCapabilities.shouldAllowServerRequests,
         let routineSyncRepository = dependencies.routineSyncRepository {
        let requestPreparer = ProductionRoutineSyncRequestPreparer(
          repository: routineSyncRepository
        )
        let responseDecoder = ProductionRoutineSyncResponseDecoder()
        let transport = ProductionRoutineSyncTransport(
          apiClient: authenticatedAPIClient,
          responseDecoder: responseDecoder
        )
        let sender = RoutineSyncSender(
          repository: routineSyncRepository,
          requestPreparer: requestPreparer,
          transport: transport,
          contract: .productionP0,
          sessionIdentityProvider: accountSessionStore
        )
        routineSyncRuntimeCoordinator = RoutineSyncRuntimeCoordinator(
          sender: sender,
          sessionIdentityProvider: accountSessionStore,
          wakeupRelay: routineSyncWakeupRelay,
          onMutationCompleted: {
            dependencies.routineTTSWarmupCoordinator?.routineSyncDidComplete()
          }
        )
      } else {
        routineSyncRuntimeCoordinator = nil
      }
      let sessionStore = dependencies.makeSessionStore()
      sessionStore.load()
      let onboardingStatusRuntimeCoordinator =
        appCapabilities.shouldAllowServerRequests
        ? OnboardingStatusRuntimeCoordinator(
          remoteService: DefaultOnboardingStatusRemoteService(
            apiClient: authenticatedAPIClient
          ),
          accountSessionStore: accountSessionStore,
          localCompletionProvider: {
            switch sessionStore.phase {
            case .ready:
              true
            case .onboardingRequired:
              false
            case .loading, .failed:
              nil
            }
          }
        )
        : nil
      let socialLoginCoordinator = SocialLoginCoordinator(
        authRemoteDataSource: authRemoteDataSource,
        accountSessionStore: accountSessionStore
      )
      let appleCredentialMonitor = AppleCredentialMonitor(
        accountSessionStore: accountSessionStore
      )
      appleCredentialMonitor.start()
      let publicLoginConfiguration = SocialLoginPublicConfiguration.mainBundle
      let googleAuthorizationSession = GoogleSignInSession(
        configuration: publicLoginConfiguration
      )
      let kakaoAuthorizationSession = KakaoSignInSession(
        configuration: publicLoginConfiguration
      )
      let providerSessionSignOut = SocialProviderSessionSignOutRouter(
        handlers: [
          .google: googleAuthorizationSession,
          .kakao: kakaoAuthorizationSession,
        ]
      )
      let accountScopedDataCleaner: any AccountScopedDataCleaning
      if let routineSyncRepository = dependencies.routineSyncRepository {
        let syncCleaner = SwiftDataRoutineSyncAccountCleaner(
          repository: routineSyncRepository
        )
        if let routineTTSAudioCache = dependencies.routineTTSAudioCache {
          accountScopedDataCleaner = RoutineTTSAudioAccountScopedDataCleaner(
            base: syncCleaner,
            audioCleaner: RoutineTTSAudioCacheCleaner(
              cache: routineTTSAudioCache
            )
          )
        } else {
          accountScopedDataCleaner = syncCleaner
        }
      } else {
        accountScopedDataCleaner = NoAccountScopedDataCleaner()
      }
      let accountLifecycleService = DefaultAccountLifecycleService(
        authRemoteDataSource: authRemoteDataSource,
        accountSessionStore: accountSessionStore,
        accountScopedDataCleaner: accountScopedDataCleaner,
        providerSessionSignOut: providerSessionSignOut,
        routineTTSAudioCacheCleaner:
          dependencies.routineTTSAudioCache.map {
            RoutineTTSAudioCacheCleaner(cache: $0)
          }
      )
      let navigationCoordinator = AppNavigationCoordinator()
      let authCallbackRouter = AuthCallbackRouter(
        configuration: publicLoginConfiguration
      )
      authCallbackRouter.register(googleAuthorizationSession, for: .google)
      authCallbackRouter.register(kakaoAuthorizationSession, for: .kakao)
      let onboardingBuilder = dependencies.makeOnboardingBuilder()
      let routinePlayerBuilder = dependencies.makeRoutinePlayerBuilder()
      let app = BootstrappedApp(
        modelContainer: modelContainer,
        dependencies: dependencies,
        sessionStore: sessionStore,
        accountSessionStore: accountSessionStore,
        appleCredentialMonitor: appleCredentialMonitor,
        socialLoginCoordinator: socialLoginCoordinator,
        googleAuthorizationSession: googleAuthorizationSession,
        kakaoAuthorizationSession: kakaoAuthorizationSession,
        accountLifecycleService: accountLifecycleService,
        appCapabilities: appCapabilities,
        authCallbackRouter: authCallbackRouter,
        navigationCoordinator: navigationCoordinator,
        onboardingBuilder: onboardingBuilder,
        routinePlayerBuilder: routinePlayerBuilder,
        onboardingStatusRuntimeCoordinator:
          onboardingStatusRuntimeCoordinator,
        routineSyncRuntimeCoordinator: routineSyncRuntimeCoordinator
      )

      finishBootstrap(
        app,
        accountSessionStore: accountSessionStore,
        accountScopedDataCleaner: accountScopedDataCleaner
      )
    } catch {
      state = .failed(
        AppBootstrapFailure(
          message: "저장소를 초기화할 수 없어요. 다시 시도해 주세요."
        )
      )
    }
  }

  private func finishBootstrap(
    _ app: BootstrappedApp,
    accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning
  ) {
    Task { @MainActor in
      let shouldRestoreAccount = await shouldRestoreAccountSession(
        accountSessionStore,
        accountScopedDataCleaner: accountScopedDataCleaner
      )
      await preflight.prepare(dependencies: app.dependencies)
      state = .ready(app)

      guard shouldRestoreAccount else {
        return
      }

      // Keep ready/restoring observable before Keychain I/O changes state.
      Task { @MainActor in
        await Task.yield()
        accountSessionStore.restore()
      }
    }
  }

  private func shouldRestoreAccountSession(
    _ accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning
  ) async -> Bool {
    guard appCapabilities.shouldRestoreAccountSession else {
      return false
    }

    let recovery: PendingAccountCleanupRecovery
    do {
      recovery = try await accountScopedDataCleaner.recoverPendingAccountCleanups()
      for memberID in recovery.completedMemberIDs {
        _ = try accountSessionStore.removeStoredSessionIfMatching(
          memberID: memberID
        )
        try await accountScopedDataCleaner.finalizePendingAccountCleanup(
          memberID: memberID
        )
      }
    } catch {
      // Confirmed cleanup that cannot finish must not revive a potentially
      // withdrawn account. Credentials remain untouched for later recovery.
      accountSessionStore.deferRestorationWithoutDeletingCredentials()
      return false
    }

    do {
      let hasAmbiguousStoredSession = try accountSessionStore.hasStoredSession(
        matching: recovery.ambiguousMemberIDs
      )
      guard !hasAmbiguousStoredSession else {
        // An attempting marker is not proof of withdrawal. Keep credentials,
        // but do not restore that exact account into an uncertain session.
        accountSessionStore.deferRestorationWithoutDeletingCredentials()
        return false
      }
    } catch {
      accountSessionStore.deferRestorationWithoutDeletingCredentials()
      return false
    }

    return true
  }
}
