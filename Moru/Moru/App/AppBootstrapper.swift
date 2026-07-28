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
final class AppBootstrapper: ObservableObject {
  @Published private(set) var state: AppBootstrapState = .idle

  private let modelContainerFactory: () throws -> ModelContainer
  private let accountSessionStoreFactory: () -> AccountSessionStore
  private let appCapabilities: AppCapabilities

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
    appCapabilities: AppCapabilities = .production
  ) {
    self.modelContainerFactory = modelContainerFactory
    self.accountSessionStoreFactory = accountSessionStoreFactory
    self.appCapabilities = appCapabilities
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
      let modelContainer = try modelContainerFactory()
      let dependencies = DependencyContainer.local(modelContext: modelContainer.mainContext)
      let sessionStore = dependencies.makeSessionStore()
      sessionStore.load()
      let accountSessionStore = accountSessionStoreFactory()
      if appCapabilities.shouldAllowServerRequests {
        accountSessionStore.setLoginSucceededHandler { memberID in
          guard let syncCoordinator = dependencies.syncCoordinator else {
            return
          }

          Task { @MainActor in
            await syncCoordinator.synchronize(
              memberID: memberID,
              trigger: .loginSucceeded
            )
          }
        }
      }
      let tokenRefreshRemoteDataSource = DefaultAuthRemoteDataSource(
        apiClient: DefaultAPIClient(
          serverRequestsEnabled: appCapabilities.shouldAllowServerRequests
        )
      )
      let tokenRefreshCoordinator = TokenRefreshCoordinator(
        authRemoteDataSource: tokenRefreshRemoteDataSource,
        accountSessionStore: accountSessionStore
      )
      let authRemoteDataSource = DefaultAuthRemoteDataSource(
        apiClient: DefaultAPIClient(
          tokenProvider: accountSessionStore.accessTokenProvider,
          accessTokenRefresher: tokenRefreshCoordinator,
          serverRequestsEnabled: appCapabilities.shouldAllowServerRequests
        )
      )
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
      let accountLifecycleService = DefaultAccountLifecycleService(
        authRemoteDataSource: authRemoteDataSource,
        accountSessionStore: accountSessionStore,
        accountScopedDataCleaner: dependencies.accountScopedDataCleaner,
        providerSessionSignOut: providerSessionSignOut
      )
      let navigationCoordinator = AppNavigationCoordinator()
      let authCallbackRouter = AuthCallbackRouter(
        configuration: publicLoginConfiguration
      )
      authCallbackRouter.register(googleAuthorizationSession, for: .google)
      authCallbackRouter.register(kakaoAuthorizationSession, for: .kakao)
      let onboardingBuilder = dependencies.makeOnboardingBuilder()
      let routinePlayerBuilder = dependencies.makeRoutinePlayerBuilder()

      if appCapabilities.shouldRestoreAccountSession {
        accountSessionStore.prepareForRestoration()
      }

      state = .ready(
        BootstrappedApp(
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
          routinePlayerBuilder: routinePlayerBuilder
        )
      )

      restoreAccountSessionIfAvailable(accountSessionStore)
    } catch {
      state = .failed(
        AppBootstrapFailure(
          message: "저장소를 초기화할 수 없어요. 다시 시도해 주세요."
        )
      )
    }
  }

  private func restoreAccountSessionIfAvailable(
    _ accountSessionStore: AccountSessionStore
  ) {
    guard appCapabilities.shouldRestoreAccountSession else {
      return
    }

    Task { @MainActor in
      await Task.yield()
      accountSessionStore.restore()
    }
  }
}
