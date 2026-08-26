//
//  ProvisionalOnboardingDataMarker.swift
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
