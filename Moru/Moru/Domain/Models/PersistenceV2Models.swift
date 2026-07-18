//
//  PersistenceV2Models.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import Foundation

nonisolated enum ScheduledAlarmObservationSource: String, Sendable, Equatable, CaseIterable {
  case alarmKitOccurrenceActionV1
}

nonisolated enum HomeWeatherCondition: String, Sendable, Equatable, CaseIterable {
  case clear
  case cloudy
  case rain
  case snow
  case wind
  case fog
  case thunderstorm
  case mixed
  case other
}

nonisolated enum AlarmRootChainState: String, Sendable, Equatable, CaseIterable {
  case open
  case terminal
  case lineageConflict
}

nonisolated enum AlarmPlatformState: String, Sendable, Equatable, CaseIterable {
  case configured
  case cancellationPending
  case cancelled
  case repairRequired
}

nonisolated struct ScheduledAlarmStartObservationSnapshot: Sendable, Equatable {
  let id: UUID
  let occurrenceID: String
  let rootOccurrenceID: String
  let parentOccurrenceID: String?
  let routineID: UUID
  let scheduleID: UUID
  let actionObservedAt: Date
  let scheduledFireAt: Date
  let resetGeneration: UInt64
  let source: ScheduledAlarmObservationSource
  let immutableFingerprint: String
  let timeZoneIdentifier: String
  let utcOffsetSeconds: Int
  let localGregorianDayKey: String
  let localGregorianDayOrdinal: Int
  let localMinute: Int
  let receivedAt: Date

  init(
    id: UUID,
    occurrenceID: String,
    rootOccurrenceID: String,
    parentOccurrenceID: String?,
    routineID: UUID,
    scheduleID: UUID,
    actionObservedAt: Date,
    scheduledFireAt: Date,
    resetGeneration: UInt64,
    source: ScheduledAlarmObservationSource,
    immutableFingerprint: String,
    timeZoneIdentifier: String,
    utcOffsetSeconds: Int,
    localGregorianDayKey: String,
    localGregorianDayOrdinal: Int,
    localMinute: Int,
    receivedAt: Date
  ) {
    self.id = id
    self.occurrenceID = occurrenceID
    self.rootOccurrenceID = rootOccurrenceID
    self.parentOccurrenceID = parentOccurrenceID
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.actionObservedAt = actionObservedAt
    self.scheduledFireAt = scheduledFireAt
    self.resetGeneration = resetGeneration
    self.source = source
    self.immutableFingerprint = immutableFingerprint
    self.timeZoneIdentifier = timeZoneIdentifier
    self.utcOffsetSeconds = utcOffsetSeconds
    self.localGregorianDayKey = localGregorianDayKey
    self.localGregorianDayOrdinal = localGregorianDayOrdinal
    self.localMinute = localMinute
    self.receivedAt = receivedAt
  }
}

nonisolated struct HomeWeatherSnapshot: Sendable, Equatable {
  let id: UUID
  let condition: HomeWeatherCondition
  let temperatureCelsius: Double
  let latitudeE4: Int
  let longitudeE4: Int
  let fetchedAt: Date
  let fetchedTimeZoneIdentifier: String
  let fetchedUTCOffsetSeconds: Int

  init(
    id: UUID,
    condition: HomeWeatherCondition,
    temperatureCelsius: Double,
    latitudeE4: Int,
    longitudeE4: Int,
    fetchedAt: Date,
    fetchedTimeZoneIdentifier: String,
    fetchedUTCOffsetSeconds: Int
  ) {
    self.id = id
    self.condition = condition
    self.temperatureCelsius = temperatureCelsius
    self.latitudeE4 = latitudeE4
    self.longitudeE4 = longitudeE4
    self.fetchedAt = fetchedAt
    self.fetchedTimeZoneIdentifier = fetchedTimeZoneIdentifier
    self.fetchedUTCOffsetSeconds = fetchedUTCOffsetSeconds
  }
}

nonisolated struct AlarmRootChainStateSnapshot: Sendable, Equatable {
  let id: UUID
  let rootOccurrenceID: String
  let routineID: UUID
  let scheduleID: UUID
  let resetGeneration: UInt64
  let rootFingerprint: String
  let earliestObservedOccurrenceID: String?
  let earliestObservedAt: Date?
  let latestObservedOccurrenceID: String?
  let latestObservedAt: Date?
  let terminalOccurrenceID: String?
  let terminalAt: Date?
  let state: AlarmRootChainState
  let updatedAt: Date

  init(
    id: UUID,
    rootOccurrenceID: String,
    routineID: UUID,
    scheduleID: UUID,
    resetGeneration: UInt64,
    rootFingerprint: String,
    earliestObservedOccurrenceID: String?,
    earliestObservedAt: Date?,
    latestObservedOccurrenceID: String?,
    latestObservedAt: Date?,
    terminalOccurrenceID: String?,
    terminalAt: Date?,
    state: AlarmRootChainState,
    updatedAt: Date
  ) {
    self.id = id
    self.rootOccurrenceID = rootOccurrenceID
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.resetGeneration = resetGeneration
    self.rootFingerprint = rootFingerprint
    self.earliestObservedOccurrenceID = earliestObservedOccurrenceID
    self.earliestObservedAt = earliestObservedAt
    self.latestObservedOccurrenceID = latestObservedOccurrenceID
    self.latestObservedAt = latestObservedAt
    self.terminalOccurrenceID = terminalOccurrenceID
    self.terminalAt = terminalAt
    self.state = state
    self.updatedAt = updatedAt
  }
}

nonisolated struct AlarmPlatformSnapshot: Sendable, Equatable {
  let id: UUID
  let scheduleID: UUID
  let routineID: UUID
  let desiredScheduleFingerprint: String
  let platformRequestID: UUID
  let state: AlarmPlatformState
  let updatedAt: Date
  let lastErrorCode: String?

  init(
    id: UUID,
    scheduleID: UUID,
    routineID: UUID,
    desiredScheduleFingerprint: String,
    platformRequestID: UUID,
    state: AlarmPlatformState,
    updatedAt: Date,
    lastErrorCode: String?
  ) {
    self.id = id
    self.scheduleID = scheduleID
    self.routineID = routineID
    self.desiredScheduleFingerprint = desiredScheduleFingerprint
    self.platformRequestID = platformRequestID
    self.state = state
    self.updatedAt = updatedAt
    self.lastErrorCode = lastErrorCode
  }
}
