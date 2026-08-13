//
//  RoutineTTSAudioCacheCleaner.swift
//  Moru
//

import Foundation

nonisolated struct RoutineTTSAudioCacheCleaner:
  RoutineTTSAudioCacheCleaning,
  Sendable {
  let cache: RoutineTTSAudioCache

  func removeAllRoutineTTSAudio() async throws {
    try await cache.purgeAll()
  }

  func removeRoutineTTSAudio(memberID: Int64) async throws {
    guard memberID > 0 else {
      throw RoutineTTSAudioCacheError.invalidKey
    }
    try await cache.purge(accountID: String(memberID))
  }
}

/// Keeps the durable account-cleanup marker until recoverable server audio has
/// also been removed. This closes the withdrawal crash window without adding
/// cached bytes to the server-side deletion transaction.
nonisolated final class RoutineTTSAudioAccountScopedDataCleaner:
  AccountScopedDataCleaning,
  @unchecked Sendable {
  private let base: any AccountScopedDataCleaning
  private let audioCleaner: any RoutineTTSAudioCacheCleaning

  init(
    base: any AccountScopedDataCleaning,
    audioCleaner: any RoutineTTSAudioCacheCleaning
  ) {
    self.base = base
    self.audioCleaner = audioCleaner
  }

  func removeAccountScopedData(memberID: Int64) async throws {
    try await audioCleaner.removeRoutineTTSAudio(memberID: memberID)
    try await base.removeAccountScopedData(memberID: memberID)
  }

  func preparePendingAccountCleanup(memberID: Int64) async throws {
    try await base.preparePendingAccountCleanup(memberID: memberID)
  }

  func beginPendingAccountCleanupAttempt(memberID: Int64) async throws {
    try await base.beginPendingAccountCleanupAttempt(memberID: memberID)
  }

  func confirmPendingAccountCleanup(memberID: Int64) async throws {
    try await base.confirmPendingAccountCleanup(memberID: memberID)
  }

  func cancelPendingAccountCleanup(memberID: Int64) async throws {
    try await base.cancelPendingAccountCleanup(memberID: memberID)
  }

  func completePendingAccountCleanup(memberID: Int64) async throws {
    // The base first advances the durable marker to localDataCleaned. A cache
    // failure then remains recoverable on the next launch.
    try await base.completePendingAccountCleanup(memberID: memberID)
    try await audioCleaner.removeRoutineTTSAudio(memberID: memberID)
  }

  func finalizePendingAccountCleanup(memberID: Int64) async throws {
    // Purge before deleting the last marker so a crash or filesystem failure
    // cannot silently orphan withdrawn-account audio.
    try await audioCleaner.removeRoutineTTSAudio(memberID: memberID)
    try await base.finalizePendingAccountCleanup(memberID: memberID)
  }

  func recoverPendingAccountCleanups() async throws -> PendingAccountCleanupRecovery {
    try await base.recoverPendingAccountCleanups()
  }
}
