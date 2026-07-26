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
  /// Opaque, versioned server catalogue metadata. Legacy P6 tier values remain lossless.
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

nonisolated struct VoiceCatalogMetadata: Codable, Equatable, Sendable {
  static let currentVersion = 1
  static let prefix = "moru.voice-catalog.v1:"

  let version: Int
  let ttsID: Int64
  let proOnly: Bool
  let description: String?
  let isAuthoritativeSelection: Bool

  init(
    ttsID: Int64,
    proOnly: Bool,
    description: String?,
    isAuthoritativeSelection: Bool
  ) {
    self.version = Self.currentVersion
    self.ttsID = ttsID
    self.proOnly = proOnly
    self.description = description
    self.isAuthoritativeSelection = isAuthoritativeSelection
  }

  func encodedRawValue() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Self.prefix + (try encoder.encode(self)).base64EncodedString()
  }

  static func decode(rawValue: String) -> VoiceCatalogMetadata? {
    guard rawValue.hasPrefix(prefix),
          let data = Data(
            base64Encoded: String(rawValue.dropFirst(prefix.count))
          ),
          let metadata = try? JSONDecoder().decode(Self.self, from: data),
          metadata.version == currentVersion,
          metadata.ttsID > 0 else {
      return nil
    }

    return metadata
  }
}

nonisolated enum AccountVoiceAvailability: Equatable, Sendable {
  case selectable
  case proOnly
  case incompatible
  case missingBundledAudio
  case unknownMetadata

  var isSelectable: Bool {
    self == .selectable
  }
}

nonisolated enum AccountVoiceSource: Equatable, Sendable {
  case serverCatalogue
  case bundledFallback
}

struct AccountVoiceOption: Identifiable, Equatable {
  let id: String
  let serverMemberID: Int64?
  let serverVoiceCode: String?
  let serverTtsID: Int64?
  let displayName: String
  let detail: String
  let localVoice: VoiceProfile?
  let availability: AccountVoiceAvailability
  let source: AccountVoiceSource
  let isAuthoritativeServerSelection: Bool
}

struct AccountVoiceMismatch: Equatable {
  let localVoice: VoiceProfile
  let serverVoice: AccountVoiceOption
}

struct AccountVoiceCatalogueSnapshot: Equatable {
  let options: [AccountVoiceOption]
  let mismatch: AccountVoiceMismatch?
  let notice: String?
}

nonisolated struct VoiceSelectionMutationPayload: Codable, Equatable, Sendable {
  static let currentVersion = 1
  static let operationKey = "account.voice.selection"

  let version: Int
  let memberID: Int64
  let ttsID: Int64
  let voiceCode: String
  let localVoiceID: String

  init(
    memberID: Int64,
    ttsID: Int64,
    voiceCode: String,
    localVoiceID: String
  ) {
    self.version = Self.currentVersion
    self.memberID = memberID
    self.ttsID = ttsID
    self.voiceCode = voiceCode
    self.localVoiceID = localVoiceID
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  static func decode(_ data: Data) throws -> VoiceSelectionMutationPayload {
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version == currentVersion,
          value.memberID > 0,
          value.ttsID > 0,
          !value.voiceCode.isEmpty,
          !value.localVoiceID.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidPayload
    }
    return value
  }
}

nonisolated struct AuthoritativeServerVoiceSelection: Equatable, Sendable {
  let memberID: Int64
  let ttsID: Int64
  let voiceCode: String
  let displayName: String
}

nonisolated enum ServerPreferenceRepositoryError: Error, Equatable, Sendable {
  case invalidMemberID
  case invalidOperationKey
  case invalidPayload
  case invalidVoiceCode
  case invalidVoiceDisplayName
}
