//
//  RoutineTTSWarming.swift
//  Moru
//

import Foundation

@MainActor
protocol RoutineTTSWarming: AnyObject {
  func prepare(routineGroupLocalID: UUID, routineLocalIDs: [UUID])
  /// Indicates whether this step is synced already or has a pending synced
  /// creation on the current account. A step without that intent remains a
  /// local cue instead of waiting for server audio.
  func expectsServerGeneratedIntro(
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) -> Bool
  func prepareAndWait(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) async -> RoutineTTSForegroundPreparationStatus
}

@MainActor
protocol RoutineTTSVoiceSelectionVersionStoring: AnyObject {
  func selectionVersion(forMemberID memberID: Int64) -> Int64?
  func setSelectionVersion(_ version: Int64, forMemberID memberID: Int64)
  func removeSelectionVersion(forMemberID memberID: Int64)
  func selectedTTSID(forMemberID memberID: Int64) -> Int64?
  func setSelectedTTSID(_ ttsID: Int64, forMemberID memberID: Int64)
  func removeSelectedTTSID(forMemberID memberID: Int64)
}

extension RoutineTTSVoiceSelectionVersionStoring {
  func selectedTTSID(forMemberID memberID: Int64) -> Int64? { nil }
  func setSelectedTTSID(_ ttsID: Int64, forMemberID memberID: Int64) {}
  func removeSelectedTTSID(forMemberID memberID: Int64) {}
}

extension RoutineTTSWarming {
  func expectsServerGeneratedIntro(
    routineGroupLocalID: UUID,
    routineLocalID: UUID
  ) -> Bool {
    false
  }

  /// Keeps lightweight test and preview doubles source-compatible while the
  /// production coordinator supplies the foreground readiness wait.
  func prepareAndWait(
    routineGroupLocalID: UUID,
    routineLocalIDs: [UUID]
  ) async -> RoutineTTSForegroundPreparationStatus {
    prepare(
      routineGroupLocalID: routineGroupLocalID,
      routineLocalIDs: routineLocalIDs
    )
    return .prepared
  }
}
