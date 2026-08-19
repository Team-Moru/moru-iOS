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
  let geminiDataConsentStore: GeminiDataConsentStore
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
  static let installationMarkerKey = "app-installation-marker-v1"

  @Published private(set) var state: AppBootstrapState = .idle

  private let modelContainerFactory: () throws -> ModelContainer
  private let accountSessionStoreFactory: () -> AccountSessionStore
  private let appCapabilities: AppCapabilities
  private let preflight: any AppBootstrapPreflightPreparing
  private let installationMarkerUserDefaults: UserDefaults

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
    preflight: any AppBootstrapPreflightPreparing = DefaultAppBootstrapPreflight(),
    installationMarkerUserDefaults: UserDefaults = .standard
  ) {
    self.modelContainerFactory = modelContainerFactory
    self.accountSessionStoreFactory = accountSessionStoreFactory
    self.appCapabilities = appCapabilities
    self.preflight = preflight
    self.installationMarkerUserDefaults = installationMarkerUserDefaults
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

  private var runtimeAppCapabilities: AppCapabilities {
    #if DEBUG
    // The review weather fixture must never restore a personal account or
    // make MORU-server requests on a developer's physical device.
    if ProcessInfo.processInfo.arguments.contains("-ui-testing-weather-fixture") {
      return .localOnly
    }
    #endif
    return appCapabilities
  }

  private func constructReadyGraph() {
    state = .loading

    do {
      let appCapabilities = runtimeAppCapabilities
      let accountSessionStore = accountSessionStoreFactory()
      let geminiDataConsentStore = GeminiDataConsentStore()
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
        geminiDataConsent: geminiDataConsentStore,
        routineSyncWakeupRelay: routineSyncWakeupRelay
      )
      let shouldSkipAccountRestoration = try prepareInstallationState(
        dependencies: dependencies,
        accountSessionStore: accountSessionStore,
        appCapabilities: appCapabilities
      )
      // Recovery changes no request identity. The sender can only replay a
      // complete stored wire artifact inside the server's retention window.
      try? dependencies.routineSyncRepository?.recoverInterruptedAttempts(at: Date())
      let routineRestorationBackfillBarrier =
        RoutineRestorationBackfillBarrier()
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
          sessionIdentityProvider: accountSessionStore,
          geminiDataConsent: geminiDataConsentStore,
          onOnboardingCompletionCommitted: { identity in
            // The remote set-to-true already committed. A local Keychain
            // failure cannot safely resurrect the Outbox row, so retain the
            // server result and let the next status refresh repair the hint.
            _ = try? accountSessionStore.markOnboardingCompleted(for: identity)
          }
        )
        let loginBackfiller = RoutineSyncLoginBackfiller(
          routineRepository: dependencies.routineRepository,
          localProfileRepository: dependencies.localProfileRepository,
          syncRepository: routineSyncRepository
        )
        routineSyncRuntimeCoordinator = RoutineSyncRuntimeCoordinator(
          sender: sender,
          sessionIdentityProvider: accountSessionStore,
          loginBackfiller: loginBackfiller,
          wakeupRelay: routineSyncWakeupRelay,
          restorationBackfillBarrier:
            routineRestorationBackfillBarrier,
          onMutationCompleted: {
            dependencies.routineTTSWarmupCoordinator?.routineSyncDidComplete()
          }
        )
      } else {
        routineSyncRuntimeCoordinator = nil
      }
      let sessionStore = dependencies.makeSessionStore()
      #if DEBUG
      if usesReviewUIFixture {
        // Review UI tests need to reach Home before exercising the operating
        // system's real location-permission screens or account entry. This is
        // Debug-only and never changes a Release user's onboarding state.
        _ = try? dependencies.localProfileRepository.loadOrCreateDefaultProfile()
      }
      #endif
      sessionStore.load()
      let serverRoutineRestorer: (any ServerRoutineRestoring)?
      if let accountRoutineGroupRemoteService,
         let routineSyncRepository = dependencies.routineSyncRepository {
        serverRoutineRestorer = DefaultServerRoutineRestorationService(
          remoteService: accountRoutineGroupRemoteService,
          persistence: SwiftDataServerRoutineRestorationRepository(
            modelContext: modelContainer.mainContext,
            syncRepository: routineSyncRepository
          ),
          sessionIdentityProvider: accountSessionStore
        )
      } else {
        serverRoutineRestorer = nil
      }
      let shouldHoldProvisionalRestorationUI: Bool
      if case .restoring = accountSessionStore.state,
         case .provisional = try? serverRoutineRestorer?.localDataState() {
        shouldHoldProvisionalRestorationUI = true
        sessionStore.beginServerRoutineRestoration()
      } else {
        shouldHoldProvisionalRestorationUI = false
      }
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
          },
          routineRestorer: serverRoutineRestorer,
          restorationBackfillBarrier:
            routineRestorationBackfillBarrier,
          onRestorationBegan: {
            sessionStore.beginServerRoutineRestoration()
          },
          onRestorationFinished: {
            sessionStore.finishServerRoutineRestoration()
          },
          onRestorationFailed: {
            sessionStore.failServerRoutineRestoration()
          },
          restorationUIHeldForAccountRestore:
            shouldHoldProvisionalRestorationUI
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
        geminiDataConsentStore: geminiDataConsentStore,
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
        accountScopedDataCleaner: accountScopedDataCleaner,
        appCapabilities: appCapabilities,
        shouldSkipAccountRestoration: shouldSkipAccountRestoration
      )
    } catch {
      state = .failed(
        AppBootstrapFailure(
          message: "저장소를 초기화할 수 없어요. 다시 시도해 주세요."
        )
      )
    }
  }

  private var usesReviewUIFixture: Bool {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    return arguments.contains("-ui-testing-weather-fixture")
      || arguments.contains("-ui-testing-account-connection-fixture")
    #else
    false
    #endif
  }

  private func finishBootstrap(
    _ app: BootstrappedApp,
    accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning,
    appCapabilities: AppCapabilities,
    shouldSkipAccountRestoration: Bool
  ) {
    Task { @MainActor in
      let shouldRestoreAccount = if shouldSkipAccountRestoration {
        false
      } else {
        await shouldRestoreAccountSession(
          accountSessionStore,
          accountScopedDataCleaner: accountScopedDataCleaner,
          appCapabilities: appCapabilities
        )
      }
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

  private func prepareInstallationState(
    dependencies: DependencyContainer,
    accountSessionStore: AccountSessionStore,
    appCapabilities: AppCapabilities
  ) throws -> Bool {
    guard appCapabilities.shouldRestoreAccountSession,
          installationMarkerUserDefaults.object(
            forKey: Self.installationMarkerKey
          ) == nil else {
      return false
    }

    let profile = try dependencies.localProfileRepository.fetchProfile()
    let routines = try dependencies.routineRepository.fetchRoutines()
    let isLocalStoreEmpty = profile == nil && routines.isEmpty

    if isLocalStoreEmpty {
      // App deletion removes SwiftData and UserDefaults but can leave this
      // device-only Keychain item behind. Do not invoke provider sign-out:
      // only discard MORU credentials and the in-memory bearer. The session
      // store remains signed out even when Keychain deletion fails.
      try? accountSessionStore.removeLocalAccountSession()
    }

    installationMarkerUserDefaults.set(
      true,
      forKey: Self.installationMarkerKey
    )
    return isLocalStoreEmpty
  }

  private func shouldRestoreAccountSession(
    _ accountSessionStore: AccountSessionStore,
    accountScopedDataCleaner: any AccountScopedDataCleaning,
    appCapabilities: AppCapabilities
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
      let preparedPendingRetry = try accountSessionStore
        .preparePendingWithdrawalRetry(
          matching: recovery.ambiguousMemberIDs
        )
      guard !preparedPendingRetry else {
        // Keep ordinary account identity unavailable while preserving a
        // visible, user-retryable withdrawal-only state.
        return false
      }
    } catch {
      accountSessionStore.deferRestorationWithoutDeletingCredentials()
      return false
    }

    return true
  }
}
