//
//  HomeWeatherService.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import CoreLocation
import Foundation
import UIKit
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
  case attributionUnavailable
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

  func locationServicesEnabled() async -> Bool
  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus
  func currentLocation() async throws -> CLLocation
  func weatherSnapshot(for location: CLLocation) async throws -> HomeWeatherSnapshot
  func weatherAttribution() async throws -> HomeWeatherAttribution
  func cancelCurrentLocationRequests()
}

@MainActor
protocol HomeLocationManaging: AnyObject {
  var delegate: (any CLLocationManagerDelegate)? { get set }
  var desiredAccuracy: CLLocationAccuracy { get set }
  var authorizationStatus: CLAuthorizationStatus { get }

  func requestWhenInUseAuthorization()
  func requestLocation()
  func stopUpdatingLocation()
}

extension CLLocationManager: HomeLocationManaging {}

typealias HomeLocationTimeoutScheduler = @MainActor @Sendable (
  Duration,
  @escaping @MainActor @Sendable () -> Void
) -> Task<Void, Never>

nonisolated struct HomeWeatherAttributionSource: Sendable, Equatable {
  let serviceName: String
  let combinedMarkLightURL: URL
  let combinedMarkDarkURL: URL
  let legalPageURL: URL
}

nonisolated struct HomeWeatherAttributionAssetResponse: Sendable, Equatable {
  let data: Data
  let statusCode: Int
  let finalURL: URL
}

typealias HomeWeatherAttributionProvider =
  @MainActor () async throws -> HomeWeatherAttributionSource
typealias HomeWeatherAttributionAssetLoader =
  @Sendable (URL) async throws -> HomeWeatherAttributionAssetResponse

@MainActor
final class CoreLocationWeatherService: NSObject, HomeWeatherService {
  nonisolated private static let maximumLocationAge: TimeInterval = 15 * 60
  nonisolated private static let maximumAttributionAssetBytes = 1_000_000
  private static let maximumLocationRequestAttempts = 3
  private static let locationRequestTimeout: Duration = .seconds(10)

  private let locationManager: any HomeLocationManaging
  private let weatherService: WeatherService
  private let locationServicesEnabledProbe: @Sendable () -> Bool
  private let scheduleLocationTimeout: HomeLocationTimeoutScheduler
  private let weatherAttributionProvider: HomeWeatherAttributionProvider
  private let weatherAttributionAssetLoader: HomeWeatherAttributionAssetLoader
  private var authorizationContinuations: [
    CheckedContinuation<HomeWeatherAuthorizationStatus, Never>
  ] = []
  private var locationContinuations: [CheckedContinuation<CLLocation, Error>] = []
  private var locationRequestStartedAt: Date?
  private var locationRequestAttempt = 0
  private var activeLocationRequestID: UUID?
  private var locationTimeoutTask: Task<Void, Never>?
  private var cachedWeatherAttribution: HomeWeatherAttribution?
  private var weatherAttributionTask: Task<HomeWeatherAttribution, Error>?

  #if DEBUG
  var pendingLocationCallerCount: Int {
    locationContinuations.count
  }
  #endif

  override convenience init() {
    self.init(
      locationManager: CLLocationManager(),
      weatherService: .shared,
      locationServicesEnabled: {
        CLLocationManager.locationServicesEnabled()
      },
      scheduleLocationTimeout: { duration, action in
        Task { @MainActor in
          try? await Task.sleep(for: duration)
          guard !Task.isCancelled else {
            return
          }

          action()
        }
      },
      weatherAttributionProvider: nil,
      weatherAttributionAssetLoader: nil
    )
  }

  init(
    locationManager: any HomeLocationManaging,
    weatherService: WeatherService,
    locationServicesEnabled: @escaping @Sendable () -> Bool,
    scheduleLocationTimeout: @escaping HomeLocationTimeoutScheduler,
    weatherAttributionProvider: HomeWeatherAttributionProvider? = nil,
    weatherAttributionAssetLoader: HomeWeatherAttributionAssetLoader? = nil
  ) {
    self.locationManager = locationManager
    self.weatherService = weatherService
    self.locationServicesEnabledProbe = locationServicesEnabled
    self.scheduleLocationTimeout = scheduleLocationTimeout
    self.weatherAttributionProvider = weatherAttributionProvider ?? {
      let attribution = try await weatherService.attribution
      return HomeWeatherAttributionSource(
        serviceName: attribution.serviceName,
        combinedMarkLightURL: attribution.combinedMarkLightURL,
        combinedMarkDarkURL: attribution.combinedMarkDarkURL,
        legalPageURL: attribution.legalPageURL
      )
    }
    self.weatherAttributionAssetLoader = weatherAttributionAssetLoader
      ?? Self.loadAttributionAsset
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  var authorizationStatus: HomeWeatherAuthorizationStatus {
    #if DEBUG
    if let uiTestingAuthorizationStatus = Self.uiTestingAuthorizationStatus {
      return uiTestingAuthorizationStatus
    }
    #endif

    return switch locationManager.authorizationStatus {
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

  func locationServicesEnabled() async -> Bool {
    #if DEBUG
    if Self.uiTestingAuthorizationStatus != nil {
      return true
    }
    #endif

    let probe = locationServicesEnabledProbe
    return await Task.detached(priority: .userInitiated) {
      probe()
    }.value
  }

  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus {
    #if DEBUG
    if let uiTestingAuthorizationStatus = Self.uiTestingAuthorizationStatus {
      return uiTestingAuthorizationStatus
    }
    #endif

    guard authorizationStatus == .notDetermined else {
      return authorizationStatus
    }
    guard await locationServicesEnabled() else {
      return .notDetermined
    }

    return await withCheckedContinuation { continuation in
      authorizationContinuations.append(continuation)
      locationManager.requestWhenInUseAuthorization()
    }
  }

  func currentLocation() async throws -> CLLocation {
    guard await locationServicesEnabled() else {
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

    #if DEBUG
    if Self.usesUITestingWeatherFixture {
      // UI review uses a deterministic coordinate after the fixture has
      // supplied its authorization state.
      return Self.uiTestingLocation
    }
    #endif

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

    #if DEBUG
    if Self.usesUITestingWeatherFixture {
      return Self.uiTestingWeatherSnapshot(for: location)
    }
    #endif

    do {
      let weather = try await weatherService.weather(for: location)
      let temperatureCelsius = weather.currentWeather.temperature
        .converted(to: .celsius)
        .value
      let todayForecast = weather.dailyForecast.forecast.first
      let dailyHighCelsius = todayForecast?.highTemperature
        .converted(to: .celsius)
        .value
      let dailyLowCelsius = todayForecast?.lowTemperature
        .converted(to: .celsius)
        .value
      let fetchedAt = Date()
      let timeZone = TimeZone.current

      guard temperatureCelsius.isFinite,
            dailyHighCelsius?.isFinite != false,
            dailyLowCelsius?.isFinite != false,
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
        dailyHighCelsius: dailyHighCelsius,
        dailyLowCelsius: dailyLowCelsius,
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

  func weatherAttribution() async throws -> HomeWeatherAttribution {
    #if DEBUG
    if Self.usesUITestingWeatherFixture {
      return Self.uiTestingWeatherAttribution
    }
    #endif

    if let cachedWeatherAttribution {
      return cachedWeatherAttribution
    }

    if let weatherAttributionTask {
      return try await weatherAttributionTask.value
    }

    let task = Task { [weak self] in
      guard let self else {
        throw CancellationError()
      }
      return try await self.fetchWeatherAttribution()
    }
    weatherAttributionTask = task

    do {
      let attribution = try await task.value
      cachedWeatherAttribution = attribution
      weatherAttributionTask = nil
      return attribution
    } catch {
      weatherAttributionTask = nil
      throw error
    }
  }

  func cancelCurrentLocationRequests() {
    finishLocationRequests(with: .failure(CancellationError()))
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

  nonisolated static func isValidAttributionURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
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

  private func endActiveLocationAttempt() {
    guard activeLocationRequestID != nil else {
      locationTimeoutTask?.cancel()
      locationTimeoutTask = nil
      return
    }

    activeLocationRequestID = nil
    locationTimeoutTask?.cancel()
    locationTimeoutTask = nil
    locationRequestStartedAt = nil
    locationManager.stopUpdatingLocation()
  }

  private func finishLocationRequests(with result: Result<CLLocation, Error>) {
    endActiveLocationAttempt()
    let continuations = locationContinuations
    locationContinuations.removeAll()
    locationRequestAttempt = 0

    switch result {
    case .success(let location):
      continuations.forEach { $0.resume(returning: location) }
    case .failure(let error):
      continuations.forEach { $0.resume(throwing: error) }
    }
  }

  private func startLocationRequest() {
    guard !locationContinuations.isEmpty, activeLocationRequestID == nil else {
      return
    }

    locationRequestAttempt += 1
    locationRequestStartedAt = Date()
    let requestID = UUID()
    activeLocationRequestID = requestID

    locationTimeoutTask = scheduleLocationTimeout(Self.locationRequestTimeout) {
      [weak self] in
      self?.locationRequestDidTimeOut(requestID: requestID)
    }
    locationManager.requestLocation()
  }

  private func locationRequestDidTimeOut(requestID: UUID) {
    guard activeLocationRequestID == requestID else {
      return
    }

    retryLocationRequestOrFinish()
  }

  private func retryLocationRequestOrFinish() {
    guard !locationContinuations.isEmpty, activeLocationRequestID != nil else {
      return
    }

    endActiveLocationAttempt()

    if locationRequestAttempt < Self.maximumLocationRequestAttempts {
      startLocationRequest()
    } else {
      finishLocationRequests(with: .failure(HomeWeatherServiceError.noLocationFix))
    }
  }

  private func fetchWeatherAttribution() async throws -> HomeWeatherAttribution {
    do {
      let source = try await weatherAttributionProvider()
      guard !source.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            Self.isValidAttributionURL(source.combinedMarkLightURL),
            Self.isValidAttributionURL(source.combinedMarkDarkURL),
            Self.isValidAttributionURL(source.legalPageURL) else {
        throw HomeWeatherServiceError.attributionUnavailable
      }

      async let lightResponse = weatherAttributionAssetLoader(
        source.combinedMarkLightURL
      )
      async let darkResponse = weatherAttributionAssetLoader(
        source.combinedMarkDarkURL
      )
      let (light, dark) = try await (lightResponse, darkResponse)

      guard Self.isValidAttributionAsset(light),
            Self.isValidAttributionAsset(dark),
            UIImage(data: light.data) != nil,
            UIImage(data: dark.data) != nil else {
        throw HomeWeatherServiceError.attributionUnavailable
      }

      return HomeWeatherAttribution(
        serviceName: source.serviceName,
        combinedMarkLightData: light.data,
        combinedMarkDarkData: dark.data,
        legalPageURL: source.legalPageURL
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw HomeWeatherServiceError.attributionUnavailable
    }
  }

  nonisolated private static func isValidAttributionAsset(
    _ response: HomeWeatherAttributionAssetResponse
  ) -> Bool {
    (200..<300).contains(response.statusCode)
      && isValidAttributionURL(response.finalURL)
      && !response.data.isEmpty
      && response.data.count <= maximumAttributionAssetBytes
  }

  nonisolated private static func loadAttributionAsset(
    from url: URL
  ) async throws -> HomeWeatherAttributionAssetResponse {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw HomeWeatherServiceError.attributionUnavailable
    }

    return HomeWeatherAttributionAssetResponse(
      data: data,
      statusCode: httpResponse.statusCode,
      finalURL: httpResponse.url ?? url
    )
  }

  #if DEBUG
  private static let uiTestingWeatherFixtureArgument =
    "-ui-testing-weather-fixture"
  private static let uiTestingLocationAuthorizedArgument =
    "-ui-testing-weather-location-authorized"
  private static let uiTestingLocationDeniedArgument =
    "-ui-testing-weather-location-denied"

  private static var usesUITestingWeatherFixture: Bool {
    ProcessInfo.processInfo.arguments.contains(uiTestingWeatherFixtureArgument)
  }

  // Physical-device XCUITest cannot consistently invoke interruption monitors
  // for the system location prompt. This fixture lets the review test exercise
  // MORU's authorized and denied UI states without changing device permissions.
  // It is compiled only into Debug builds and requires the weather fixture flag.
  private static var uiTestingAuthorizationStatus: HomeWeatherAuthorizationStatus? {
    guard usesUITestingWeatherFixture else {
      return nil
    }

    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains(uiTestingLocationAuthorizedArgument) {
      return .authorized
    }
    if arguments.contains(uiTestingLocationDeniedArgument) {
      return .denied
    }
    return nil
  }

  private static let uiTestingLocation = CLLocation(
    latitude: 37.5665,
    longitude: 126.9780
  )

  private static func uiTestingWeatherSnapshot(
    for location: CLLocation
  ) -> HomeWeatherSnapshot {
    let fetchedAt = Date()
    let timeZone = TimeZone.current

    return HomeWeatherSnapshot(
      id: UUID(),
      condition: .clear,
      temperatureCelsius: 22,
      dailyHighCelsius: 25,
      dailyLowCelsius: 18,
      latitudeE4: Int((location.coordinate.latitude * 10_000).rounded()),
      longitudeE4: Int((location.coordinate.longitude * 10_000).rounded()),
      fetchedAt: fetchedAt,
      fetchedTimeZoneIdentifier: timeZone.identifier,
      fetchedUTCOffsetSeconds: timeZone.secondsFromGMT(for: fetchedAt)
    )
  }

  private static let uiTestingWeatherAttribution: HomeWeatherAttribution = {
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: 96, height: 20)
    )
    let lightData = renderer.pngData { context in
      UIColor.black.setFill()
      (" Weather" as NSString).draw(
        at: CGPoint(x: 1, y: 4),
        withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
      )
    }
    let darkData = renderer.pngData { context in
      UIColor.white.setFill()
      (" Weather" as NSString).draw(
        at: CGPoint(x: 1, y: 4),
        withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
      )
    }

    return HomeWeatherAttribution(
      serviceName: "Apple Weather",
      combinedMarkLightData: lightData,
      combinedMarkDarkData: darkData,
      legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    )
  }()
  #endif
}

extension CoreLocationWeatherService: CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard authorizationStatus != .notDetermined else {
      return
    }

    resumeAuthorizationContinuations(with: authorizationStatus)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard activeLocationRequestID != nil, !locationContinuations.isEmpty else {
      return
    }

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

    finishLocationRequests(with: .success(location))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard activeLocationRequestID != nil, !locationContinuations.isEmpty else {
      return
    }

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

    finishLocationRequests(with: .failure(serviceError))
  }
}
