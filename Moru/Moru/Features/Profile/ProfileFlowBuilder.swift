//
//  ProfileFlowBuilder.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import SwiftUI

@MainActor
protocol ProfileFlowBuilding: AnyObject {
  func make() -> AnyView
}

@MainActor
final class DefaultProfileFlowBuilder: ProfileFlowBuilding {
  private let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let alarmService: any ProfileAlarmServicing
  private let accountServerViewModel: AccountServerSettingsViewModel
  private let accountRoutineGroupRemoteService:
    (any AccountRoutineGroupRemoteServing)?
  private let serverVoicePreviewPlayer: ServerVoicePreviewPlayer
  private let accountSessionStore: AccountSessionStore
  private let socialLoginCoordinator: any SocialLoginCoordinating
  private let googleAuthorizationSession: any GoogleAuthorizationStarting
  private let kakaoAuthorizationSession: any KakaoAuthorizationStarting
  private let accountLifecycleService: any AccountLifecycleManaging
  private let geminiDataConsentStore: GeminiDataConsentStore
  private let appCapabilities: AppCapabilities
  private let resetUseCase: (any ResetLocalDataUseCaseProtocol)?
  private let resetAvailability: @MainActor () -> Bool
  private let onOpenSettings: @MainActor () -> Void
  private let onResetSucceeded: @MainActor () -> Void

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying,
    alarmService: any ProfileAlarmServicing,
    accountServerViewModel: AccountServerSettingsViewModel,
    accountRoutineGroupRemoteService:
      (any AccountRoutineGroupRemoteServing)? = nil,
    serverVoicePreviewPlayer: ServerVoicePreviewPlayer = ServerVoicePreviewPlayer(),
    accountSessionStore: AccountSessionStore,
    socialLoginCoordinator: any SocialLoginCoordinating,
    googleAuthorizationSession: any GoogleAuthorizationStarting,
    kakaoAuthorizationSession: any KakaoAuthorizationStarting,
    accountLifecycleService: any AccountLifecycleManaging,
    geminiDataConsentStore: GeminiDataConsentStore,
    appCapabilities: AppCapabilities,
    resetUseCase: (any ResetLocalDataUseCaseProtocol)?,
    resetAvailability: @escaping @MainActor () -> Bool,
    onOpenSettings: @escaping @MainActor () -> Void,
    onResetSucceeded: @escaping @MainActor () -> Void
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.alarmService = alarmService
    self.accountServerViewModel = accountServerViewModel
    self.accountRoutineGroupRemoteService =
      accountRoutineGroupRemoteService
    self.serverVoicePreviewPlayer = serverVoicePreviewPlayer
    self.accountSessionStore = accountSessionStore
    self.socialLoginCoordinator = socialLoginCoordinator
    self.googleAuthorizationSession = googleAuthorizationSession
    self.kakaoAuthorizationSession = kakaoAuthorizationSession
    self.accountLifecycleService = accountLifecycleService
    self.geminiDataConsentStore = geminiDataConsentStore
    self.appCapabilities = appCapabilities
    self.resetUseCase = resetUseCase
    self.resetAvailability = resetAvailability
    self.onOpenSettings = onOpenSettings
    self.onResetSucceeded = onResetSucceeded
  }

  func make() -> AnyView {
    AnyView(
      ProfileView(
        viewModel: ProfileViewModel(
          profileSettingsUseCase: profileSettingsUseCase,
          voicePreviewPlayer: voicePreviewPlayer,
          alarmService: alarmService,
          socialLoginCoordinator: socialLoginCoordinator,
          accountLifecycleService: accountLifecycleService,
          resetUseCase: resetUseCase,
          resetAvailability: resetAvailability,
          onOpenSettings: onOpenSettings,
          onResetSucceeded: onResetSucceeded
        ),
        accountServerViewModel: accountServerViewModel,
        serverVoicePreviewPlayer: serverVoicePreviewPlayer,
        accountRoutineGroupRemoteService:
          accountRoutineGroupRemoteService,
        accountSessionStore: accountSessionStore,
        googleAuthorizationSession: googleAuthorizationSession,
        kakaoAuthorizationSession: kakaoAuthorizationSession,
        geminiDataConsentStore: geminiDataConsentStore,
        appCapabilities: appCapabilities
      )
    )
  }
}
