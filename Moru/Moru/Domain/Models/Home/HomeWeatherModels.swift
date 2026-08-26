//
//  HomeWeatherModels.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

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

nonisolated struct HomeWeatherSnapshot: Sendable, Equatable {
  let id: UUID
  let condition: HomeWeatherCondition
  let temperatureCelsius: Double
  let dailyHighCelsius: Double?
  let dailyLowCelsius: Double?
  let latitudeE4: Int
  let longitudeE4: Int
  let fetchedAt: Date
  let fetchedTimeZoneIdentifier: String
  let fetchedUTCOffsetSeconds: Int

  init(
    id: UUID,
    condition: HomeWeatherCondition,
    temperatureCelsius: Double,
    dailyHighCelsius: Double? = nil,
    dailyLowCelsius: Double? = nil,
    latitudeE4: Int,
    longitudeE4: Int,
    fetchedAt: Date,
    fetchedTimeZoneIdentifier: String,
    fetchedUTCOffsetSeconds: Int
  ) {
    self.id = id
    self.condition = condition
    self.temperatureCelsius = temperatureCelsius
    self.dailyHighCelsius = dailyHighCelsius
    self.dailyLowCelsius = dailyLowCelsius
    self.latitudeE4 = latitudeE4
    self.longitudeE4 = longitudeE4
    self.fetchedAt = fetchedAt
    self.fetchedTimeZoneIdentifier = fetchedTimeZoneIdentifier
    self.fetchedUTCOffsetSeconds = fetchedUTCOffsetSeconds
  }
}

nonisolated struct HomeWeatherAttribution: Sendable, Equatable {
  let serviceName: String
  let combinedMarkLightData: Data
  let combinedMarkDarkData: Data
  let legalPageURL: URL
}

nonisolated struct HomeWeatherContent: Sendable, Equatable {
  let snapshot: HomeWeatherSnapshot
  let attribution: HomeWeatherAttribution
}
