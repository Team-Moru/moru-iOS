//
//  ServerPreferenceModels.swift
//  Moru
//

import Foundation

nonisolated enum IdempotentServerOperation: String, CaseIterable, Sendable {
  case replaceVoiceSelection
}

nonisolated struct ServerMutation: Equatable, Sendable {
  let id: UUID
  let memberID: Int64
  let operation: IdempotentServerOperation
  let operationKey: String
  let payload: Data
  let idempotencyKey: UUID
  let createdAt: Date
  let updatedAt: Date
  let attemptCount: Int
  let nextAttemptAt: Date?
  let lastFailure: ServerMutationFailure?
}

nonisolated struct EnqueuedServerMutation: Equatable, Sendable {
  let memberID: Int64
  let operation: IdempotentServerOperation
  let operationKey: String
  let payload: Data

  init(
    memberID: Int64,
    operation: IdempotentServerOperation,
    operationKey: String,
    payload: Data
  ) {
    self.memberID = memberID
    self.operation = operation
    self.operationKey = operationKey
    self.payload = payload
  }
}

nonisolated enum ServerMutationFailure: String, Equatable, Sendable {
  case transport
  case requestTimeout
  case rateLimited
  case serverUnavailable
  case nonRetryable

  var isRetryable: Bool {
    switch self {
    case .transport, .requestTimeout, .rateLimited, .serverUnavailable:
      true
    case .nonRetryable:
      false
    }
  }
}

nonisolated struct ServerVoiceCatalogEntry: Equatable, Sendable {
  let id: UUID
  let memberID: Int64
  let voiceCode: String
  let displayName: String
  /// Kept losslessly so a server tier added after this app ships does not corrupt the cache.
  let tierRawValue: String
  let isLocallyPlayable: Bool
  let fetchedAt: Date

  init(
    id: UUID = UUID(),
    memberID: Int64,
    voiceCode: String,
    displayName: String,
    tierRawValue: String,
    isLocallyPlayable: Bool,
    fetchedAt: Date
  ) {
    self.id = id
    self.memberID = memberID
    self.voiceCode = voiceCode
    self.displayName = displayName
    self.tierRawValue = tierRawValue
    self.isLocallyPlayable = isLocallyPlayable
    self.fetchedAt = fetchedAt
  }
}

nonisolated enum ServerPreferenceRepositoryError: Error, Equatable, Sendable {
  case invalidMemberID
  case invalidOperationKey
  case invalidPayload
  case invalidVoiceCode
  case invalidVoiceDisplayName
}
