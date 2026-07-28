//
//  ServerPreferenceRepositories.swift
//  Moru
//

import Foundation

nonisolated protocol AccountVoiceRemoteServing: Sendable {
  func fetchVoices(
    memberID: Int64
  ) async throws -> [ServerVoiceCatalogueItem]
  func updateSelection(
    ttsID: Int64,
    memberID: Int64
  ) async throws -> AuthoritativeServerVoiceSelection
}

@MainActor
protocol SignedInMemberProviding: AnyObject {
  var signedInMemberID: Int64? { get }
}

@MainActor
protocol ServerSynchronizing: AnyObject {
  func synchronize(memberID: Int64, trigger: SyncTrigger) async
  func suspendSynchronization(memberID: Int64) async
  func resumeSynchronization(memberID: Int64)
}

@MainActor
protocol ServerMutationRepository: AnyObject {
  @discardableResult
  func enqueue(_ mutation: EnqueuedServerMutation) throws -> ServerMutation
  func mutations(
    memberID: Int64,
    dueAt date: Date,
    includeBlocked: Bool
  ) throws -> [ServerMutation]
  func recordFailure(
    _ failure: ServerMutationFailure,
    for mutation: ServerMutation,
    at date: Date
  ) throws
  func removeSucceeded(_ mutation: ServerMutation) throws
}

@MainActor
protocol ServerVoiceCatalogRepository: AnyObject {
  func catalog(memberID: Int64) throws -> [ServerVoiceCatalogEntry]
  func replaceCatalog(
    _ entries: [ServerVoiceCatalogEntry],
    memberID: Int64
  ) throws
  func recordAuthoritativeSelection(
    _ selection: AuthoritativeServerVoiceSelection
  ) throws
  func clearAuthoritativeSelection(memberID: Int64) throws
}
