//
//  AccountServerDTO.swift
//  Moru
//

import Foundation

nonisolated struct AccountProfileResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let memberId: Int64?
  let nickname: String?
  let loginType: String?
  let profileImageKey: String?
  let ttsId: Int64?
}

nonisolated struct AccountStreakResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let currentStreak: Int64?
  let maxStreak: Int64?
  let weeklyStatus: [Bool]?
}

nonisolated struct TTSVoiceListResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let voices: [TTSVoiceResponseDTO]?
}

nonisolated struct TTSVoiceResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let ttsId: Int64?
  let voiceCode: String?
  let displayName: String?
  let description: String?
  let proOnly: Bool?
  let previewAudioUrl: String?

  init(
    ttsId: Int64?,
    voiceCode: String?,
    displayName: String?,
    description: String?,
    proOnly: Bool?,
    previewAudioUrl: String? = nil
  ) {
    self.ttsId = ttsId
    self.voiceCode = voiceCode
    self.displayName = displayName
    self.description = description
    self.proOnly = proOnly
    self.previewAudioUrl = previewAudioUrl
  }
}

nonisolated struct TTSUpdateRequestDTO:
  Encodable,
  Equatable,
  Sendable {
  let ttsId: Int64
}

nonisolated struct TTSUpdateResponseDTO:
  Decodable,
  Equatable,
  Sendable {
  let memberId: Int64?
  let ttsId: Int64?
  let voiceCode: String?
  let displayName: String?
  let selectionVersion: Int64?
}
