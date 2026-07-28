//
//  VoiceSelectionMutationExecutor.swift
//  Moru
//

import Foundation

nonisolated final class VoiceSelectionMutationExecutor:
  ServerMutationExecuting,
  @unchecked Sendable {
  private let remoteService: any AccountVoiceRemoteServing
  private let catalogueRepository: any ServerVoiceCatalogRepository
  private let compatibilityTable: VoiceCompatibilityTable

  init(
    remoteService: any AccountVoiceRemoteServing,
    catalogueRepository: any ServerVoiceCatalogRepository,
    compatibilityTable: VoiceCompatibilityTable = .production
  ) {
    self.remoteService = remoteService
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

    let response: AuthoritativeServerVoiceSelection
    do {
      response = try await remoteService.updateSelection(
        ttsID: payload.ttsID,
        memberID: mutation.memberID
      )
    } catch AccountVoiceRemoteError.accountAuthorizationChanged {
      return .deferred
    }
    try Task.checkCancellation()
    let responseVoiceCode = VoiceCompatibilityTable.normalizedServerVoiceCode(
      response.voiceCode
    )
    guard response.memberID == mutation.memberID else {
      throw AccountVoiceRemoteError.authoritativeMismatch
    }

    try Task.checkCancellation()
    let authoritativeSelection = AuthoritativeServerVoiceSelection(
      memberID: response.memberID,
      ttsID: response.ttsID,
      voiceCode: responseVoiceCode,
      displayName: response.displayName
    )
    try await catalogueRepository.recordAuthoritativeSelection(
      authoritativeSelection
    )

    guard compatibilityTable.localVoiceID(
      forServerVoiceCode: responseVoiceCode
    ) == payload.localVoiceID else {
      throw AccountVoiceRemoteError.authoritativeMismatch
    }

    return .sent
  }
}
