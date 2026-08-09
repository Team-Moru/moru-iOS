//
//  ServerRoutineTTSModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerRoutineTTSItem: Equatable, Sendable {
  let routineID: Int64
  let title: String?
  let type: ServerRoutineTTSRoutineType?

  /// `nil` means that the server omitted the field. `[]` means no TTS steps.
  let steps: [ServerRoutineTTSStep]?
}

nonisolated enum ServerRoutineTTSRoutineType: Equatable, Sendable {
  case check
  case timer
  case input
  case unknown(String)
}

nonisolated struct ServerRoutineTTSStep: Equatable, Sendable {
  let stepID: Int64
  let content: String?
  let ttsIntro: String?
  let status: ServerRoutineTTSStatus?

  /// The server can keep returning the previous audio while regeneration is
  /// pending or has failed.
  let audioURL: URL?
}

nonisolated enum ServerRoutineTTSStatus: Equatable, Sendable {
  case pending
  case completed
  case failed
  case unknown(String)
}
