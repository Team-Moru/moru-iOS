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

  /// A remote audio URL is exposed only when the complete playable contract
  /// is satisfied. Callers must still download and validate the asset before
  /// playback rather than streaming this URL directly.
  let audioURL: URL?

  var isPlayable: Bool {
    audioURL != nil
  }
}

nonisolated enum ServerRoutineTTSGenerationStatus: Equatable, Sendable {
  case pending
  case completed
  case failed
  case unknown(String)
}
