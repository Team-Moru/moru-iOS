//
//  SyncMetadata.swift
//  Moru
//

import Foundation

enum SyncStatus: String, Codable, CaseIterable, Hashable {
  case localOnly
}

struct SyncMetadata: Codable, Hashable {
  var remoteID: String?
  var status: SyncStatus
  var lastSyncedAt: Date?
  var remoteRevision: String?

  init(
    remoteID: String? = nil,
    status: SyncStatus = .localOnly,
    lastSyncedAt: Date? = nil,
    remoteRevision: String? = nil
  ) {
    self.remoteID = remoteID
    self.status = status
    self.lastSyncedAt = lastSyncedAt
    self.remoteRevision = remoteRevision
  }

  static let localOnly = SyncMetadata()
}
