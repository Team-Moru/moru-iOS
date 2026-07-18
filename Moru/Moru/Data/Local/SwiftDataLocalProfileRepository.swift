//
//  SwiftDataLocalProfileRepository.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

enum LocalSettingsRepositoryError: Error, Equatable, LocalizedError {
  case profileNotFound(UUID)
  case settingsNotFound(UUID)
  case unavailableVoiceSelection(String)
  case acknowledgementNotPending(VoiceMigrationState)

  var errorDescription: String? {
    switch self {
    case .profileNotFound:
      return "Local profile was not found."
    case .settingsNotFound:
      return "Local settings were not found."
    case .unavailableVoiceSelection(let voiceID):
      return "Voice '\(voiceID)' is not available."
    case .acknowledgementNotPending(let state):
      return "Voice migration notice is not pending: \(state.rawValue)."
    }
  }
}

nonisolated final class SwiftDataLocalProfileRepository:
  LocalProfileRepository,
  LocalSettingsRepository,
  @unchecked Sendable {
  private let modelContext: ModelContext
  private let availabilityProbe: any VoiceAvailabilityProbing
  private let now: @Sendable () -> Date

  init(
    modelContext: ModelContext,
    availabilityProbe: any VoiceAvailabilityProbing = UnavailableVoiceAvailabilityProbe(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.modelContext = modelContext
    self.availabilityProbe = availabilityProbe
    self.now = now
  }

  @MainActor
  func fetchProfile() throws -> LocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).first.map(SwiftDataMapper.makeDomainProfile)
  }

  @MainActor
  func loadOrCreateDefaultProfile() throws -> LocalProfile {
    if let profile = try fetchProfile() {
      return profile
    }

    let profile = LocalProfile()
    try saveProfile(profile)
    return profile
  }

  @MainActor
  func saveProfile(_ profile: LocalProfile) throws {
    if let persisted = try persistedProfile(id: profile.id) {
      SwiftDataMapper.update(persisted, with: profile)
    } else {
      modelContext.insert(SwiftDataMapper.makePersistedProfile(from: profile))
    }

    try modelContext.save()
  }

  @MainActor
  func deleteProfile() throws {
    let profiles = try modelContext.fetch(FetchDescriptor<PersistedLocalProfile>())
    let settings = try modelContext.fetch(FetchDescriptor<PersistedLocalSettings>())
    profiles.forEach { modelContext.delete($0) }
    settings.forEach { modelContext.delete($0) }
    try modelContext.save()
  }

  @MainActor
  func fetchSettings(profileID: UUID) throws -> LocalSettingsSnapshot? {
    guard let profile = try persistedProfile(id: profileID) else {
      try deleteOrphanedSettings(profileID: profileID)
      return nil
    }

    let prepared = try prepareSettings(for: profile)
    if prepared.didMutate {
      try modelContext.save()
    }

    return try prepared.settings.map(SwiftDataMapper.makeDomainSettings)
  }

  @MainActor
  func resolveVoiceSettings(profileID: UUID) throws -> LocalSettingsSnapshot {
    let profile = try requirePersistedProfile(id: profileID)
    var prepared = try prepareSettings(for: profile)

    if prepared.settings == nil {
      let settings = PersistedLocalSettings(id: profile.id, profileID: profile.id)
      modelContext.insert(settings)
      prepared = PreparedSettings(settings: settings, didMutate: true, wasRepaired: false)
    }

    let settings = try requirePreparedSettings(prepared, profileID: profileID)
    if prepared.wasRepaired {
      try modelContext.save()
      return try SwiftDataMapper.makeDomainSettings(from: settings)
    }

    let snapshot = try SwiftDataMapper.makeDomainSettings(from: settings)
    var didMutate = prepared.didMutate

    switch snapshot.voiceMigrationState {
    case .resolved, .fallbackNoticePending, .fallbackNoticeAcknowledged:
      break
    case .unresolved:
      let originalVoiceID = profile.selectedVoiceID
      if let selectedVoice = VoiceProfile.catalogueVoice(id: originalVoiceID),
         availabilityProbe.isAvailable(selectedVoice) {
        applyResolvedSelection(to: settings, voiceID: selectedVoice.id)
      } else {
        applyFallback(
          to: settings,
          profile: profile,
          originalVoiceID: originalVoiceID,
          skippingVoiceID: VoiceProfile.catalogueVoice(id: originalVoiceID)?.id
        )
      }
      didMutate = true
    case .noFallbackNoticePending, .noFallbackNoticeAcknowledged, .corruptRecoveryPending:
      guard let originalVoiceID = snapshot.originalVoiceID else {
        applyCorruptRecovery(to: settings, profile: profile)
        didMutate = true
        break
      }

      applyFallback(to: settings, profile: profile, originalVoiceID: originalVoiceID)
      didMutate = true
    }

    if didMutate {
      try modelContext.save()
    }

    return try SwiftDataMapper.makeDomainSettings(from: settings)
  }

  @MainActor
  func acknowledgeVoiceNotice(profileID: UUID) throws {
    let profile = try requirePersistedProfile(id: profileID)
    let prepared = try prepareSettings(for: profile)
    guard let settings = prepared.settings else {
      throw LocalSettingsRepositoryError.settingsNotFound(profileID)
    }

    let snapshot = try SwiftDataMapper.makeDomainSettings(from: settings)
    switch snapshot.voiceMigrationState {
    case .fallbackNoticePending:
      settings.voiceMigrationStateRawValue = VoiceMigrationState
        .fallbackNoticeAcknowledged.rawValue
    case .noFallbackNoticePending:
      settings.voiceMigrationStateRawValue = VoiceMigrationState
        .noFallbackNoticeAcknowledged.rawValue
    case .unresolved,
         .resolved,
         .fallbackNoticeAcknowledged,
         .noFallbackNoticeAcknowledged,
         .corruptRecoveryPending:
      if prepared.didMutate {
        try modelContext.save()
      }
      throw LocalSettingsRepositoryError.acknowledgementNotPending(
        snapshot.voiceMigrationState
      )
    }

    try modelContext.save()
  }

  @MainActor
  func selectVoice(profileID: UUID, voiceID: String) throws -> LocalSettingsSnapshot {
    guard case let .available(voice) = VoiceSelection(rawID: voiceID),
          availabilityProbe.isAvailable(voice) else {
      throw LocalSettingsRepositoryError.unavailableVoiceSelection(voiceID)
    }

    let profile = try requirePersistedProfile(id: profileID)
    var prepared = try prepareSettings(for: profile)
    let settings: PersistedLocalSettings

    if let existing = prepared.settings {
      settings = existing
    } else {
      let created = PersistedLocalSettings(id: profile.id, profileID: profile.id)
      modelContext.insert(created)
      settings = created
      prepared = PreparedSettings(settings: created, didMutate: true, wasRepaired: false)
    }

    let selectedAt = now()
    profile.selectedVoiceID = voice.id
    profile.updatedAt = selectedAt
    apply(
      state: .resolved,
      originalVoiceID: nil,
      resolvedVoiceID: voice.id,
      updatedAt: selectedAt,
      marker: .v2Resolved,
      to: settings
    )
    try modelContext.save()

    return try SwiftDataMapper.makeDomainSettings(from: settings)
  }

  @MainActor
  private func persistedProfile(id: UUID) throws -> PersistedLocalProfile? {
    try modelContext.fetch(FetchDescriptor<PersistedLocalProfile>()).first { $0.id == id }
  }

  @MainActor
  private func requirePersistedProfile(id: UUID) throws -> PersistedLocalProfile {
    guard let profile = try persistedProfile(id: id) else {
      throw LocalSettingsRepositoryError.profileNotFound(id)
    }

    return profile
  }

  @MainActor
  private func deleteOrphanedSettings(profileID: UUID) throws {
    let settings = try modelContext.fetch(FetchDescriptor<PersistedLocalSettings>())
    let orphaned = settings.filter { $0.profileID == profileID }
    orphaned.forEach { modelContext.delete($0) }

    if !orphaned.isEmpty {
      try modelContext.save()
    }
  }

  @MainActor
  private func prepareSettings(for profile: PersistedLocalProfile) throws -> PreparedSettings {
    let allSettings = try modelContext.fetch(FetchDescriptor<PersistedLocalSettings>())
    let matchingSettings = allSettings.filter { $0.profileID == profile.id }

    guard let winner = winningSettings(from: matchingSettings) else {
      return PreparedSettings(settings: nil, didMutate: false, wasRepaired: false)
    }

    let duplicates = matchingSettings.filter { $0 !== winner }
    duplicates.forEach { modelContext.delete($0) }

    guard winner.id == profile.id else {
      modelContext.delete(winner)
      let replacement = makeCorruptRecoverySettings(for: profile)
      modelContext.insert(replacement)
      return PreparedSettings(settings: replacement, didMutate: true, wasRepaired: true)
    }

    guard isValid(winner, for: profile) else {
      applyCorruptRecovery(to: winner, profile: profile)
      return PreparedSettings(settings: winner, didMutate: true, wasRepaired: true)
    }

    return PreparedSettings(
      settings: winner,
      didMutate: !duplicates.isEmpty,
      wasRepaired: false
    )
  }

  @MainActor
  private func requirePreparedSettings(
    _ prepared: PreparedSettings,
    profileID: UUID
  ) throws -> PersistedLocalSettings {
    guard let settings = prepared.settings else {
      throw LocalSettingsRepositoryError.settingsNotFound(profileID)
    }

    return settings
  }

  @MainActor
  private func winningSettings(
    from settings: [PersistedLocalSettings]
  ) -> PersistedLocalSettings? {
    settings.sorted { left, right in
      let leftDate = left.voiceMigrationUpdatedAt ?? .distantPast
      let rightDate = right.voiceMigrationUpdatedAt ?? .distantPast

      if leftDate != rightDate {
        return leftDate > rightDate
      }

      return canonicalUUID(right.id).utf8.lexicographicallyPrecedes(
        canonicalUUID(left.id).utf8
      )
    }.first
  }

  @MainActor
  private func canonicalUUID(_ id: UUID) -> String {
    id.uuidString.lowercased()
  }

  @MainActor
  private func isValid(
    _ settings: PersistedLocalSettings,
    for profile: PersistedLocalProfile
  ) -> Bool {
    guard let snapshot = try? SwiftDataMapper.makeDomainSettings(from: settings),
          snapshot.id == profile.id,
          snapshot.profileID == profile.id else {
      return false
    }

    switch snapshot.voiceMigrationState {
    case .unresolved:
      return snapshot.originalVoiceID == nil
        && snapshot.resolvedVoiceID == nil
        && snapshot.migrationUpdatedAt == nil
        && snapshot.schemaMigrationMarker == .v2Unresolved
    case .resolved:
      return snapshot.originalVoiceID == nil
        && snapshot.resolvedVoiceID == profile.selectedVoiceID
        && VoiceProfile.catalogueVoice(id: profile.selectedVoiceID) != nil
        && snapshot.migrationUpdatedAt != nil
        && snapshot.schemaMigrationMarker == .v2Resolved
    case .fallbackNoticePending, .fallbackNoticeAcknowledged:
      return snapshot.originalVoiceID != nil
        && snapshot.originalVoiceID != snapshot.resolvedVoiceID
        && snapshot.resolvedVoiceID == profile.selectedVoiceID
        && VoiceProfile.catalogueVoice(id: profile.selectedVoiceID) != nil
        && snapshot.migrationUpdatedAt != nil
        && snapshot.schemaMigrationMarker == .v2Resolved
    case .noFallbackNoticePending, .noFallbackNoticeAcknowledged:
      return snapshot.originalVoiceID == profile.selectedVoiceID
        && snapshot.resolvedVoiceID == nil
        && snapshot.migrationUpdatedAt != nil
        && snapshot.schemaMigrationMarker == .v2Unresolved
    case .corruptRecoveryPending:
      return snapshot.originalVoiceID == profile.selectedVoiceID
        && snapshot.resolvedVoiceID == nil
        && snapshot.migrationUpdatedAt != nil
        && snapshot.schemaMigrationMarker == .v2Unresolved
    }
  }

  @MainActor
  private func makeCorruptRecoverySettings(
    for profile: PersistedLocalProfile
  ) -> PersistedLocalSettings {
    PersistedLocalSettings(
      id: profile.id,
      profileID: profile.id,
      voiceMigrationStateRawValue: VoiceMigrationState.corruptRecoveryPending.rawValue,
      voiceMigrationOriginalVoiceID: profile.selectedVoiceID,
      voiceMigrationResolvedVoiceID: nil,
      voiceMigrationUpdatedAt: now(),
      schemaMigrationMarkerRawValue: SchemaMigrationMarker.v2Unresolved.rawValue
    )
  }

  @MainActor
  private func applyCorruptRecovery(
    to settings: PersistedLocalSettings,
    profile: PersistedLocalProfile
  ) {
    apply(
      state: .corruptRecoveryPending,
      originalVoiceID: profile.selectedVoiceID,
      resolvedVoiceID: nil,
      updatedAt: now(),
      marker: .v2Unresolved,
      to: settings
    )
  }

  @MainActor
  private func applyResolvedSelection(
    to settings: PersistedLocalSettings,
    voiceID: String
  ) {
    apply(
      state: .resolved,
      originalVoiceID: nil,
      resolvedVoiceID: voiceID,
      updatedAt: now(),
      marker: .v2Resolved,
      to: settings
    )
  }

  @MainActor
  private func applyFallback(
    to settings: PersistedLocalSettings,
    profile: PersistedLocalProfile,
    originalVoiceID: String,
    skippingVoiceID: String? = nil
  ) {
    let migratedAt = now()
    let fallback = VoiceProfile.localVoices.first { voice in
      voice.id != skippingVoiceID && availabilityProbe.isAvailable(voice)
    }

    if let fallback {
      profile.selectedVoiceID = fallback.id
      profile.updatedAt = migratedAt
      apply(
        state: .fallbackNoticePending,
        originalVoiceID: originalVoiceID,
        resolvedVoiceID: fallback.id,
        updatedAt: migratedAt,
        marker: .v2Resolved,
        to: settings
      )
    } else {
      apply(
        state: .noFallbackNoticePending,
        originalVoiceID: originalVoiceID,
        resolvedVoiceID: nil,
        updatedAt: migratedAt,
        marker: .v2Unresolved,
        to: settings
      )
    }
  }

  @MainActor
  private func apply(
    state: VoiceMigrationState,
    originalVoiceID: String?,
    resolvedVoiceID: String?,
    updatedAt: Date?,
    marker: SchemaMigrationMarker,
    to settings: PersistedLocalSettings
  ) {
    settings.voiceMigrationStateRawValue = state.rawValue
    settings.voiceMigrationOriginalVoiceID = originalVoiceID
    settings.voiceMigrationResolvedVoiceID = resolvedVoiceID
    settings.voiceMigrationUpdatedAt = updatedAt
    settings.schemaMigrationMarkerRawValue = marker.rawValue
  }
}

private struct PreparedSettings {
  let settings: PersistedLocalSettings?
  let didMutate: Bool
  let wasRepaired: Bool
}
