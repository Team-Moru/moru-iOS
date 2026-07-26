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
  private let accountVoiceSelectionUseCase: any AccountVoiceSelectionUseCaseProtocol
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let alarmService: any ProfileAlarmServicing
  private let accountSessionStore: AccountSessionStore
  private let appleAccountLinkingService: any AppleAccountLinking
  private let accountLifecycleService: any AccountLifecycleManaging
  private let resetUseCase: (any ResetLocalDataUseCaseProtocol)?
  private let resetAvailability: @MainActor () -> Bool
  private let onOpenSettings: @MainActor () -> Void
  private let onResetSucceeded: @MainActor () -> Void

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    accountVoiceSelectionUseCase: any AccountVoiceSelectionUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying,
    alarmService: any ProfileAlarmServicing,
    accountSessionStore: AccountSessionStore,
    appleAccountLinkingService: any AppleAccountLinking,
    accountLifecycleService: any AccountLifecycleManaging,
    resetUseCase: (any ResetLocalDataUseCaseProtocol)?,
    resetAvailability: @escaping @MainActor () -> Bool,
    onOpenSettings: @escaping @MainActor () -> Void,
    onResetSucceeded: @escaping @MainActor () -> Void
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.accountVoiceSelectionUseCase = accountVoiceSelectionUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.alarmService = alarmService
    self.accountSessionStore = accountSessionStore
    self.appleAccountLinkingService = appleAccountLinkingService
    self.accountLifecycleService = accountLifecycleService
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
          accountVoiceSelectionUseCase: accountVoiceSelectionUseCase,
          voicePreviewPlayer: voicePreviewPlayer,
          alarmService: alarmService,
          appleAccountLinkingService: appleAccountLinkingService,
          accountLifecycleService: accountLifecycleService,
          resetUseCase: resetUseCase,
          resetAvailability: resetAvailability,
          onOpenSettings: onOpenSettings,
          onResetSucceeded: onResetSucceeded
        ),
        accountSessionStore: accountSessionStore
      )
    )
  }
}
