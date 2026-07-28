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

nonisolated extension VoiceResponseDTO {
  func makeDomainModel() throws -> ServerVoiceCatalogueItem {
    let normalizedVoiceCode = VoiceCompatibilityTable
      .normalizedServerVoiceCode(voiceCode)
    let normalizedDisplayName = displayName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let normalizedDescription = description?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard ttsId > 0,
          !normalizedVoiceCode.isEmpty,
          !normalizedDisplayName.isEmpty else {
      throw AccountVoiceRemoteError.invalidCatalogue
    }

    return ServerVoiceCatalogueItem(
      ttsID: ttsId,
      voiceCode: normalizedVoiceCode,
      displayName: normalizedDisplayName,
      description: normalizedDescription?.isEmpty == true
        ? nil
        : normalizedDescription,
      proOnly: proOnly
    )
  }
}

nonisolated extension TtsUpdateResponseDTO {
  func makeDomainModel() throws -> AuthoritativeServerVoiceSelection {
    let normalizedVoiceCode = VoiceCompatibilityTable
      .normalizedServerVoiceCode(voiceCode)
    let normalizedDisplayName = displayName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    guard memberId > 0,
          ttsId > 0,
          !normalizedVoiceCode.isEmpty,
          !normalizedDisplayName.isEmpty else {
      throw AccountVoiceRemoteError.invalidUpdateResponse
    }

    return AuthoritativeServerVoiceSelection(
      memberID: memberId,
      ttsID: ttsId,
      voiceCode: normalizedVoiceCode,
      displayName: normalizedDisplayName
    )
  }
}
