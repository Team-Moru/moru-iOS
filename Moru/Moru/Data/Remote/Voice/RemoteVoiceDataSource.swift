//
//  RemoteVoiceDataSource.swift
//  Moru
//

import Foundation

nonisolated protocol VoiceRemoteDataSource: Sendable {
  func fetchVoices() async throws -> [VoiceResponseDTO]
  func updateSelection(ttsID: Int64) async throws -> TtsUpdateResponseDTO
}

nonisolated enum VoiceRemoteDataSourceError: Error, Equatable, Sendable {
  case invalidCatalogue
  case invalidTtsID
  case invalidUpdateResponse
  case authoritativeMismatch
}

nonisolated final class DefaultVoiceRemoteDataSource: VoiceRemoteDataSource {
  private let apiClient: any APIClient

  init(apiClient: any APIClient) {
    self.apiClient = apiClient
  }

  func fetchVoices() async throws -> [VoiceResponseDTO] {
    let response = try await apiClient.request(
      VoiceTarget.catalogue,
      as: VoiceListResponseDTO.self
    )
    var seenTtsIDs: Set<Int64> = []
    var seenVoiceCodes: Set<String> = []

    for voice in response.voices {
      let voiceCode = VoiceCompatibilityTable.normalizedServerVoiceCode(
        voice.voiceCode
      )
      let displayName = voice.displayName.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard voice.ttsId > 0,
            !voiceCode.isEmpty,
            !displayName.isEmpty,
            seenTtsIDs.insert(voice.ttsId).inserted,
            seenVoiceCodes.insert(voiceCode).inserted else {
        throw VoiceRemoteDataSourceError.invalidCatalogue
      }
    }

    return response.voices
  }

  func updateSelection(ttsID: Int64) async throws -> TtsUpdateResponseDTO {
    guard ttsID > 0 else {
      throw VoiceRemoteDataSourceError.invalidTtsID
    }

    let response = try await apiClient.request(
      VoiceTarget.updateSelection(TtsUpdateRequestDTO(ttsId: ttsID)),
      as: TtsUpdateResponseDTO.self
    )
    guard response.memberId > 0,
          response.ttsId > 0,
          !VoiceCompatibilityTable.normalizedServerVoiceCode(
            response.voiceCode
          ).isEmpty,
          !response.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty else {
      throw VoiceRemoteDataSourceError.invalidUpdateResponse
    }

    return response
  }
}
