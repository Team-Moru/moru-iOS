//
//  LocalResetJournalModels.swift
//  Moru
//

import Foundation

nonisolated enum LocalResetJournalPhase: String, Codable, CaseIterable, Sendable {
  case freezeRequested
  case gathering
  case sealed
  case cancelling
  case swiftDataDeleting
  case coordinatorClearing
  case completed
  case retryRequired

  var isTerminal: Bool {
    self == .completed
  }
}

nonisolated struct LocalResetJournalEntry: Codable, Equatable, Sendable {
  static let currentFormatVersion = 1

  let formatVersion: Int
  let operationID: UUID
  let revision: UInt64
  let generation: UInt64
  let phase: LocalResetJournalPhase
  let resumePhase: LocalResetJournalPhase?
  let sealedScheduleIDs: [UUID]
  let createdAt: Date
  let updatedAt: Date

  init(
    formatVersion: Int = LocalResetJournalEntry.currentFormatVersion,
    operationID: UUID,
    revision: UInt64,
    generation: UInt64,
    phase: LocalResetJournalPhase,
    resumePhase: LocalResetJournalPhase? = nil,
    sealedScheduleIDs: [UUID] = [],
    createdAt: Date,
    updatedAt: Date
  ) {
    self.formatVersion = formatVersion
    self.operationID = operationID
    self.revision = revision
    self.generation = generation
    self.phase = phase
    self.resumePhase = resumePhase
    self.sealedScheduleIDs = sealedScheduleIDs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
