//
//  RoutineTTSModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerRoutineTTSRoutine: Equatable, Sendable {
  let routineID: Int64
  let title: String
  let type: ServerRoutineTTSRoutineType
  let steps: [ServerRoutineTTSStep]
}

nonisolated enum ServerRoutineTTSRoutineType: Equatable, Sendable {
  case check
  case timer
  case input
}

nonisolated struct ServerRoutineTTSStep: Equatable, Sendable {
  let stepID: Int64
  let content: String
  let introText: String?
  let status: ServerRoutineTTSGenerationStatus
  let selectionVersion: Int64?

  /// A remote audio URL is exposed only when the complete playable contract
  /// is satisfied. Callers must still download and validate the asset before
  /// playback rather than streaming this URL directly.
  let audioURL: URL?

  init(
    stepID: Int64,
    content: String,
    introText: String?,
    status: ServerRoutineTTSGenerationStatus,
    selectionVersion: Int64? = nil,
    audioURL: URL?
  ) {
    self.stepID = stepID
    self.content = content
    self.introText = introText
    self.status = status
    self.selectionVersion = selectionVersion
    self.audioURL = audioURL
  }

  var isPlayable: Bool {
    audioURL != nil
  }

  func matchesCurrentSelectionVersion(_ currentSelectionVersion: Int64?) -> Bool {
    // A missing side means a legacy server contract, not a mismatch.
    guard let currentSelectionVersion, let selectionVersion else {
      return true
    }
    return currentSelectionVersion == selectionVersion
  }
}

nonisolated enum ServerRoutineTTSGenerationStatus: Equatable, Sendable {
  case pending
  case completed
  case failed
  case unknown(String)
}
