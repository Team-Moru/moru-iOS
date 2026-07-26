//
//  ProfileViewModel.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Observation
import UIKit

@MainActor
enum ProfileViewState: Equatable {
  case loading
  case content(ProfileSettingsLoadResult)
  case failed(message: String)
}

@MainActor
@Observable
final class ProfileViewModel {
  private let profileSettingsUseCase: any ProfileSettingsUseCaseProtocol
  private let accountVoiceSelectionUseCase: any AccountVoiceSelectionUseCaseProtocol
  private let voicePreviewPlayer: any VoicePreviewPlaying
  private let alarmService: any ProfileAlarmServicing
  private let appleAccountLinkingService: any AppleAccountLinking
  private let accountLifecycleService: any AccountLifecycleManaging
  private let resetUseCase: (any ResetLocalDataUseCaseProtocol)?
  private let resetAvailability: @MainActor () -> Bool
  private let onOpenSettings: @MainActor () -> Void
  private let onResetSucceeded: @MainActor () -> Void

  private(set) var state: ProfileViewState = .loading
  private(set) var alarmStatus: ProfileAlarmStatus = .unavailable
  private(set) var displayNameErrorMessage: String?
  private(set) var voiceErrorMessage: String?
  private(set) var voiceCatalogue = AccountVoiceCatalogueSnapshot(
    options: [],
    mismatch: nil,
    notice: nil
  )
  private(set) var isVoiceCatalogueLoading = false
  private(set) var resetErrorMessage: String?
  private(set) var accountErrorMessage: String?
  private(set) var isAlarmRequestInProgress = false
  private(set) var isResetInProgress = false
  private(set) var isAccountLinkInProgress = false
  private(set) var accountLifecycleAction: AccountLifecycleAction?

  var isResetAvailable: Bool {
    resetUseCase != nil && resetAvailability() && !isResetInProgress
  }

  var isAccountLifecycleInProgress: Bool {
    accountLifecycleAction != nil
  }

  var resetAvailabilityMessage: String? {
    guard resetUseCase != nil else {
      return "이 기기에서는 초기화 기능을 사용할 수 없어요."
    }
    guard resetAvailability() else {
      return "진행 중인 루틴이 끝난 후 초기화해 주세요."
    }

    return nil
  }

  init(
    profileSettingsUseCase: any ProfileSettingsUseCaseProtocol,
    accountVoiceSelectionUseCase: (any AccountVoiceSelectionUseCaseProtocol)? = nil,
    voicePreviewPlayer: any VoicePreviewPlaying,
    alarmService: any ProfileAlarmServicing,
    appleAccountLinkingService: any AppleAccountLinking =
      UnavailableAppleAccountLinkingService(),
    accountLifecycleService: any AccountLifecycleManaging =
      UnavailableAccountLifecycleService(),
    resetUseCase: (any ResetLocalDataUseCaseProtocol)?,
    resetAvailability: @escaping @MainActor () -> Bool,
    onOpenSettings: @escaping @MainActor () -> Void,
    onResetSucceeded: @escaping @MainActor () -> Void
  ) {
    self.profileSettingsUseCase = profileSettingsUseCase
    self.accountVoiceSelectionUseCase = accountVoiceSelectionUseCase
      ?? UnavailableAccountVoiceSelectionUseCase(
        profileSettingsUseCase: profileSettingsUseCase,
        voiceAvailabilityProbe: UnavailableVoiceAvailabilityProbe()
      )
    self.voicePreviewPlayer = voicePreviewPlayer
    self.alarmService = alarmService
    self.appleAccountLinkingService = appleAccountLinkingService
    self.accountLifecycleService = accountLifecycleService
    self.resetUseCase = resetUseCase
    self.resetAvailability = resetAvailability
    self.onOpenSettings = onOpenSettings
    self.onResetSucceeded = onResetSucceeded
  }

  func loadProfileSettings() {
    state = .loading

    do {
      state = .content(try profileSettingsUseCase.loadProfileSettings())
    } catch {
      state = .failed(message: "프로필 설정을 불러오지 못했어요.")
    }

    Task {
      await refreshAlarmStatus()
    }
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

    do {
      state = .content(try profileSettingsUseCase.selectVoice(voice))
      voicePreviewPlayer.stopVoicePreview()
      return true
    } catch {
      reportVoiceError("이 목소리는 기기에서 사용할 수 없어요.")
      return false
    }
  }

  func voicePreviewButtonDidTap(_ voice: VoiceProfile) {
    voiceErrorMessage = nil

    guard voicePreviewPlayer.previewVoice(voice) else {
      reportVoiceError("이 목소리를 미리 들을 수 없어요.")
      return
    }
  }

  func voiceSelectionViewDidDisappear() {
    voicePreviewPlayer.stopVoicePreview()
  }

  func voiceSelectionViewDidAppear() async {
    isVoiceCatalogueLoading = true
    voiceCatalogue = await accountVoiceSelectionUseCase.loadCatalogue()
    isVoiceCatalogueLoading = false
  }

  func accountVoiceSelectionButtonDidTap(
    _ option: AccountVoiceOption
  ) async -> Bool {
    voiceErrorMessage = nil

    do {
      let result = try await accountVoiceSelectionUseCase.select(option)
      state = .content(result.profileResult)
      voicePreviewPlayer.stopVoicePreview()
      if result.serverDisposition == .queueFailed {
        reportVoiceError(
          "기기에는 저장했지만 서버 반영 대기를 등록하지 못했어요."
        )
      }
      voiceCatalogue = await accountVoiceSelectionUseCase.loadCatalogue()
      return true
    } catch {
      reportVoiceError("이 목소리는 지금 선택할 수 없어요.")
      return false
    }
  }

  func accountVoicePreviewButtonDidTap(_ option: AccountVoiceOption) {
    guard let voice = option.localVoice,
          option.availability.isSelectable else {
      reportVoiceError("이 목소리를 미리 들을 수 없어요.")
      return
    }
    voicePreviewButtonDidTap(voice)
  }

  func voiceMismatchChoiceDidTap(
    _ choice: AccountVoiceMismatchChoice
  ) async {
    guard let mismatch = voiceCatalogue.mismatch else {
      return
    }

    do {
      let result = try await accountVoiceSelectionUseCase.resolveMismatch(
        mismatch,
        choice: choice
      )
      state = .content(result.profileResult)
      voiceCatalogue = await accountVoiceSelectionUseCase.loadCatalogue()
      if result.serverDisposition == .queueFailed {
        reportVoiceError(
          "기기에는 저장했지만 서버 반영 대기를 등록하지 못했어요."
        )
      }
    } catch {
      reportVoiceError("음성 선택 차이를 처리하지 못했어요.")
    }
  }

  func voiceMismatchDialogDidDismiss() {
    voiceCatalogue = AccountVoiceCatalogueSnapshot(
      options: voiceCatalogue.options,
      mismatch: nil,
      notice: voiceCatalogue.notice
    )
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    profileSettingsUseCase.isVoiceAvailable(voice)
  }

  func refreshAlarmStatus() async {
    alarmStatus = await alarmService.currentStatus()
  }

  func alarmAuthorizationButtonDidTap() async {
    guard !isAlarmRequestInProgress else {
      return
    }

    isAlarmRequestInProgress = true
    alarmStatus = await alarmService.requestAuthorization()
    isAlarmRequestInProgress = false
  }

  func alarmRetryButtonDidTap() async {
    guard !isAlarmRequestInProgress else {
      return
    }

    isAlarmRequestInProgress = true
    alarmStatus = await alarmService.retryScheduling()
    isAlarmRequestInProgress = false
  }

  func alarmSettingsButtonDidTap() {
    onOpenSettings()
  }

  func appleAuthorizationDidComplete(
    _ outcome: AppleAuthorizationOutcome
  ) async {
    guard !isAccountLinkInProgress,
          !isAccountLifecycleInProgress else {
      return
    }

    accountErrorMessage = nil

    switch outcome {
    case .cancelled:
      return
    case .failed:
      reportAccountError(
        "Apple 인증 정보를 확인하지 못했어요. "
          + "로컬 데이터는 그대로 사용할 수 있어요."
      )
    case .authorized(let identityToken, let authorizationCode):
      isAccountLinkInProgress = true
      defer { isAccountLinkInProgress = false }

      do {
        try await appleAccountLinkingService.link(
          identityToken: identityToken,
          authorizationCode: authorizationCode
        )
        announce("Apple 계정이 연결되었어요.")
      } catch {
        reportAccountError(
          "Apple 계정을 연결하지 못했어요. "
            + "로컬 데이터는 그대로 사용할 수 있어요."
        )
      }
    }
  }

  func logoutButtonDidTap() async {
    guard !isAccountLinkInProgress,
          !isAccountLifecycleInProgress else {
      return
    }

    accountLifecycleAction = .logout
    accountErrorMessage = nil
    defer { accountLifecycleAction = nil }

    do {
      try await accountLifecycleService.logout()
      announce("로그아웃했어요. 로컬 루틴과 기록은 유지됩니다.")
    } catch {
      reportAccountError(
        "로그아웃 정보를 정리하지 못했어요. 다시 시도해 주세요."
      )
    }
  }

  func withdrawalConfirmationButtonDidTap() async {
    guard !isAccountLinkInProgress,
          !isAccountLifecycleInProgress else {
      return
    }

    accountLifecycleAction = .withdrawal
    accountErrorMessage = nil
    defer { accountLifecycleAction = nil }

    do {
      try await accountLifecycleService.withdraw()
      announce("회원 탈퇴가 완료됐어요. 로컬 루틴과 기록은 유지됩니다.")
    } catch AccountLifecycleError.localCleanupFailed {
      reportAccountError(
        "회원 탈퇴는 완료됐지만 "
          + "기기의 계정 정보를 모두 정리하지 못했어요."
      )
    } catch {
      reportAccountError(
        "회원 탈퇴를 완료하지 못했어요. "
          + "계정 연결은 유지되며 다시 시도할 수 있어요."
      )
    }
  }

  func resetConfirmationButtonDidTap() async {
    guard isResetAvailable, let resetUseCase else {
      reportResetError(resetAvailabilityMessage ?? "지금은 초기화할 수 없어요.")
      return
    }

    isResetInProgress = true
    resetErrorMessage = nil

    do {
      try await resetUseCase.execute()
      onResetSucceeded()
    } catch {
      reportResetError("초기화하지 못했어요. 기존 데이터는 유지됩니다.")
    }

    isResetInProgress = false
  }

  private func reportDisplayNameError(_ message: String) {
    displayNameErrorMessage = message
    announce(message)
  }

  private func reportVoiceError(_ message: String) {
    voiceErrorMessage = message
    announce(message)
  }

  private func reportResetError(_ message: String) {
    resetErrorMessage = message
    announce(message)
  }

  private func reportAccountError(_ message: String) {
    accountErrorMessage = message
    announce(message)
  }

  private func announce(_ message: String) {
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  private func displayNameErrorMessage(for error: ProfileSettingsUseCaseError) -> String {
    switch error {
    case .invalidDisplayName(.empty):
      "이름은 1자 이상 입력해 주세요."
    case .invalidDisplayName(.tooLong):
      "이름은 20자 이하로 입력해 주세요."
    case .invalidDisplayName(.containsEmoji):
      "이름에는 이모지를 사용할 수 없어요."
    case .invalidDisplayName(.containsControlCharacter):
      "이름에는 제어 문자를 사용할 수 없어요."
    case .profileUnavailable:
      "프로필 정보를 확인할 수 없어요."
    case .unavailableVoice:
      "이름을 저장하지 못했어요. 다시 시도해 주세요."
    }
  }
}

nonisolated enum AccountLifecycleAction: Equatable, Sendable {
  case logout
  case withdrawal
}
