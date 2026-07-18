//
//  ProfileFlowBuilder.swift
//  Moru
//
//  Created by Codex on 7/18/26.
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
  private let alarmStatusProvider: @MainActor () -> ProfileAlarmStatus
  private let resetPerformer: any ProfileLocalResetPerforming
  private let onOpenSettings: @MainActor () -> Void
  private let onRetryAlarmRepair: @MainActor () -> Void

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying = AVSpeechVoicePreviewPlayer(),
    alarmStatusProvider: @escaping @MainActor () -> ProfileAlarmStatus,
    resetPerformer: any ProfileLocalResetPerforming,
    onOpenSettings: @escaping @MainActor () -> Void,
    onRetryAlarmRepair: @escaping @MainActor () -> Void
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.alarmStatusProvider = alarmStatusProvider
    self.resetPerformer = resetPerformer
    self.onOpenSettings = onOpenSettings
    self.onRetryAlarmRepair = onRetryAlarmRepair
  }

  func make() -> AnyView {
    AnyView(
      ProfileView(
        viewModel: ProfileViewModel(
          profileSettingsUseCase: profileSettingsUseCase,
          voicePreviewPlayer: voicePreviewPlayer,
          alarmStatusProvider: alarmStatusProvider,
          resetPerformer: resetPerformer,
          onOpenSettings: onOpenSettings,
          onRetryAlarmRepair: onRetryAlarmRepair
        )
      )
    )
  }
}
