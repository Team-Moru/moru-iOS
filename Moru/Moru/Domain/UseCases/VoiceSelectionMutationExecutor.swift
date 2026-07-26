//
//  VoiceSelectionMutationExecutor.swift
//  Moru
//

import Foundation

nonisolated final class VoiceSelectionMutationExecutor:
  ServerMutationExecuting,
  @unchecked Sendable {
  private let remoteDataSource: any VoiceRemoteDataSource
  private let catalogueRepository: any ServerVoiceCatalogRepository
  private let compatibilityTable: VoiceCompatibilityTable

  init(
    remoteDataSource: any VoiceRemoteDataSource,
    catalogueRepository: any ServerVoiceCatalogRepository,
    compatibilityTable: VoiceCompatibilityTable = .production
  ) {
    self.remoteDataSource = remoteDataSource
    self.catalogueRepository = catalogueRepository
    self.compatibilityTable = compatibilityTable
  }

  func execute(
    _ mutation: ServerMutation
  ) async throws -> ServerMutationExecutionResult {
    guard mutation.operation == .replaceVoiceSelection else {
      return .deferred
    }
    guard mutation.operationKey == VoiceSelectionMutationPayload.operationKey else {
      throw ServerPreferenceRepositoryError.invalidPayload
    }

    let payload = try VoiceSelectionMutationPayload.decode(mutation.payload)
    let payloadVoiceCode = VoiceCompatibilityTable.normalizedServerVoiceCode(
      payload.voiceCode
    )
    guard payload.memberID == mutation.memberID,
          compatibilityTable.localVoiceID(
            forServerVoiceCode: payloadVoiceCode
          ) == payload.localVoiceID else {
      throw ServerPreferenceRepositoryError.invalidPayload
    }

    let response = try await remoteDataSource.updateSelection(
      ttsID: payload.ttsID
    )
    let responseVoiceCode = VoiceCompatibilityTable.normalizedServerVoiceCode(
      response.voiceCode
    )
    guard response.memberId == mutation.memberID,
          response.ttsId == payload.ttsID,
          responseVoiceCode == payloadVoiceCode else {
      throw VoiceRemoteDataSourceError.authoritativeMismatch
    }

    try await catalogueRepository.recordAuthoritativeSelection(
      AuthoritativeServerVoiceSelection(
        memberID: response.memberId,
        ttsID: response.ttsId,
        voiceCode: responseVoiceCode,
        displayName: response.displayName
      )
    )
    return .sent
  }
}
