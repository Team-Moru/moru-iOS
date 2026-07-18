//
//  LocalSettingsRepository.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import Foundation

protocol VoiceAvailabilityProbing: Sendable {
  func isAvailable(_ voice: VoiceProfile) -> Bool
}

struct UnavailableVoiceAvailabilityProbe: VoiceAvailabilityProbing {
  func isAvailable(_ voice: VoiceProfile) -> Bool {
    false
  }
}

@MainActor
protocol LocalSettingsRepository: Sendable {
  func fetchSettings(profileID: UUID) throws -> LocalSettingsSnapshot?
  func resolveVoiceSettings(profileID: UUID) throws -> LocalSettingsSnapshot
  func acknowledgeVoiceNotice(profileID: UUID) throws
  func selectVoice(profileID: UUID, voiceID: String) throws -> LocalSettingsSnapshot
}
