//
//  SwiftDataServerPreferenceRepository.swift
//  Moru
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataServerPreferenceRepository:
  ServerMutationRepository,
  ServerVoiceCatalogRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @discardableResult
  func enqueue(_ mutation: EnqueuedServerMutation) throws -> ServerMutation {
    let operationKey = mutation.operationKey.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard mutation.memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }
    guard !operationKey.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidOperationKey
    }
    guard !mutation.payload.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidPayload
    }

    let now = Date()
    let matching = try persistedMutations().filter {
      $0.memberID == mutation.memberID && $0.operationKey == operationKey
    }
    let persisted: PersistedServerMutation

    if let newest = matching.max(by: { $0.updatedAt < $1.updatedAt }) {
      persisted = newest
      persisted.operationRawValue = mutation.operation.rawValue
      persisted.payload = mutation.payload
      persisted.idempotencyKey = UUID()
      persisted.updatedAt = now
      persisted.attemptCount = 0
      persisted.nextAttemptAt = nil
      persisted.lastFailureRawValue = nil
      matching
        .filter { $0 !== newest }
        .forEach(modelContext.delete)
    } else {
      persisted = PersistedServerMutation(
        id: UUID(),
        memberID: mutation.memberID,
        operationRawValue: mutation.operation.rawValue,
        operationKey: operationKey,
        payload: mutation.payload,
        idempotencyKey: UUID(),
        createdAt: now,
        updatedAt: now,
        attemptCount: 0,
        nextAttemptAt: nil,
        lastFailureRawValue: nil
      )
      modelContext.insert(persisted)
    }

    try saveOrRollback()
    return try makeMutation(persisted)
  }

  func mutations(
    memberID: Int64,
    dueAt date: Date,
    includeBlocked: Bool
  ) throws -> [ServerMutation] {
    guard memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }

    let valid = try persistedMutations()
      .filter { $0.memberID == memberID }
      .compactMap { try? makeMutation($0) }
      .filter { mutation in
        if includeBlocked {
          return true
        }
        if mutation.lastFailure == .nonRetryable {
          return false
        }
        return mutation.nextAttemptAt.map { $0 <= date } ?? true
      }
      .sorted {
        if $0.createdAt == $1.createdAt {
          return $0.id.uuidString < $1.id.uuidString
        }
        return $0.createdAt < $1.createdAt
      }

    var newestByOperationKey: [String: ServerMutation] = [:]
    for mutation in valid {
      let current = newestByOperationKey[mutation.operationKey]
      if current == nil || current!.updatedAt < mutation.updatedAt {
        newestByOperationKey[mutation.operationKey] = mutation
      }
    }

    return newestByOperationKey.values.sorted {
      if $0.createdAt == $1.createdAt {
        return $0.id.uuidString < $1.id.uuidString
      }
      return $0.createdAt < $1.createdAt
    }
  }

  func recordFailure(
    _ failure: ServerMutationFailure,
    for mutation: ServerMutation,
    at date: Date
  ) throws {
    guard let persisted = try persistedMutation(id: mutation.id),
          persisted.idempotencyKey == mutation.idempotencyKey else {
      return
    }

    let nextAttemptCount = max(persisted.attemptCount, 0) + 1
    persisted.attemptCount = nextAttemptCount
    persisted.updatedAt = date
    persisted.lastFailureRawValue = failure.rawValue
    persisted.nextAttemptAt = failure.isRetryable
      ? date.addingTimeInterval(
        ServerMutationBackoff.delay(afterAttempt: nextAttemptCount)
      )
      : nil
    try saveOrRollback()
  }

  func removeSucceeded(_ mutation: ServerMutation) throws {
    guard let persisted = try persistedMutation(id: mutation.id),
          persisted.idempotencyKey == mutation.idempotencyKey else {
      return
    }

    let matching = try persistedMutations().filter {
      $0.memberID == mutation.memberID
        && $0.operationKey == mutation.operationKey
    }
    matching.forEach(modelContext.delete)
    try saveOrRollback()
  }

  func catalog(memberID: Int64) throws -> [ServerVoiceCatalogEntry] {
    guard memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }

    let valid = try persistedVoiceEntries()
      .filter { $0.memberID == memberID }
      .compactMap { try? makeVoiceEntry($0) }
      .sorted {
        if $0.fetchedAt == $1.fetchedAt {
          return $0.id.uuidString < $1.id.uuidString
        }
        return $0.fetchedAt > $1.fetchedAt
      }

    var newestByVoiceCode: [String: ServerVoiceCatalogEntry] = [:]
    for entry in valid where newestByVoiceCode[entry.voiceCode] == nil {
      newestByVoiceCode[entry.voiceCode] = entry
    }

    return newestByVoiceCode.values.sorted {
      if $0.displayName == $1.displayName {
        return $0.voiceCode < $1.voiceCode
      }
      return $0.displayName < $1.displayName
    }
  }

  func upsertCatalog(
    _ entries: [ServerVoiceCatalogEntry],
    memberID: Int64
  ) throws {
    guard memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }

    let normalized = try entries.map { entry in
      guard entry.memberID == memberID else {
        throw ServerPreferenceRepositoryError.invalidMemberID
      }

      let voiceCode = entry.voiceCode.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayName = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !voiceCode.isEmpty else {
        throw ServerPreferenceRepositoryError.invalidVoiceCode
      }
      guard !displayName.isEmpty else {
        throw ServerPreferenceRepositoryError.invalidVoiceDisplayName
      }

      return ServerVoiceCatalogEntry(
        id: entry.id,
        memberID: memberID,
        voiceCode: voiceCode,
        displayName: displayName,
        tierRawValue: entry.tierRawValue,
        isLocallyPlayable: entry.isLocallyPlayable,
        fetchedAt: entry.fetchedAt
      )
    }

    do {
      for entry in normalized {
        let matching = try persistedVoiceEntries().filter {
          $0.memberID == memberID && $0.voiceCode == entry.voiceCode
        }
        if let newest = matching.max(by: { $0.fetchedAt < $1.fetchedAt }) {
          newest.displayName = entry.displayName
          newest.tierRawValue = entry.tierRawValue
          newest.isLocallyPlayable = entry.isLocallyPlayable
          newest.fetchedAt = entry.fetchedAt
          matching
            .filter { $0 !== newest }
            .forEach(modelContext.delete)
        } else {
          modelContext.insert(
            PersistedVoiceCatalogEntry(
              id: entry.id,
              memberID: memberID,
              voiceCode: entry.voiceCode,
              displayName: entry.displayName,
              tierRawValue: entry.tierRawValue,
              isLocallyPlayable: entry.isLocallyPlayable,
              fetchedAt: entry.fetchedAt
            )
          )
        }
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func recordAuthoritativeSelection(
    _ selection: AuthoritativeServerVoiceSelection
  ) throws {
    guard selection.memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }

    let voiceCode = VoiceCompatibilityTable.normalizedServerVoiceCode(
      selection.voiceCode
    )
    let displayName = selection.displayName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !voiceCode.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidVoiceCode
    }
    guard !displayName.isEmpty, selection.ttsID > 0 else {
      throw ServerPreferenceRepositoryError.invalidVoiceDisplayName
    }

    do {
      let accountEntries = try persistedVoiceEntries().filter {
        $0.memberID == selection.memberID
      }
      var foundSelection = false

      for entry in accountEntries {
        guard let metadata = VoiceCatalogMetadata.decode(
          rawValue: entry.tierRawValue
        ) else {
          continue
        }

        let isSelection = entry.voiceCode == voiceCode
          && metadata.ttsID == selection.ttsID
        entry.tierRawValue = try VoiceCatalogMetadata(
          ttsID: metadata.ttsID,
          proOnly: metadata.proOnly,
          description: metadata.description,
          isAuthoritativeSelection: isSelection
        ).encodedRawValue()
        foundSelection = foundSelection || isSelection
      }

      if !foundSelection {
        modelContext.insert(
          PersistedVoiceCatalogEntry(
            id: UUID(),
            memberID: selection.memberID,
            voiceCode: voiceCode,
            displayName: displayName,
            tierRawValue: try VoiceCatalogMetadata(
              ttsID: selection.ttsID,
              proOnly: false,
              description: nil,
              isAuthoritativeSelection: true
            ).encodedRawValue(),
            isLocallyPlayable: false,
            fetchedAt: Date()
          )
        )
      }

      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  func removeAccountScopedData(memberID: Int64) throws {
    do {
      try persistedMutations()
        .filter { $0.memberID == memberID }
        .forEach(modelContext.delete)
      try persistedVoiceEntries()
        .filter { $0.memberID == memberID }
        .forEach(modelContext.delete)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func persistedMutations() throws -> [PersistedServerMutation] {
    try modelContext.fetch(FetchDescriptor<PersistedServerMutation>())
  }

  private func persistedMutation(id: UUID) throws -> PersistedServerMutation? {
    try persistedMutations().first { $0.id == id }
  }

  private func persistedVoiceEntries() throws -> [PersistedVoiceCatalogEntry] {
    try modelContext.fetch(FetchDescriptor<PersistedVoiceCatalogEntry>())
  }

  private func makeMutation(
    _ persisted: PersistedServerMutation
  ) throws -> ServerMutation {
    guard persisted.memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }
    guard let operation = IdempotentServerOperation(
      rawValue: persisted.operationRawValue
    ) else {
      throw ServerPreferenceRepositoryError.invalidOperationKey
    }
    let operationKey = persisted.operationKey.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !operationKey.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidOperationKey
    }
    guard !persisted.payload.isEmpty, persisted.attemptCount >= 0 else {
      throw ServerPreferenceRepositoryError.invalidPayload
    }

    let failure: ServerMutationFailure?
    if let rawValue = persisted.lastFailureRawValue {
      guard let mapped = ServerMutationFailure(rawValue: rawValue) else {
        throw ServerPreferenceRepositoryError.invalidPayload
      }
      failure = mapped
    } else {
      failure = nil
    }

    return ServerMutation(
      id: persisted.id,
      memberID: persisted.memberID,
      operation: operation,
      operationKey: operationKey,
      payload: persisted.payload,
      idempotencyKey: persisted.idempotencyKey,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt,
      attemptCount: persisted.attemptCount,
      nextAttemptAt: persisted.nextAttemptAt,
      lastFailure: failure
    )
  }

  private func makeVoiceEntry(
    _ persisted: PersistedVoiceCatalogEntry
  ) throws -> ServerVoiceCatalogEntry {
    guard persisted.memberID > 0 else {
      throw ServerPreferenceRepositoryError.invalidMemberID
    }
    let voiceCode = persisted.voiceCode.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let displayName = persisted.displayName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !voiceCode.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidVoiceCode
    }
    guard !displayName.isEmpty else {
      throw ServerPreferenceRepositoryError.invalidVoiceDisplayName
    }

    return ServerVoiceCatalogEntry(
      id: persisted.id,
      memberID: persisted.memberID,
      voiceCode: voiceCode,
      displayName: displayName,
      tierRawValue: persisted.tierRawValue,
      isLocallyPlayable: persisted.isLocallyPlayable,
      fetchedAt: persisted.fetchedAt
    )
  }

  private func saveOrRollback() throws {
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }
}

nonisolated final class SwiftDataAccountScopedDataCleaner:
  AccountScopedDataCleaning,
  @unchecked Sendable {
  private let repository: SwiftDataServerPreferenceRepository

  init(repository: SwiftDataServerPreferenceRepository) {
    self.repository = repository
  }

  func removeAccountScopedData(memberID: Int64) async throws {
    try await repository.removeAccountScopedData(memberID: memberID)
  }
}
