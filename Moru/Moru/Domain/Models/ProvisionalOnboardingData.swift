//
//  ProvisionalOnboardingData.swift
//  Moru
//

import Foundation

/// Durable provenance for the exact profile and routines created by one
/// successful local onboarding completion.
nonisolated struct ProvisionalOnboardingDataMarker:
  Equatable,
  Sendable {
  let generationID: UUID
  let profileID: UUID
  let routineIDs: [UUID]
  let createdAt: Date
}

/// Only the first two states may initialize the local store from the server.
/// Existing installations have no marker and therefore classify as
/// `established` without a migration that guesses provenance.
nonisolated enum ServerRoutineRestorationLocalDataState:
  Equatable,
  Sendable {
  case empty
  case provisional(ProvisionalOnboardingDataMarker)
  case established

  var restorationSource: ServerRoutineRestorationSource? {
    switch self {
    case .empty:
      .empty
    case .provisional(let marker):
      .provisional(generationID: marker.generationID)
    case .established:
      nil
    }
  }
}

nonisolated enum ServerRoutineRestorationSource:
  Equatable,
  Sendable {
  case empty
  case provisional(generationID: UUID)
}
