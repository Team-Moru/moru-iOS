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
  let latitudeE4: Int
  let longitudeE4: Int
  let fetchedAt: Date
  let fetchedTimeZoneIdentifier: String
  let fetchedUTCOffsetSeconds: Int
}
