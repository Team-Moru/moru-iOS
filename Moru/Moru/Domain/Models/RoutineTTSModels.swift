//
//  RoutineTTSModels.swift
//  Moru
//

import Foundation

enum RoutineTTSLinkStatus: String, Codable, CaseIterable, Hashable, Sendable {
  case creating
  case generating
  case ready
  case failed
  case stale
}

struct RoutineTTSAsset: Codable, Hashable, Sendable {
  let localStepID: UUID
  let serverRoutineID: Int64
  let serverStepID: Int64
  let orderIndex: Int
  var cachedRelativePath: String?

  init(
    localStepID: UUID,
    serverRoutineID: Int64,
    serverStepID: Int64,
    orderIndex: Int,
    cachedRelativePath: String? = nil
  ) {
    self.localStepID = localStepID
    self.serverRoutineID = serverRoutineID
    self.serverStepID = serverStepID
    self.orderIndex = orderIndex
    self.cachedRelativePath = cachedRelativePath
  }
}

struct RoutineTTSLink: Hashable, Sendable {
  let localRoutineID: UUID
  var memberID: Int64
  var serverRoutineGroupID: Int64?
  var contentFingerprint: String
  var status: RoutineTTSLinkStatus
  var assets: [RoutineTTSAsset]
  var lastFailureCode: String?
  var createdAt: Date
  var updatedAt: Date

  init(
    localRoutineID: UUID,
    memberID: Int64,
    serverRoutineGroupID: Int64? = nil,
    contentFingerprint: String,
    status: RoutineTTSLinkStatus,
    assets: [RoutineTTSAsset] = [],
    lastFailureCode: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.localRoutineID = localRoutineID
    self.memberID = memberID
    self.serverRoutineGroupID = serverRoutineGroupID
    self.contentFingerprint = contentFingerprint
    self.status = status
    self.assets = assets
    self.lastFailureCode = lastFailureCode
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
