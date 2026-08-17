//
//  SwiftDataProvisionalOnboardingDataStore.swift
//  Moru
//

import Foundation
import SwiftData

/// Owns the singleton provenance marker. A marker is valid only while the
/// complete current profile/routine projection exactly matches its snapshots.
/// Any uncertainty fails closed to established local data.
@MainActor
final class SwiftDataProvisionalOnboardingDataStore {
  private let modelContext: ModelContext
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    decoder = JSONDecoder()
  }

  func marker() throws -> ProvisionalOnboardingDataMarker? {
    let markers = try persistedMarkers()
    guard markers.count == 1 else { return nil }
    return makeMarker(from: markers[0])
  }

  func localDataState() throws -> ServerRoutineRestorationLocalDataState {
    let profiles = try modelContext.fetch(
      FetchDescriptor<PersistedLocalProfile>()
    )
    let persistedRoutines = try modelContext.fetch(
      FetchDescriptor<PersistedRoutine>()
    )

    if profiles.isEmpty, persistedRoutines.isEmpty {
      return .empty
    }

    let markers = try persistedMarkers()
    guard profiles.count == 1,
          markers.count == 1,
          let marker = makeMarker(from: markers[0]),
          !marker.routineIDs.isEmpty,
          profiles[0].id == marker.profileID,
          Set(persistedRoutines.map(\.id)) == Set(marker.routineIDs),
          let expectedProfile = try? decoder.decode(
            LocalProfile.self,
            from: markers[0].profileSnapshot
          ),
          let expectedRoutines = try? decoder.decode(
            [Routine].self,
            from: markers[0].routineSnapshots
          ),
          expectedProfile.id == marker.profileID,
          expectedRoutines.count == marker.routineIDs.count,
          Set(expectedRoutines.map(\.id)) == Set(marker.routineIDs),
          SwiftDataMapper.makeDomainProfile(from: profiles[0])
            == expectedProfile,
          let currentRoutines = try? persistedRoutines.map(
            SwiftDataMapper.makeDomainRoutine
          ),
          Dictionary(uniqueKeysWithValues: currentRoutines.map {
            ($0.id, $0)
          }) == Dictionary(uniqueKeysWithValues: expectedRoutines.map {
            ($0.id, $0)
          }) else {
      return .established
    }

    return .provisional(marker)
  }

  /// Must be called in the same transaction that creates the onboarding
  /// profile and routine.
  @discardableResult
  func stageRecord(
    profile: LocalProfile,
    routines: [Routine],
    at date: Date
  ) throws -> ProvisionalOnboardingDataMarker {
    precondition(!routines.isEmpty)
    try stageInvalidate()

    let generationID = UUID()
    let sortedRoutines = routines.sorted {
      $0.id.uuidString < $1.id.uuidString
    }
    let routineIDs = sortedRoutines.map(\.id)
    modelContext.insert(
      PersistedProvisionalOnboardingMarker(
        id: generationID,
        generationID: generationID,
        profileID: profile.id,
        routineIDsRawValue: Self.encodeRoutineIDs(routineIDs),
        profileSnapshot: try encoder.encode(profile),
        routineSnapshots: try encoder.encode(sortedRoutines),
        createdAt: date
      )
    )

    return ProvisionalOnboardingDataMarker(
      generationID: generationID,
      profileID: profile.id,
      routineIDs: routineIDs,
      createdAt: date
    )
  }

  /// Local profile/routine CRUD calls this before committing a user change.
  /// Removing provenance never removes user data.
  func stageInvalidate() throws {
    try persistedMarkers().forEach(modelContext.delete)
  }

  /// Atomically removes only a still-valid provisional projection. The full
  /// snapshot and every explicit ID are revalidated immediately before delete.
  func stageDeleteValidatedProvisionalData(
    generationID: UUID
  ) throws -> Bool {
    guard case .provisional(let marker) = try localDataState(),
          marker.generationID == generationID else {
      return false
    }

    let profiles = try modelContext.fetch(
      FetchDescriptor<PersistedLocalProfile>()
    )
    let routines = try modelContext.fetch(
      FetchDescriptor<PersistedRoutine>()
    )
    guard profiles.count == 1,
          profiles[0].id == marker.profileID,
          Set(routines.map(\.id)) == Set(marker.routineIDs) else {
      return false
    }

    modelContext.delete(profiles[0])
    routines.forEach(modelContext.delete)
    try stageInvalidate()
    return true
  }

  /// A server-incomplete decision promotes the local onboarding projection to
  /// established before login backfill is released. A missing marker means a
  /// local edit already established the data. A different generation remains
  /// unresolved and is never silently cleared.
  func finalizeAsEstablished(
    expectedGenerationID: UUID
  ) throws -> Bool {
    do {
      let markers = try persistedMarkers()
      if markers.isEmpty {
        return true
      }
      guard markers.count == 1,
            markers[0].generationID == expectedGenerationID else {
        return false
      }
      modelContext.delete(markers[0])
      try modelContext.save()
      return true
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func persistedMarkers()
    throws -> [PersistedProvisionalOnboardingMarker] {
    try modelContext.fetch(
      FetchDescriptor<PersistedProvisionalOnboardingMarker>()
    )
  }

  private func makeMarker(
    from persisted: PersistedProvisionalOnboardingMarker
  ) -> ProvisionalOnboardingDataMarker? {
    guard persisted.id == persisted.generationID,
          let routineIDs = Self.decodeRoutineIDs(
            persisted.routineIDsRawValue
          ),
          !routineIDs.isEmpty else {
      return nil
    }
    return ProvisionalOnboardingDataMarker(
      generationID: persisted.generationID,
      profileID: persisted.profileID,
      routineIDs: routineIDs,
      createdAt: persisted.createdAt
    )
  }

  private static func encodeRoutineIDs(_ routineIDs: [UUID]) -> String {
    routineIDs
      .map(\.uuidString)
      .sorted()
      .joined(separator: ",")
  }

  private static func decodeRoutineIDs(_ rawValue: String) -> [UUID]? {
    let components = rawValue.split(
      separator: ",",
      omittingEmptySubsequences: false
    )
    guard !components.isEmpty,
          components.allSatisfy({ !$0.isEmpty }) else {
      return nil
    }
    let routineIDs = components.compactMap {
      UUID(uuidString: String($0))
    }
    guard routineIDs.count == components.count,
          Set(routineIDs).count == routineIDs.count else {
      return nil
    }
    return routineIDs.sorted { $0.uuidString < $1.uuidString }
  }
}
