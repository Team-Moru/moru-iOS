//
//  HomeWeatherService.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import CoreLocation
import Foundation
import WeatherKit

enum HomeWeatherAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

enum HomeWeatherServiceError: Error, Equatable, Sendable {
  case authorizationDenied
  case authorizationRestricted
  case locationServicesDisabled
  case noLocationFix
  case weatherUnavailable
  case invalidWeatherData
}

enum HomeWeatherRepositoryError: Error, Equatable, Sendable {
  case invalidCachedSnapshot
}

@MainActor
protocol HomeWeatherRepository: AnyObject {
  func cachedWeather() throws -> HomeWeatherSnapshot?
  func saveWeather(_ snapshot: HomeWeatherSnapshot) throws
  func eraseCachedWeather() throws
}

@MainActor
protocol HomeWeatherService: AnyObject {
  var authorizationStatus: HomeWeatherAuthorizationStatus { get }
  var isLocationServiceEnabled: Bool { get }

  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus
  func currentLocation() async throws -> CLLocation
  func weatherSnapshot(for location: CLLocation) async throws -> HomeWeatherSnapshot
  func cancelCurrentLocationRequests()
}

@MainActor
final class CoreLocationWeatherService: NSObject, HomeWeatherService {
  nonisolated private static let maximumLocationAge: TimeInterval = 15 * 60
  private static let maximumLocationRequestAttempts = 3
  private static let locationRequestTimeout: Duration = .seconds(10)

  private let locationManager: CLLocationManager
  private let weatherService: WeatherService
  private var authorizationContinuations: [
    CheckedContinuation<HomeWeatherAuthorizationStatus, Never>
  ] = []
  private var locationContinuations: [CheckedContinuation<CLLocation, Error>] = []
  private var locationRequestStartedAt: Date?
  private var locationRequestAttempt = 0
  private var locationTimeoutTask: Task<Void, Never>?

  override init() {
    locationManager = CLLocationManager()
    weatherService = .shared
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  var authorizationStatus: HomeWeatherAuthorizationStatus {
    switch locationManager.authorizationStatus {
    case .notDetermined:
      .notDetermined
    case .authorizedAlways, .authorizedWhenInUse:
      .authorized
    case .denied:
      .denied
    case .restricted:
      .restricted
    @unknown default:
      .restricted
    }
  }

  var isLocationServiceEnabled: Bool {
    CLLocationManager.locationServicesEnabled()
  }

  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus {
    guard authorizationStatus == .notDetermined else {
      return authorizationStatus
    }
    guard isLocationServiceEnabled else {
      return .notDetermined
    }

    return await withCheckedContinuation { continuation in
      authorizationContinuations.append(continuation)
      locationManager.requestWhenInUseAuthorization()
    }
  }

  func currentLocation() async throws -> CLLocation {
    guard isLocationServiceEnabled else {
      throw HomeWeatherServiceError.locationServicesDisabled
    }

    switch authorizationStatus {
    case .authorized:
      break
    case .denied:
      throw HomeWeatherServiceError.authorizationDenied
    case .restricted:
      throw HomeWeatherServiceError.authorizationRestricted
    case .notDetermined:
      throw HomeWeatherServiceError.noLocationFix
    }

    return try await withCheckedThrowingContinuation { continuation in
      let shouldRequestLocation = locationContinuations.isEmpty
      locationContinuations.append(continuation)

      if shouldRequestLocation {
        locationRequestAttempt = 0
        startLocationRequest()
      }
    }
  }

  func weatherSnapshot(for location: CLLocation) async throws -> HomeWeatherSnapshot {
    guard Self.isValidLocation(location) else {
      throw HomeWeatherServiceError.invalidWeatherData
    }

    do {
      let weather = try await weatherService.weather(for: location)
      let temperatureCelsius = weather.currentWeather.temperature
        .converted(to: .celsius)
        .value
      let fetchedAt = Date()
      let timeZone = TimeZone.current

      guard temperatureCelsius.isFinite,
            let latitudeE4 = roundedE4(location.coordinate.latitude),
            let longitudeE4 = roundedE4(location.coordinate.longitude),
            !timeZone.identifier.isEmpty,
            TimeZone(identifier: timeZone.identifier) != nil,
            (-86_400...86_400).contains(timeZone.secondsFromGMT(for: fetchedAt)) else {
        throw HomeWeatherServiceError.invalidWeatherData
      }

      return HomeWeatherSnapshot(
        id: UUID(),
        condition: Self.condition(for: weather.currentWeather.condition),
        temperatureCelsius: temperatureCelsius,
        latitudeE4: latitudeE4,
        longitudeE4: longitudeE4,
        fetchedAt: fetchedAt,
        fetchedTimeZoneIdentifier: timeZone.identifier,
        fetchedUTCOffsetSeconds: timeZone.secondsFromGMT(for: fetchedAt)
      )
    } catch let error as HomeWeatherServiceError {
      throw error
    } catch {
      throw HomeWeatherServiceError.weatherUnavailable
    }
  }

  func cancelCurrentLocationRequests() {
    locationTimeoutTask?.cancel()
    locationTimeoutTask = nil
    let continuations = locationContinuations
    locationContinuations.removeAll()
    locationRequestStartedAt = nil
    locationRequestAttempt = 0
    continuations.forEach { $0.resume(throwing: CancellationError()) }
  }

  nonisolated static func isValidLocation(_ location: CLLocation) -> Bool {
    let coordinate = location.coordinate
    return coordinate.latitude.isFinite
      && coordinate.longitude.isFinite
      && (-90...90).contains(coordinate.latitude)
      && (-180...180).contains(coordinate.longitude)
      && location.horizontalAccuracy.isFinite
      && location.horizontalAccuracy >= 0
  }

  nonisolated static func isValidLocationFix(
    _ location: CLLocation,
    requestedAt: Date?,
    now: Date
  ) -> Bool {
    guard requestedAt != nil, isValidLocation(location) else {
      return false
    }

    let futureTolerance: TimeInterval = 5
    return location.timestamp >= now.addingTimeInterval(-maximumLocationAge)
      && location.timestamp <= now.addingTimeInterval(futureTolerance)
  }

  nonisolated static func condition(for condition: WeatherCondition) -> HomeWeatherCondition {
    switch condition {
    case .clear, .mostlyClear:
      .clear
    case .cloudy, .mostlyCloudy, .partlyCloudy:
      .cloudy
    case .drizzle, .freezingDrizzle, .freezingRain, .heavyRain, .rain, .sunShowers:
      .rain
    case .blizzard, .blowingSnow, .flurries, .heavySnow, .snow, .sunFlurries:
      .snow
    case .breezy, .hurricane, .windy:
      .wind
    case .blowingDust, .foggy, .haze, .smoky:
      .fog
    case .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
         .thunderstorms, .tropicalStorm:
      .thunderstorm
    case .hail, .sleet, .wintryMix:
      .mixed
    case .frigid, .hot:
      .other
    @unknown default:
      .other
    }
  }

  private func roundedE4(_ coordinate: CLLocationDegrees) -> Int? {
    guard coordinate.isFinite else {
      return nil
    }

    let rounded = (coordinate * 10_000).rounded(.toNearestOrAwayFromZero)
    guard rounded.isFinite else {
      return nil
    }

    return Int(rounded)
  }

  private func resumeAuthorizationContinuations(with status: HomeWeatherAuthorizationStatus) {
    let continuations = authorizationContinuations
    authorizationContinuations.removeAll()
    continuations.forEach { $0.resume(returning: status) }
  }

  private func resumeLocationContinuations(throwing error: Error) {
    locationTimeoutTask?.cancel()
    locationTimeoutTask = nil
    let continuations = locationContinuations
    locationContinuations.removeAll()
    locationRequestStartedAt = nil
    locationRequestAttempt = 0
    continuations.forEach { $0.resume(throwing: error) }
  }

  private func startLocationRequest() {
    guard !locationContinuations.isEmpty else {
      return
    }

    locationTimeoutTask?.cancel()
    locationRequestAttempt += 1
    locationRequestStartedAt = Date()
    locationManager.requestLocation()

    locationTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: Self.locationRequestTimeout)
      guard !Task.isCancelled else {
        return
      }

      self?.retryLocationRequestOrFinish()
    }
  }

  private func retryLocationRequestOrFinish() {
    guard !locationContinuations.isEmpty else {
      return
    }

    if locationRequestAttempt < Self.maximumLocationRequestAttempts {
      startLocationRequest()
    } else {
      resumeLocationContinuations(throwing: HomeWeatherServiceError.noLocationFix)
    }
  }
}

extension CoreLocationWeatherService: CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard authorizationStatus != .notDetermined else {
      return
    }

    resumeAuthorizationContinuations(with: authorizationStatus)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last(where: {
      Self.isValidLocationFix(
        $0,
        requestedAt: locationRequestStartedAt,
        now: Date()
      )
    }) else {
      retryLocationRequestOrFinish()
      return
    }

    locationTimeoutTask?.cancel()
    locationTimeoutTask = nil
    let continuations = locationContinuations
    locationContinuations.removeAll()
    locationRequestStartedAt = nil
    locationRequestAttempt = 0
    continuations.forEach { $0.resume(returning: location) }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let serviceError: HomeWeatherServiceError
    if let locationError = error as? CLError, locationError.code == .denied {
      serviceError = .authorizationDenied
    } else if let locationError = error as? CLError,
              locationError.code == .locationUnknown {
      retryLocationRequestOrFinish()
      return
    } else {
      serviceError = .noLocationFix
    }

    resumeLocationContinuations(throwing: serviceError)
  }
}
