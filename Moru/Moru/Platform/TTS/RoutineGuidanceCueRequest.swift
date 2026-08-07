//
//  RoutineGuidanceCueRequest.swift
//  Moru
//

import Foundation

nonisolated struct RoutineGuidanceCueRequest: Equatable, Sendable {
  let localRoutineID: UUID?
  let localStepID: UUID?
  let presetItemID: String?
  let voiceCode: String
  let kind: RoutineAudioCueKind

  init(
    localRoutineID: UUID? = nil,
    localStepID: UUID? = nil,
    presetItemID: String?,
    voiceCode: String,
    kind: RoutineAudioCueKind
  ) {
    self.localRoutineID = localRoutineID
    self.localStepID = localStepID
    self.presetItemID = presetItemID
    self.voiceCode = voiceCode
    self.kind = kind
  }
}
