//
//  ProfileViewModel.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import Observation
import UIKit

nonisolated enum ProfileAlarmStatus: Equatable {
  case configured
  case permissionOff
  case repairRequired
  case unavailable
}

nonisolated enum LocalResetAvailability: Equatable {
  case available
  case blockedByActiveRoutine
  case blockedByAlarmRepair
  case blockedByAlarmReset
}

protocol ProfileLocalResetPerforming: AnyObject {
  func availability() -> LocalResetAvailability
  func reset() async throws
}

@MainActor
enum ProfileViewState {
  case loading
  case content(ProfileSettingsLoadResult)
  case failed(message: String)
}

@MainActor
@Observable
final class ProfileViewModel {
  private let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let resetPerformer: any ProfileLocalResetPerforming
  private let alarmStatusProvider: @MainActor () -> ProfileAlarmStatus
  private let onOpenSettings: @MainActor () -> Void
  private let onRetryAlarmRepair: @MainActor () -> Void

  private(set) var alarmStatus: ProfileAlarmStatus
  private(set) var state: ProfileViewState = .loading
  private(set) var displayNameErrorMessage: String?
  private(set) var voiceErrorMessage: String?
  private(set) var resetStatusMessage: String?
  private(set) var didResetSucceed = false
  private(set) var isResetInProgress = false

  var isResetAvailable: Bool {
    resetPerformer.availability() == .available
  }

  var resetAvailabilityMessage: String? {
    resetMessage(for: resetPerformer.availability())
  }

  var resetAccessibilityHint: String {
    guard !isResetInProgress else {
      return "로컬 데이터를 초기화하고 있어 초기화 버튼을 사용할 수 없어요."
    }
    let availability = resetPerformer.availability()

    guard let message = resetMessage(for: availability) else {
      return "로컬 데이터 초기화 확인 화면을 엽니다."
    }

    return "\(message) 초기화 버튼을 사용할 수 없어요."
  }

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    voicePreviewPlayer: any VoicePreviewPlaying,
    alarmStatusProvider: @escaping @MainActor () -> ProfileAlarmStatus,
    resetPerformer: any ProfileLocalResetPerforming,
    onOpenSettings: @escaping @MainActor () -> Void,
    onRetryAlarmRepair: @escaping @MainActor () -> Void
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.voicePreviewPlayer = voicePreviewPlayer
    self.alarmStatusProvider = alarmStatusProvider
    self.alarmStatus = alarmStatusProvider()
    self.resetPerformer = resetPerformer
    self.onOpenSettings = onOpenSettings
    self.onRetryAlarmRepair = onRetryAlarmRepair
  }

  func loadProfileSettings() {
    state = .loading

    do {
      state = .content(try profileSettingsUseCase.loadProfileSettings())
    } catch {
      state = .failed(message: "프로필 설정을 불러오지 못했어요.")
    }
  }

  func refreshAlarmStatus() {
    alarmStatus = alarmStatusProvider()
  }

  func retryButtonDidTap() {
    loadProfileSettings()
  }

  func displayNameSaveButtonDidTap(_ displayName: String) -> Bool {
    displayNameErrorMessage = nil

    do {
      state = .content(try profileSettingsUseCase.saveDisplayName(displayName))
      return true
    } catch let error as ProfileSettingsUseCaseError {
      reportDisplayNameError(displayNameErrorMessage(for: error))
      return false
    } catch {
      reportDisplayNameError("이름을 저장하지 못했어요. 다시 시도해 주세요.")
      return false
    }
  }

  func voiceSelectionButtonDidTap(_ voice: VoiceProfile) -> Bool {
    voiceErrorMessage = nil

    guard profileSettingsUseCase.isVoiceAvailable(voice) else {
      reportVoiceError("이 목소리는 기기에서 사용할 수 없어요.")
      return false
    }

    do {
      state = .content(try profileSettingsUseCase.selectVoice(voiceID: voice.id))
      return true
    } catch {
      reportVoiceError("목소리를 변경하지 못했어요. 다시 시도해 주세요.")
      return false
    }
  }

  func voicePreviewButtonDidTap(_ voice: VoiceProfile) {
    voiceErrorMessage = nil

    guard profileSettingsUseCase.isVoiceAvailable(voice),
          voicePreviewPlayer.previewVoice(voice) else {
      reportVoiceError("이 목소리를 미리 들을 수 없어요.")
      return
    }
  }

  func voiceSelectionViewDidDisappear() {
    voicePreviewPlayer.stopVoicePreview()
  }

  func voiceNoticeAcknowledgeButtonDidTap() {
    voiceErrorMessage = nil

    guard case .content(let content) = state,
          content.settings.pendingVoiceMigrationNotice != nil else {
      return
    }

    do {
      state = .content(try profileSettingsUseCase.acknowledgeVoiceNotice())
    } catch {
      reportVoiceError("목소리 변경 안내를 확인하지 못했어요. 다시 시도해 주세요.")
    }
  }

  func voiceResolutionRetryButtonDidTap() {
    voiceErrorMessage = nil

    do {
      state = .content(try profileSettingsUseCase.retryVoiceResolution())
    } catch {
      reportVoiceError("목소리 설정을 확인하지 못했어요. 다시 시도해 주세요.")
    }
  }

  func alarmSettingsButtonDidTap() {
    onOpenSettings()
  }

  func alarmRepairRetryButtonDidTap() {
    onRetryAlarmRepair()
  }

  func resetButtonDidTap() -> Bool {
    resetStatusMessage = nil
    didResetSucceed = false

    guard let message = resetMessage(for: resetPerformer.availability()) else {
      return true
    }

    reportResetStatus(message)
    return false
  }

  func resetConfirmationButtonDidTap() async {
    guard !isResetInProgress else {
      return
    }
    didResetSucceed = false

    guard let message = resetMessage(for: resetPerformer.availability()) else {
      isResetInProgress = true
      resetStatusMessage = nil

      do {
        try await resetPerformer.reset()
        reportResetStatus("로컬 데이터를 초기화했어요.", didSucceed: true)
      } catch {
        reportResetStatus("초기화하지 못했어요. 다시 시도해 주세요.")
      }

      isResetInProgress = false
      return
    }

    reportResetStatus(message)
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    profileSettingsUseCase.isVoiceAvailable(voice)
  }

  func isSelectedVoice(_ voice: VoiceProfile, in content: ProfileSettingsLoadResult) -> Bool {
    content.profile.selectedVoice.id == voice.id
  }

  func pendingVoiceNotice(in content: ProfileSettingsLoadResult) -> String? {
    content.settings.pendingVoiceMigrationNotice
  }

  func voiceRecoveryMessage(in content: ProfileSettingsLoadResult) -> String? {
    switch content.settings.voiceMigrationState {
    case .unresolved:
      return "목소리 설정을 확인하고 있어요. 다시 시도해 주세요."
    case .noFallbackNoticePending, .noFallbackNoticeAcknowledged:
      return "사용 가능한 목소리를 찾지 못했어요. 목소리를 설치한 뒤 다시 시도해 주세요."
    case .corruptRecoveryPending:
      return "목소리 설정을 복구해야 해요. 다시 시도해 주세요."
    case .resolved, .fallbackNoticePending, .fallbackNoticeAcknowledged:
      break
    }

    switch VoiceSelection(rawID: content.profile.selectedVoice.id) {
    case .available:
      return nil
    case .unavailable(let rawID):
      if rawID == VoiceProfile.moru.id {
        return "이전 버전의 기본 목소리 설정이에요. 다시 시도해 주세요."
      }

      return "알 수 없는 목소리 설정이에요. 다시 시도해 주세요."
    }
  }

  func shouldOfferVoiceResolutionRetry(in content: ProfileSettingsLoadResult) -> Bool {
    switch content.settings.voiceMigrationState {
    case .unresolved,
         .noFallbackNoticePending,
         .noFallbackNoticeAcknowledged,
         .corruptRecoveryPending:
      return true
    case .resolved, .fallbackNoticePending, .fallbackNoticeAcknowledged:
      break
    }

    if case .unavailable = VoiceSelection(rawID: content.profile.selectedVoice.id) {
      return true
    }

    return false
  }

  private func reportDisplayNameError(_ message: String) {
    displayNameErrorMessage = message
    announce(message)
  }

  private func reportVoiceError(_ message: String) {
    voiceErrorMessage = message
    announce(message)
  }

  private func reportResetStatus(_ message: String, didSucceed: Bool = false) {
    self.didResetSucceed = didSucceed
    resetStatusMessage = message
    announce(message)
  }

  private func announce(_ message: String) {
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  private func resetMessage(for availability: LocalResetAvailability) -> String? {
    switch availability {
    case .available:
      nil
    case .blockedByActiveRoutine:
      "루틴이 끝난 후 초기화해 주세요"
    case .blockedByAlarmRepair:
      "알람 상태를 먼저 복구해 주세요"
    case .blockedByAlarmReset:
      "알람 초기화 기능이 준비되지 않아 지금은 로컬 데이터를 초기화할 수 없어요"
    }
  }
  private func displayNameErrorMessage(for error: ProfileSettingsUseCaseError) -> String {
    switch error {
    case .invalidDisplayName(.empty):
      return "이름은 1자 이상 입력해 주세요."
    case .invalidDisplayName(.tooLong):
      return "이름은 20자 이하로 입력해 주세요."
    case .invalidDisplayName(.containsEmoji):
      return "이름에는 이모지를 사용할 수 없어요."
    case .invalidDisplayName(.containsControlCharacter):
      return "이름에는 제어 문자를 사용할 수 없어요."
    case .profileUnavailable:
      return "프로필 정보를 확인할 수 없어요."
    case .settingsUnavailable:
      return "설정 정보를 확인할 수 없어요."
    case .unavailableVoice:
      return "이름을 저장하지 못했어요. 다시 시도해 주세요."
    }
  }
}
