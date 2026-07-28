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
      let accountLifecycleService = DefaultAccountLifecycleService(
        authRemoteDataSource: authRemoteDataSource,
        accountSessionStore: accountSessionStore,
        accountScopedDataCleaner: NoAccountScopedDataCleaner()
      )
      let navigationCoordinator = AppNavigationCoordinator()
      let authCallbackRouter = AuthCallbackRouter(
        configuration: .mainBundle
      )
      let onboardingBuilder = dependencies.makeOnboardingBuilder()
      let routinePlayerBuilder = dependencies.makeRoutinePlayerBuilder()

      state = .ready(
        BootstrappedApp(
          modelContainer: modelContainer,
          dependencies: dependencies,
          sessionStore: sessionStore,
          accountSessionStore: accountSessionStore,
          appleCredentialMonitor: appleCredentialMonitor,
          socialLoginCoordinator: socialLoginCoordinator,
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
