//
//  HomeWeatherSnapshotMapper.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

enum HomeWeatherSnapshotMapperError: Error, Equatable {
  case invalidValue(field: String)
  case unknownCondition(String)
}

enum HomeWeatherSnapshotMapper {
  static func makePersistedSnapshot(
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

  static func makeDomainSnapshot(
    from persisted: PersistedHomeWeatherSnapshot,
    now: Date
  ) throws -> HomeWeatherSnapshot {
    guard let condition = HomeWeatherCondition(rawValue: persisted.conditionRawValue) else {
      throw HomeWeatherSnapshotMapperError.unknownCondition(persisted.conditionRawValue)
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

  private static func validate(_ snapshot: HomeWeatherSnapshot, now: Date) throws {
    guard snapshot.temperatureCelsius.isFinite else {
      throw HomeWeatherSnapshotMapperError.invalidValue(field: "temperatureCelsius")
    }
    guard (-900_000...900_000).contains(snapshot.latitudeE4) else {
      throw HomeWeatherSnapshotMapperError.invalidValue(field: "latitudeE4")
    }
    guard (-1_800_000...1_800_000).contains(snapshot.longitudeE4) else {
      throw HomeWeatherSnapshotMapperError.invalidValue(field: "longitudeE4")
    }
    guard TimeZone(identifier: snapshot.fetchedTimeZoneIdentifier) != nil else {
      throw HomeWeatherSnapshotMapperError.invalidValue(
        field: "fetchedTimeZoneIdentifier"
      )
    }
    guard (-86_400...86_400).contains(snapshot.fetchedUTCOffsetSeconds) else {
      throw HomeWeatherSnapshotMapperError.invalidValue(field: "fetchedUTCOffsetSeconds")
    }
    guard snapshot.fetchedAt <= now.addingTimeInterval(5 * 60) else {
      throw HomeWeatherSnapshotMapperError.invalidValue(field: "fetchedAt")
    }
  }
}
