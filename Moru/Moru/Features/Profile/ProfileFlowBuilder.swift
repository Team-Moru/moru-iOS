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
  private let accountSessionStore: AccountSessionStore
  private let appleAccountLinkingService: any AppleAccountLinking
  private let resetUseCase: (any ResetLocalDataUseCaseProtocol)?
  private let resetAvailability: @MainActor () -> Bool
  private let onOpenSettings: @MainActor () -> Void
  private let onResetSucceeded: @MainActor () -> Void

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying,
    alarmService: any ProfileAlarmServicing,
    accountSessionStore: AccountSessionStore,
    appleAccountLinkingService: any AppleAccountLinking,
    resetUseCase: (any ResetLocalDataUseCaseProtocol)?,
    resetAvailability: @escaping @MainActor () -> Bool,
    onOpenSettings: @escaping @MainActor () -> Void,
    onResetSucceeded: @escaping @MainActor () -> Void
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.alarmService = alarmService
    self.accountSessionStore = accountSessionStore
    self.appleAccountLinkingService = appleAccountLinkingService
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
          appleAccountLinkingService: appleAccountLinkingService,
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
