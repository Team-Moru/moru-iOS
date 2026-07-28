//
//  VoiceDTO.swift
//  Moru
//

import Foundation

nonisolated struct VoiceListResponseDTO: Decodable, Equatable, Sendable {
  let voices: [VoiceResponseDTO]
}

nonisolated struct VoiceResponseDTO: Decodable, Equatable, Sendable {
  let ttsId: Int64
  let voiceCode: String
  let displayName: String
  let description: String?
  let proOnly: Bool
}

nonisolated struct TtsUpdateRequestDTO: Encodable, Equatable, Sendable {
  let ttsId: Int64
}

nonisolated struct TtsUpdateResponseDTO: Decodable, Equatable, Sendable {
  let memberId: Int64
  let ttsId: Int64
  let voiceCode: String
  let displayName: String
}
