//
//  ServerPreferenceRepositories.swift
//  Moru
//

import Foundation

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
  func upsertCatalog(
    _ entries: [ServerVoiceCatalogEntry],
    memberID: Int64
  ) throws
  func recordAuthoritativeSelection(
    _ selection: AuthoritativeServerVoiceSelection
  ) throws
}
