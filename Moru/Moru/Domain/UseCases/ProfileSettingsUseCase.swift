//
//  ProfileSettingsUseCase.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

struct ProfileSettingsLoadResult: Equatable {
  let profile: LocalProfile
  let fallbackNotice: String?
}

enum ProfileDisplayNameValidationError: Error, Equatable {
  case empty
  case tooLong
  case containsEmoji
  case containsControlCharacter
}

enum ProfileSettingsUseCaseError: Error, Equatable {
  case profileUnavailable
  case invalidDisplayName(ProfileDisplayNameValidationError)
  case unavailableVoice(String)
}

@MainActor
protocol ProfileSettingsUseCaseProtocol: AnyObject {
  func loadProfileSettings() throws -> ProfileSettingsLoadResult
  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult
  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult
  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool
}

@MainActor
final class ProfileSettingsUseCase: ProfileSettingsUseCaseProtocol {
  private let localProfileRepository: any LocalProfileRepository
  private let voiceAvailabilityProbe: any VoiceAvailabilityProbing
  private let now: () -> Date

  init(
    localProfileRepository: any LocalProfileRepository,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing,
    now: @escaping () -> Date = Date.init
  ) {
    self.localProfileRepository = localProfileRepository
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
    self.now = now
  }

  func loadProfileSettings() throws -> ProfileSettingsLoadResult {
    var profile = try requiredProfile()

    guard !isVoiceAvailable(profile.selectedVoice),
          let fallbackVoice = VoiceProfile.localVoices.first(where: isVoiceAvailable) else {
      return ProfileSettingsLoadResult(profile: profile, fallbackNotice: nil)
    }

    profile.selectedVoice = fallbackVoice
    profile.updatedAt = now()
    try localProfileRepository.saveProfile(profile)

    return ProfileSettingsLoadResult(
      profile: profile,
      fallbackNotice: "사용할 수 없는 목소리를 "
        + "\(fallbackVoice.displayName)(으)로 변경했어요."
    )
  }

  func saveDisplayName(_ displayName: String) throws -> ProfileSettingsLoadResult {
    var profile = try requiredProfile()
    profile.displayName = try validatedDisplayName(from: displayName)
    profile.updatedAt = now()
    try localProfileRepository.saveProfile(profile)
    return ProfileSettingsLoadResult(profile: profile, fallbackNotice: nil)
  }

  func selectVoice(_ voice: VoiceProfile) throws -> ProfileSettingsLoadResult {
    guard VoiceProfile.localVoices.contains(voice), isVoiceAvailable(voice) else {
      throw ProfileSettingsUseCaseError.unavailableVoice(voice.id)
    }

    var profile = try requiredProfile()
    profile.selectedVoice = voice
    profile.updatedAt = now()
    try localProfileRepository.saveProfile(profile)
    return ProfileSettingsLoadResult(profile: profile, fallbackNotice: nil)
  }

  func isVoiceAvailable(_ voice: VoiceProfile) -> Bool {
    VoiceProfile.localVoices.contains(voice) && voiceAvailabilityProbe.isAvailable(voice)
  }

  private func requiredProfile() throws -> LocalProfile {
    guard let profile = try localProfileRepository.fetchProfile() else {
      throw ProfileSettingsUseCaseError.profileUnavailable
    }

    return profile
  }

  private func validatedDisplayName(from displayName: String) throws -> String {
    guard !containsControlCharacter(in: displayName) else {
      throw ProfileSettingsUseCaseError.invalidDisplayName(.containsControlCharacter)
    }

    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

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
