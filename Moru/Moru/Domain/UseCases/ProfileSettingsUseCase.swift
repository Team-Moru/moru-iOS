//
//  ProfileSettingsUseCase.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import Foundation

struct ProfileSettingsLoadResult: Equatable {
  let profile: LocalProfile
  let settings: LocalSettingsSnapshot
}

enum ProfileDisplayNameValidationError: Error, Equatable {
  case empty
  case tooLong
  case containsEmoji
  case containsControlCharacter
}

enum ProfileSettingsUseCaseError: Error, Equatable {
  case profileUnavailable
  case settingsUnavailable
  case invalidDisplayName(ProfileDisplayNameValidationError)
  case unavailableVoice(String)
}

@MainActor
protocol ProfileSettingsUseCaseProtocol: AnyObject {
  func loadProfileSettings() throws -> ProfileSettingsLoadResult
  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult
  func selectVoice(voiceID: String) throws -> ProfileSettingsLoadResult
  func acknowledgeVoiceNotice() throws -> ProfileSettingsLoadResult
  func retryVoiceResolution() throws -> ProfileSettingsLoadResult
  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool
}

@MainActor
final class ProfileSettingsUseCase: ProfileSettingsUseCaseProtocol {
  private let localProfileRepository: any LocalProfileRepository
  private let localSettingsRepository: any LocalSettingsRepository
  private let voiceAvailabilityProbe: any VoiceAvailabilityProbing
  private let now: () -> Date

  init(
    localProfileRepository: any LocalProfileRepository,
    localSettingsRepository: any LocalSettingsRepository,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing,
    now: @escaping () -> Date = Date.init
  ) {
    self.localProfileRepository = localProfileRepository
    self.localSettingsRepository = localSettingsRepository
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
    self.now = now
  }

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    let profile = try requiredProfile()
    let settings = try localSettingsRepository.resolveVoiceSettings(profileID: profile.id)
    return makeLoadResult(profile: profile, settings: settings)
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    var profile = try requiredProfile()
    let settings = try requiredSettings(profileID: profile.id)
    let validatedName = try validatedDisplayName(from: displayName)

    profile.displayName = validatedName
    profile.updatedAt = now()
    try localProfileRepository.saveProfile(profile)

    return ProfileSettingsLoadResult(profile: profile, settings: settings)
  }

  func selectVoice(voiceID: String) throws -> ProfileSettingsLoadResult {
    guard let voice = VoiceProfile.catalogueVoice(id: voiceID), isVoiceAvailable(voice) else {
      throw ProfileSettingsUseCaseError.unavailableVoice(voiceID)
    }

    let profile = try requiredProfile()
    let settings = try localSettingsRepository.selectVoice(
      profileID: profile.id,
      voiceID: voice.id
    )
    return makeLoadResult(profile: profile, settings: settings)
  }

  func acknowledgeVoiceNotice() throws -> ProfileSettingsLoadResult {
    let profile = try requiredProfile()
    let settings = try requiredSettings(profileID: profile.id)
    try localSettingsRepository.acknowledgeVoiceNotice(profileID: profile.id)

    return ProfileSettingsLoadResult(
      profile: profile,
      settings: acknowledgedSettings(from: settings)
    )
  }

  func retryVoiceResolution() throws -> ProfileSettingsLoadResult {
    let profile = try requiredProfile()
    let settings = try localSettingsRepository.resolveVoiceSettings(profileID: profile.id)
    return makeLoadResult(profile: profile, settings: settings)
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    guard VoiceProfile.catalogueVoice(id: voice.id) == voice else {
      return false
    }

    return voiceAvailabilityProbe.isAvailable(voice)
  }

  private func requiredProfile() throws -> LocalProfile {
    guard let profile = try localProfileRepository.fetchProfile() else {
      throw ProfileSettingsUseCaseError.profileUnavailable
    }

    return profile
  }

  private func requiredSettings(profileID: UUID) throws -> LocalSettingsSnapshot {
    guard let settings = try localSettingsRepository.fetchSettings(profileID: profileID) else {
      throw ProfileSettingsUseCaseError.settingsUnavailable
    }

    return settings
  }

  private func makeLoadResult(
    profile: LocalProfile,
    settings: LocalSettingsSnapshot
  ) -> ProfileSettingsLoadResult {
    var resolvedProfile = profile

    if let resolvedVoiceID = settings.resolvedVoiceID,
       let resolvedVoice = VoiceProfile.catalogueVoice(id: resolvedVoiceID) {
      resolvedProfile.selectedVoice = resolvedVoice
      resolvedProfile.updatedAt = settings.migrationUpdatedAt ?? resolvedProfile.updatedAt
    }

    return ProfileSettingsLoadResult(profile: resolvedProfile, settings: settings)
  }

  private func acknowledgedSettings(
    from settings: LocalSettingsSnapshot
  ) -> LocalSettingsSnapshot {
    let acknowledgedState: VoiceMigrationState

    switch settings.voiceMigrationState {
    case .fallbackNoticePending:
      acknowledgedState = .fallbackNoticeAcknowledged
    case .noFallbackNoticePending:
      acknowledgedState = .noFallbackNoticeAcknowledged
    case .unresolved,
         .resolved,
         .fallbackNoticeAcknowledged,
         .noFallbackNoticeAcknowledged,
         .corruptRecoveryPending:
      acknowledgedState = settings.voiceMigrationState
    }

    return LocalSettingsSnapshot(
      id: settings.id,
      profileID: settings.profileID,
      voiceMigrationState: acknowledgedState,
      originalVoiceID: settings.originalVoiceID,
      resolvedVoiceID: settings.resolvedVoiceID,
      migrationUpdatedAt: settings.migrationUpdatedAt,
      schemaMigrationMarker: settings.schemaMigrationMarker
    )
  }

  private func validatedDisplayName(from displayName: String) throws -> String {
    guard !containsControlCharacter(in: displayName) else {
      throw ProfileSettingsUseCaseError.invalidDisplayName(.containsControlCharacter)
    }

    let trimmedName = displayName.trimmingCharacters(in: .whitespaces)

    guard !trimmedName.isEmpty else {
      throw ProfileSettingsUseCaseError.invalidDisplayName(.empty)
    }
    guard trimmedName.count <= 20 else {
      throw ProfileSettingsUseCaseError.invalidDisplayName(.tooLong)
    }
    guard !containsEmoji(in: trimmedName) else {
      throw ProfileSettingsUseCaseError.invalidDisplayName(.containsEmoji)
    }

    return trimmedName
  }

  private func containsControlCharacter(in text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      switch scalar.properties.generalCategory {
      case .control, .format, .lineSeparator, .paragraphSeparator:
        true
      default:
        false
      }
    }
  }

  private func containsEmoji(in text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      scalar.properties.isEmojiPresentation
        || (!scalar.isASCII && scalar.properties.isEmoji)
        || scalar.value == 0xFE0F
        || scalar.value == 0x20E3
    }
  }
}
