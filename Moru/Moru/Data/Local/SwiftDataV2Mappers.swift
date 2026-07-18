//
//  SwiftDataV2Mappers.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import Foundation

nonisolated enum PersistenceV2MappingError: Error, Equatable, LocalizedError {
  case unknownRawValue(field: String, rawValue: String)
  case invalidValue(field: String)
  case observationIdentityConflict(occurrenceID: String)
  case terminalObservationMissing
  case terminalObservationMismatch

  var errorDescription: String? {
    switch self {
    case .unknownRawValue(let field, let rawValue):
      return "Unknown raw value '\(rawValue)' in \(field)."
    case .invalidValue(let field):
      return "Invalid value in \(field)."
    case .observationIdentityConflict(let occurrenceID):
      return "Conflicting observation identity for \(occurrenceID)."
    case .terminalObservationMissing:
      return "A terminal root requires its immutable observation."
    case .terminalObservationMismatch:
      return "The terminal root does not match its immutable observation."
    }
  }
}

nonisolated enum SwiftDataV2Mapper {
  static func makePersistedObservation(
    from snapshot: ScheduledAlarmStartObservationSnapshot
  ) throws -> PersistedScheduledAlarmStartObservation {
    try validate(snapshot)
    return PersistedScheduledAlarmStartObservation(
      id: snapshot.id,
      occurrenceID: snapshot.occurrenceID,
      rootOccurrenceID: snapshot.rootOccurrenceID,
      parentOccurrenceID: snapshot.parentOccurrenceID,
      routineID: snapshot.routineID,
      scheduleID: snapshot.scheduleID,
      actionObservedAt: snapshot.actionObservedAt,
      scheduledFireAt: snapshot.scheduledFireAt,
      resetGeneration: snapshot.resetGeneration,
      sourceRawValue: snapshot.source.rawValue,
      immutableFingerprint: snapshot.immutableFingerprint,
      timeZoneIdentifier: snapshot.timeZoneIdentifier,
      utcOffsetSeconds: snapshot.utcOffsetSeconds,
      localGregorianDayKey: snapshot.localGregorianDayKey,
      localGregorianDayOrdinal: snapshot.localGregorianDayOrdinal,
      localMinute: snapshot.localMinute,
      receivedAt: snapshot.receivedAt
    )
  }

  static func makeObservationSnapshot(
    from persisted: PersistedScheduledAlarmStartObservation
  ) throws -> ScheduledAlarmStartObservationSnapshot {
    guard let source = ScheduledAlarmObservationSource(rawValue: persisted.sourceRawValue) else {
      throw PersistenceV2MappingError.unknownRawValue(
        field: "PersistedScheduledAlarmStartObservation.sourceRawValue",
        rawValue: persisted.sourceRawValue
      )
    }

    let snapshot = ScheduledAlarmStartObservationSnapshot(
      id: persisted.id,
      occurrenceID: persisted.occurrenceID,
      rootOccurrenceID: persisted.rootOccurrenceID,
      parentOccurrenceID: persisted.parentOccurrenceID,
      routineID: persisted.routineID,
      scheduleID: persisted.scheduleID,
      actionObservedAt: persisted.actionObservedAt,
      scheduledFireAt: persisted.scheduledFireAt,
      resetGeneration: persisted.resetGeneration,
      source: source,
      immutableFingerprint: persisted.immutableFingerprint,
      timeZoneIdentifier: persisted.timeZoneIdentifier,
      utcOffsetSeconds: persisted.utcOffsetSeconds,
      localGregorianDayKey: persisted.localGregorianDayKey,
      localGregorianDayOrdinal: persisted.localGregorianDayOrdinal,
      localMinute: persisted.localMinute,
      receivedAt: persisted.receivedAt
    )
    try validate(snapshot)
    return snapshot
  }

  static func validate(
    observation candidate: ScheduledAlarmStartObservationSnapshot,
    against existing: ScheduledAlarmStartObservationSnapshot
  ) throws {
    try validate(candidate)
    try validate(existing)

    guard candidate.occurrenceID != existing.occurrenceID
      || (candidate.immutableFingerprint == existing.immutableFingerprint
        && candidate.resetGeneration == existing.resetGeneration) else {
      throw PersistenceV2MappingError.observationIdentityConflict(
        occurrenceID: candidate.occurrenceID
      )
    }
  }

  static func makePersistedWeatherSnapshot(
    from snapshot: HomeWeatherSnapshot,
    now: Date
  ) throws -> PersistedHomeWeatherSnapshot {
    try validate(snapshot, now: now)
    return PersistedHomeWeatherSnapshot(
      id: snapshot.id,
      conditionRawValue: snapshot.condition.rawValue,
      temperatureCelsius: snapshot.temperatureCelsius,
      latitudeE4: snapshot.latitudeE4,
      longitudeE4: snapshot.longitudeE4,
      fetchedAt: snapshot.fetchedAt,
      fetchedTimeZoneIdentifier: snapshot.fetchedTimeZoneIdentifier,
      fetchedUTCOffsetSeconds: snapshot.fetchedUTCOffsetSeconds
    )
  }

  static func makeHomeWeatherSnapshot(
    from persisted: PersistedHomeWeatherSnapshot,
    now: Date
  ) throws -> HomeWeatherSnapshot {
    guard let condition = HomeWeatherCondition(rawValue: persisted.conditionRawValue) else {
      throw PersistenceV2MappingError.unknownRawValue(
        field: "PersistedHomeWeatherSnapshot.conditionRawValue",
        rawValue: persisted.conditionRawValue
      )
    }

    let snapshot = HomeWeatherSnapshot(
      id: persisted.id,
      condition: condition,
      temperatureCelsius: persisted.temperatureCelsius,
      latitudeE4: persisted.latitudeE4,
      longitudeE4: persisted.longitudeE4,
      fetchedAt: persisted.fetchedAt,
      fetchedTimeZoneIdentifier: persisted.fetchedTimeZoneIdentifier,
      fetchedUTCOffsetSeconds: persisted.fetchedUTCOffsetSeconds
    )
    try validate(snapshot, now: now)
    return snapshot
  }

  static func makePersistedLocalSettings(
    from snapshot: LocalSettingsSnapshot
  ) throws -> PersistedLocalSettings {
    try validate(snapshot)
    return PersistedLocalSettings(
      id: snapshot.id,
      profileID: snapshot.profileID,
      voiceMigrationStateRawValue: snapshot.voiceMigrationState.rawValue,
      voiceMigrationOriginalVoiceID: snapshot.originalVoiceID,
      voiceMigrationResolvedVoiceID: snapshot.resolvedVoiceID,
      voiceMigrationUpdatedAt: snapshot.migrationUpdatedAt,
      schemaMigrationMarkerRawValue: snapshot.schemaMigrationMarker.rawValue
    )
  }

  static func makeLocalSettingsSnapshot(
    from persisted: PersistedLocalSettings
  ) throws -> LocalSettingsSnapshot {
    guard let state = VoiceMigrationState(rawValue: persisted.voiceMigrationStateRawValue) else {
      throw PersistenceV2MappingError.unknownRawValue(
        field: "PersistedLocalSettings.voiceMigrationStateRawValue",
        rawValue: persisted.voiceMigrationStateRawValue
      )
    }
    guard let marker = SchemaMigrationMarker(
      rawValue: persisted.schemaMigrationMarkerRawValue
    ) else {
      throw PersistenceV2MappingError.unknownRawValue(
        field: "PersistedLocalSettings.schemaMigrationMarkerRawValue",
        rawValue: persisted.schemaMigrationMarkerRawValue
      )
    }

    let snapshot = LocalSettingsSnapshot(
      id: persisted.id,
      profileID: persisted.profileID,
      voiceMigrationState: state,
      originalVoiceID: persisted.voiceMigrationOriginalVoiceID,
      resolvedVoiceID: persisted.voiceMigrationResolvedVoiceID,
      migrationUpdatedAt: persisted.voiceMigrationUpdatedAt,
      schemaMigrationMarker: marker
    )
    try validate(snapshot)
    return snapshot
  }
  static func makeLocalSettingsSnapshot(
    from persisted: PersistedLocalSettings,
    profile: PersistedLocalProfile
  ) throws -> LocalSettingsSnapshot {
    let snapshot = try makeLocalSettingsSnapshot(from: persisted)
    try validate(snapshot, profileSelectedVoiceID: profile.selectedVoiceID)
    return snapshot
  }

  static func validate(
    _ snapshot: LocalSettingsSnapshot,
    profileSelectedVoiceID: String
  ) throws {
    try validate(snapshot)

    switch snapshot.voiceMigrationState {
    case .unresolved:
      return
    case .resolved:
      guard snapshot.resolvedVoiceID == profileSelectedVoiceID else {
        throw PersistenceV2MappingError.invalidValue(field: "resolved profile voice")
      }
    case .fallbackNoticePending, .fallbackNoticeAcknowledged:
      guard snapshot.resolvedVoiceID == profileSelectedVoiceID else {
        throw PersistenceV2MappingError.invalidValue(field: "fallback profile voice")
      }
    case .noFallbackNoticePending, .noFallbackNoticeAcknowledged, .corruptRecoveryPending:
      guard snapshot.originalVoiceID == profileSelectedVoiceID else {
        throw PersistenceV2MappingError.invalidValue(field: "no-fallback profile voice")
      }
    }
  }


  static func makePersistedRootChainState(
    from snapshot: AlarmRootChainStateSnapshot,
    terminalObservation: ScheduledAlarmStartObservationSnapshot? = nil
  ) throws -> PersistedAlarmRootChainState {
    try validate(snapshot, terminalObservation: terminalObservation)
    return PersistedAlarmRootChainState(
      id: snapshot.id,
      rootOccurrenceID: snapshot.rootOccurrenceID,
      routineID: snapshot.routineID,
      scheduleID: snapshot.scheduleID,
      resetGeneration: snapshot.resetGeneration,
      rootFingerprint: snapshot.rootFingerprint,
      earliestObservedOccurrenceID: snapshot.earliestObservedOccurrenceID,
      earliestObservedAt: snapshot.earliestObservedAt,
      latestObservedOccurrenceID: snapshot.latestObservedOccurrenceID,
      latestObservedAt: snapshot.latestObservedAt,
      terminalOccurrenceID: snapshot.terminalOccurrenceID,
      terminalAt: snapshot.terminalAt,
      stateRawValue: snapshot.state.rawValue,
      updatedAt: snapshot.updatedAt
    )
  }

  static func makeAlarmRootChainStateSnapshot(
    from persisted: PersistedAlarmRootChainState,
    terminalObservation: ScheduledAlarmStartObservationSnapshot? = nil
  ) throws -> AlarmRootChainStateSnapshot {
    guard let state = AlarmRootChainState(rawValue: persisted.stateRawValue) else {
      throw PersistenceV2MappingError.unknownRawValue(
        field: "PersistedAlarmRootChainState.stateRawValue",
        rawValue: persisted.stateRawValue
      )
    }

    let snapshot = AlarmRootChainStateSnapshot(
      id: persisted.id,
      rootOccurrenceID: persisted.rootOccurrenceID,
      routineID: persisted.routineID,
      scheduleID: persisted.scheduleID,
      resetGeneration: persisted.resetGeneration,
      rootFingerprint: persisted.rootFingerprint,
      earliestObservedOccurrenceID: persisted.earliestObservedOccurrenceID,
      earliestObservedAt: persisted.earliestObservedAt,
      latestObservedOccurrenceID: persisted.latestObservedOccurrenceID,
      latestObservedAt: persisted.latestObservedAt,
      terminalOccurrenceID: persisted.terminalOccurrenceID,
      terminalAt: persisted.terminalAt,
      state: state,
      updatedAt: persisted.updatedAt
    )
    try validate(snapshot, terminalObservation: terminalObservation)
    return snapshot
  }

  static func makePersistedAlarmPlatformState(
    from snapshot: AlarmPlatformSnapshot
  ) throws -> PersistedAlarmPlatformState {
    try validate(snapshot)
    return PersistedAlarmPlatformState(
      id: snapshot.id,
      scheduleID: snapshot.scheduleID,
      routineID: snapshot.routineID,
      desiredScheduleFingerprint: snapshot.desiredScheduleFingerprint,
      platformRequestID: snapshot.platformRequestID,
      stateRawValue: snapshot.state.rawValue,
      updatedAt: snapshot.updatedAt,
      lastErrorCode: snapshot.lastErrorCode
    )
  }

  static func makeAlarmPlatformSnapshot(
    from persisted: PersistedAlarmPlatformState
  ) throws -> AlarmPlatformSnapshot {
    guard let state = AlarmPlatformState(rawValue: persisted.stateRawValue) else {
      throw PersistenceV2MappingError.unknownRawValue(
        field: "PersistedAlarmPlatformState.stateRawValue",
        rawValue: persisted.stateRawValue
      )
    }

    let snapshot = AlarmPlatformSnapshot(
      id: persisted.id,
      scheduleID: persisted.scheduleID,
      routineID: persisted.routineID,
      desiredScheduleFingerprint: persisted.desiredScheduleFingerprint,
      platformRequestID: persisted.platformRequestID,
      state: state,
      updatedAt: persisted.updatedAt,
      lastErrorCode: persisted.lastErrorCode
    )
    try validate(snapshot)
    return snapshot
  }

  private static func validate(_ snapshot: ScheduledAlarmStartObservationSnapshot) throws {
    guard !snapshot.occurrenceID.isEmpty else {
      throw PersistenceV2MappingError.invalidValue(field: "occurrenceID")
    }
    guard !snapshot.rootOccurrenceID.isEmpty else {
      throw PersistenceV2MappingError.invalidValue(field: "rootOccurrenceID")
    }
    guard snapshot.parentOccurrenceID?.isEmpty != true else {
      throw PersistenceV2MappingError.invalidValue(field: "parentOccurrenceID")
    }
    guard snapshot.resetGeneration > 0 else {
      throw PersistenceV2MappingError.invalidValue(field: "resetGeneration")
    }
    guard snapshot.source == .alarmKitOccurrenceActionV1 else {
      throw PersistenceV2MappingError.invalidValue(field: "source")
    }
    guard isCanonicalSHA256Hex(snapshot.immutableFingerprint) else {
      throw PersistenceV2MappingError.invalidValue(field: "immutableFingerprint")
    }
    guard isIANAZoneIdentifier(snapshot.timeZoneIdentifier) else {
      throw PersistenceV2MappingError.invalidValue(field: "timeZoneIdentifier")
    }
    guard (-86_400...86_400).contains(snapshot.utcOffsetSeconds) else {
      throw PersistenceV2MappingError.invalidValue(field: "utcOffsetSeconds")
    }
    guard isGregorianDayKey(snapshot.localGregorianDayKey) else {
      throw PersistenceV2MappingError.invalidValue(field: "localGregorianDayKey")
    }
    guard (1...366).contains(snapshot.localGregorianDayOrdinal) else {
      throw PersistenceV2MappingError.invalidValue(field: "localGregorianDayOrdinal")
    }
    guard (0...1_439).contains(snapshot.localMinute) else {
      throw PersistenceV2MappingError.invalidValue(field: "localMinute")
    }
  }

  private static func validate(_ snapshot: HomeWeatherSnapshot, now: Date) throws {
    guard snapshot.temperatureCelsius.isFinite else {
      throw PersistenceV2MappingError.invalidValue(field: "temperatureCelsius")
    }
    guard (-900_000...900_000).contains(snapshot.latitudeE4) else {
      throw PersistenceV2MappingError.invalidValue(field: "latitudeE4")
    }
    guard (-1_800_000...1_800_000).contains(snapshot.longitudeE4) else {
      throw PersistenceV2MappingError.invalidValue(field: "longitudeE4")
    }
    guard isIANAZoneIdentifier(snapshot.fetchedTimeZoneIdentifier) else {
      throw PersistenceV2MappingError.invalidValue(field: "fetchedTimeZoneIdentifier")
    }
    guard (-86_400...86_400).contains(snapshot.fetchedUTCOffsetSeconds) else {
      throw PersistenceV2MappingError.invalidValue(field: "fetchedUTCOffsetSeconds")
    }
    guard snapshot.fetchedAt <= now.addingTimeInterval(300) else {
      throw PersistenceV2MappingError.invalidValue(field: "fetchedAt")
    }
  }

  private static func validate(_ snapshot: LocalSettingsSnapshot) throws {
    guard snapshot.id == snapshot.profileID else {
      throw PersistenceV2MappingError.invalidValue(field: "id/profileID")
    }

    switch snapshot.voiceMigrationState {
    case .unresolved:
      guard snapshot.originalVoiceID == nil,
            snapshot.resolvedVoiceID == nil,
            snapshot.migrationUpdatedAt == nil,
            snapshot.schemaMigrationMarker == .v2Unresolved else {
        throw PersistenceV2MappingError.invalidValue(field: "unresolved settings")
      }
    case .resolved:
      guard snapshot.originalVoiceID == nil,
            isNonEmpty(snapshot.resolvedVoiceID),
            snapshot.migrationUpdatedAt != nil,
            snapshot.schemaMigrationMarker == .v2Resolved else {
        throw PersistenceV2MappingError.invalidValue(field: "resolved settings")
      }
    case .fallbackNoticePending, .fallbackNoticeAcknowledged:
      guard isNonEmpty(snapshot.originalVoiceID),
            isNonEmpty(snapshot.resolvedVoiceID),
            snapshot.migrationUpdatedAt != nil,
            snapshot.schemaMigrationMarker == .v2Resolved else {
        throw PersistenceV2MappingError.invalidValue(field: "fallback settings")
      }
    case .noFallbackNoticePending, .noFallbackNoticeAcknowledged, .corruptRecoveryPending:
      guard isNonEmpty(snapshot.originalVoiceID),
            snapshot.resolvedVoiceID == nil,
            snapshot.migrationUpdatedAt != nil,
            snapshot.schemaMigrationMarker == .v2Unresolved else {
        throw PersistenceV2MappingError.invalidValue(field: "no-fallback settings")
      }
    }
  }

  private static func validate(
    _ snapshot: AlarmRootChainStateSnapshot,
    terminalObservation: ScheduledAlarmStartObservationSnapshot?
  ) throws {
    guard !snapshot.rootOccurrenceID.isEmpty else {
      throw PersistenceV2MappingError.invalidValue(field: "rootOccurrenceID")
    }
    guard snapshot.resetGeneration > 0 else {
      throw PersistenceV2MappingError.invalidValue(field: "resetGeneration")
    }
    guard isCanonicalSHA256Hex(snapshot.rootFingerprint) else {
      throw PersistenceV2MappingError.invalidValue(field: "rootFingerprint")
    }
    guard paired(snapshot.earliestObservedOccurrenceID, snapshot.earliestObservedAt),
          paired(snapshot.latestObservedOccurrenceID, snapshot.latestObservedAt) else {
      throw PersistenceV2MappingError.invalidValue(field: "root observation bounds")
    }
    guard let earliestAt = snapshot.earliestObservedAt,
          let latestAt = snapshot.latestObservedAt,
          earliestAt <= latestAt else {
      throw PersistenceV2MappingError.invalidValue(field: "root observation ordering")
    }

    switch snapshot.state {
    case .open, .lineageConflict:
      guard snapshot.terminalOccurrenceID == nil, snapshot.terminalAt == nil else {
        throw PersistenceV2MappingError.invalidValue(field: "terminal observation")
      }
    case .terminal:
      guard let terminalOccurrenceID = snapshot.terminalOccurrenceID,
            let terminalAt = snapshot.terminalAt,
            terminalOccurrenceID == snapshot.latestObservedOccurrenceID,
            terminalAt == snapshot.latestObservedAt else {
        throw PersistenceV2MappingError.invalidValue(field: "terminal observation")
      }
      guard let terminalObservation else {
        throw PersistenceV2MappingError.terminalObservationMissing
      }
      try validate(terminalObservation)
      guard terminalObservation.occurrenceID == terminalOccurrenceID,
            terminalObservation.actionObservedAt == terminalAt,
            terminalObservation.rootOccurrenceID == snapshot.rootOccurrenceID,
            terminalObservation.routineID == snapshot.routineID,
            terminalObservation.scheduleID == snapshot.scheduleID,
            terminalObservation.resetGeneration == snapshot.resetGeneration else {
        throw PersistenceV2MappingError.terminalObservationMismatch
      }
    }
  }

  private static func validate(_ snapshot: AlarmPlatformSnapshot) throws {
    guard isCanonicalSHA256Hex(snapshot.desiredScheduleFingerprint) else {
      throw PersistenceV2MappingError.invalidValue(field: "desiredScheduleFingerprint")
    }
    guard snapshot.lastErrorCode?.isEmpty != true else {
      throw PersistenceV2MappingError.invalidValue(field: "lastErrorCode")
    }
  }

  private static func paired(_ identifier: String?, _ date: Date?) -> Bool {
    (identifier == nil) == (date == nil) && identifier?.isEmpty != true
  }

  private static func isNonEmpty(_ value: String?) -> Bool {
    guard let value else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func isIANAZoneIdentifier(_ identifier: String) -> Bool {
    guard identifier.contains("/"), TimeZone(identifier: identifier) != nil else {
      return false
    }
    return true
  }

  private static func isGregorianDayKey(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else {
      return false
    }
    guard let year = Int(value.prefix(4)),
          let month = Int(value.dropFirst(5).prefix(2)),
          let day = Int(value.suffix(2)) else {
      return false
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(year: year, month: month, day: day)
    guard let date = calendar.date(from: components) else { return false }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    return resolved.year == year && resolved.month == month && resolved.day == day
  }

  private static func isCanonicalSHA256Hex(_ value: String) -> Bool {
    guard value.utf8.count == 64 else { return false }
    return value.utf8.allSatisfy { byte in
      (48...57).contains(byte) || (97...102).contains(byte)
    }
  }
}
