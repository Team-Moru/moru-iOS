//
//  RemoteVoiceDataSource.swift
//  Moru
//

import Foundation

nonisolated final class DefaultVoiceRemoteDataSource:
  AccountVoiceRemoteServing {
  private let apiClient: any AccountBoundAPIClient

  init(apiClient: any AccountBoundAPIClient) {
    self.apiClient = apiClient
  }

  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerVoiceCatalogueItem] {
    let response: VoiceListResponseDTO
    do {
      response = try await apiClient.request(
        VoiceTarget.catalogue,
        as: VoiceListResponseDTO.self,
        authorizedForMemberID: memberID
      )
    } catch is AccountAuthorizationContextError {
      throw AccountVoiceRemoteError.accountAuthorizationChanged
    } catch APIError.cancelled {
      throw CancellationError()
    }
    let voices = try response.voices.map { try $0.makeDomainModel() }
    var seenTtsIDs: Set<Int64> = []
    var seenVoiceCodes: Set<String> = []

    for voice in voices {
      guard seenTtsIDs.insert(voice.ttsID).inserted,
            seenVoiceCodes.insert(voice.voiceCode).inserted else {
        throw AccountVoiceRemoteError.invalidCatalogue
      }
    }

    return voices
  }

  func updateSelection(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> AuthoritativeServerVoiceSelection {
    guard ttsID > 0, memberID > 0 else {
      throw AccountVoiceRemoteError.invalidTtsID
    }

    do {
      let response = try await apiClient.request(
        VoiceTarget.updateSelection(TtsUpdateRequestDTO(ttsId: ttsID)),
        as: TtsUpdateResponseDTO.self,
        authorizedForMemberID: memberID
      )
      return try response.makeDomainModel()
    } catch is AccountAuthorizationContextError {
      throw AccountVoiceRemoteError.accountAuthorizationChanged
    } catch APIError.cancelled {
      throw CancellationError()
    }
  }
}
