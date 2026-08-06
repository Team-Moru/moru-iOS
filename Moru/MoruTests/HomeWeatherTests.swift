//
//  HomeWeatherTests.swift
//  MoruTests
//
//  Created by Codex on 7/22/26.
//

import CoreLocation
import Foundation
import SwiftData
import WeatherKit
import XCTest
@testable import Moru

final class HomeWeatherTests: XCTestCase {
  @MainActor
  func testAutomaticWeatherLoadRequestsPermissionWithoutTap() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let repository = TestHomeWeatherRepository(
      cachedSnapshot: makeSnapshot(fetchedAt: now)
    )
    let service = ControlledHomeWeatherService(authorizationStatus: .notDetermined)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.loadWeatherAutomaticallyIfNeeded()

    await service.waitForAuthorizationRequest(count: 1)

    XCTAssertEqual(viewModel.weatherState, .requestingPermission)
    XCTAssertEqual(service.authorizationRequestCount, 1)
    XCTAssertEqual(service.locationRequestCount, 0)
    XCTAssertEqual(service.weatherRequestCount, 0)
    XCTAssertEqual(repository.cachedWeatherReadCount, 0)

    service.fulfillAuthorization(with: .denied)
    await waitUntil { viewModel.weatherState == .denied }
  }

  func testWeatherConditionMappingCoversCurrentSDKConditions() {
    let mappings: [(WeatherCondition, HomeWeatherCondition)] = [
      (.clear, .clear),
      (.mostlyCloudy, .cloudy),
      (.heavyRain, .rain),
      (.blizzard, .snow),
      (.windy, .wind),
      (.foggy, .fog),
      (.thunderstorms, .thunderstorm),
      (.wintryMix, .mixed),
      (.hot, .other),
    ]

    for (condition, expected) in mappings {
      XCTAssertEqual(CoreLocationWeatherService.condition(for: condition), expected)
    }
  }

  @MainActor
  func testLocationServicesEnabledProbeRunsOffMainThread() async {
    let manager = TestHomeLocationManager()
    manager.testAuthorizationStatus = .authorizedWhenInUse
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = CoreLocationWeatherService(
      locationManager: manager,
      weatherService: .shared,
      locationServicesEnabled: {
        !Thread.isMainThread
      },
      scheduleLocationTimeout: { duration, action in
        scheduler.schedule(after: duration, action: action)
      }
    )

    let servicesEnabled = await service.locationServicesEnabled()
    XCTAssertTrue(servicesEnabled)
  }

  @MainActor
  func testWeatherAttributionLoadsAssetsOnceAndCachesSharedResult() async throws {
    let source = makeTestAttributionSource()
    let sourceProvider = TestWeatherAttributionSourceProvider(source: source)
    let assetLoader = TestWeatherAttributionAssetLoader(
      responseData: testAttributionPNGData
    )
    let service = makeCoreLocationService(
      manager: TestHomeLocationManager(),
      scheduler: ManualHomeLocationTimeoutScheduler(),
      attributionProvider: {
        try await sourceProvider.load()
      },
      attributionAssetLoader: { url in
        try await assetLoader.load(url)
      }
    )

    async let first = service.weatherAttribution()
    async let second = service.weatherAttribution()
    let (firstAttribution, secondAttribution) = try await (first, second)
    let cachedAttribution = try await service.weatherAttribution()

    XCTAssertEqual(firstAttribution, makeTestWeatherAttribution())
    XCTAssertEqual(secondAttribution, firstAttribution)
    XCTAssertEqual(cachedAttribution, firstAttribution)
    XCTAssertEqual(sourceProvider.requestCount, 1)
    let assetRequestCount = await assetLoader.requestCount
    XCTAssertEqual(assetRequestCount, 2)
  }

  @MainActor
  func testWeatherAttributionRejectsInsecureURLsAndInvalidImageData() async {
    let insecureProvider = TestWeatherAttributionSourceProvider(
      source: HomeWeatherAttributionSource(
        serviceName: "Apple Weather",
        combinedMarkLightURL: URL(string: "http://example.com/light.png")!,
        combinedMarkDarkURL: URL(string: "https://example.com/dark.png")!,
        legalPageURL: URL(string: "https://example.com/legal")!
      )
    )
    let unusedLoader = TestWeatherAttributionAssetLoader(
      responseData: testAttributionPNGData
    )
    let insecureService = makeCoreLocationService(
      manager: TestHomeLocationManager(),
      scheduler: ManualHomeLocationTimeoutScheduler(),
      attributionProvider: {
        try await insecureProvider.load()
      },
      attributionAssetLoader: { url in
        try await unusedLoader.load(url)
      }
    )

    await assertAttributionUnavailable(from: insecureService)
    let unusedRequestCount = await unusedLoader.requestCount
    XCTAssertEqual(unusedRequestCount, 0)

    let invalidImageLoader = TestWeatherAttributionAssetLoader(
      responseData: Data("not-an-image".utf8)
    )
    let invalidImageService = makeCoreLocationService(
      manager: TestHomeLocationManager(),
      scheduler: ManualHomeLocationTimeoutScheduler(),
      attributionProvider: {
        makeTestAttributionSource()
      },
      attributionAssetLoader: { url in
        try await invalidImageLoader.load(url)
      }
    )

    await assertAttributionUnavailable(from: invalidImageService)
    let invalidImageRequestCount = await invalidImageLoader.requestCount
    XCTAssertEqual(invalidImageRequestCount, 2)
  }

  func testLocationFixAcceptsRecentCachedLocationForIPadCompatibility() {
    let now = fixtureDate("2026-07-28T09:00:00Z")
    let requestedAt = now.addingTimeInterval(-1)
    let recentCachedLocation = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9781),
      altitude: 0,
      horizontalAccuracy: 1_000,
      verticalAccuracy: -1,
      timestamp: now.addingTimeInterval(-10 * 60)
    )

    XCTAssertTrue(
      CoreLocationWeatherService.isValidLocationFix(
        recentCachedLocation,
        requestedAt: requestedAt,
        now: now
      )
    )
  }

  func testLocationFixRejectsStaleOrFutureLocation() {
    let now = fixtureDate("2026-07-28T09:00:00Z")
    let requestedAt = now.addingTimeInterval(-1)
    let staleLocation = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9781),
      altitude: 0,
      horizontalAccuracy: 1_000,
      verticalAccuracy: -1,
      timestamp: now.addingTimeInterval(-15 * 60 - 1)
    )
    let futureLocation = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9781),
      altitude: 0,
      horizontalAccuracy: 1_000,
      verticalAccuracy: -1,
      timestamp: now.addingTimeInterval(6)
    )

    XCTAssertFalse(
      CoreLocationWeatherService.isValidLocationFix(
        staleLocation,
        requestedAt: requestedAt,
        now: now
      )
    )
    XCTAssertFalse(
      CoreLocationWeatherService.isValidLocationFix(
        futureLocation,
        requestedAt: requestedAt,
        now: now
      )
    )
  }

  @MainActor
  func testLocationTimeoutStopsEachAttemptBeforeRetryingThreeTimes() async {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let locationTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    scheduler.fire(at: 0)
    XCTAssertEqual(manager.operations, [.request, .stop, .request])

    scheduler.fire(at: 1)
    XCTAssertEqual(manager.operations, [.request, .stop, .request, .stop, .request])

    scheduler.fire(at: 2)
    XCTAssertEqual(
      manager.operations,
      [.request, .stop, .request, .stop, .request, .stop]
    )

    do {
      _ = try await locationTask.value
      XCTFail("Expected noLocationFix after three timed-out attempts.")
    } catch let error as HomeWeatherServiceError {
      XCTAssertEqual(error, .noLocationFix)
    } catch {
      XCTFail("Unexpected location error: \(error)")
    }
  }

  @MainActor
  func testLocationTimeoutStartsRealSecondRequestAndCanSucceed() async throws {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let locationTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    scheduler.fire(at: 0)
    XCTAssertEqual(manager.operations, [.request, .stop, .request])

    scheduler.fire(at: 0)
    XCTAssertEqual(manager.operations, [.request, .stop, .request])

    let location = validCurrentLocation()
    manager.deliver(location)

    let result = try await locationTask.value
    XCTAssertEqual(result.coordinate.latitude, location.coordinate.latitude)
    XCTAssertEqual(result.coordinate.longitude, location.coordinate.longitude)
    XCTAssertEqual(manager.operations, [.request, .stop, .request, .stop])
  }

  @MainActor
  func testLocationUnknownStopsBeforeEachRetryAndThenFails() async {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let locationTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    manager.fail(with: CLError(.locationUnknown))
    manager.fail(with: CLError(.locationUnknown))
    manager.fail(with: CLError(.locationUnknown))

    XCTAssertEqual(
      manager.operations,
      [.request, .stop, .request, .stop, .request, .stop]
    )
    do {
      _ = try await locationTask.value
      XCTFail("Expected noLocationFix after three locationUnknown failures.")
    } catch let error as HomeWeatherServiceError {
      XCTAssertEqual(error, .noLocationFix)
    } catch {
      XCTFail("Unexpected location error: \(error)")
    }
  }

  @MainActor
  func testInvalidLocationStopsBeforeRetrying() async throws {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let locationTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    manager.deliver(
      CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9781),
        altitude: 0,
        horizontalAccuracy: 1_000,
        verticalAccuracy: -1,
        timestamp: Date().addingTimeInterval(-16 * 60)
      )
    )
    XCTAssertEqual(manager.operations, [.request, .stop, .request])

    let location = validCurrentLocation()
    manager.deliver(location)
    _ = try await locationTask.value

    XCTAssertEqual(manager.operations, [.request, .stop, .request, .stop])
  }

  @MainActor
  func testLocationCancellationStopsRequestAndIgnoresLateEvents() async {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let locationTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    service.cancelCurrentLocationRequests()

    do {
      _ = try await locationTask.value
      XCTFail("Expected CancellationError.")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Unexpected location error: \(error)")
    }

    scheduler.fire(at: 0)
    manager.deliver(validCurrentLocation())
    manager.fail(with: CLError(.locationUnknown))
    XCTAssertEqual(manager.operations, [.request, .stop])
  }

  @MainActor
  func testConcurrentLocationCallersShareOnePhysicalRequest() async throws {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let firstTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    let secondTask = Task {
      try await service.currentLocation()
    }
    await waitUntil { service.pendingLocationCallerCount == 2 }
    XCTAssertEqual(manager.operations, [.request])

    let location = validCurrentLocation()
    manager.deliver(location)

    let firstResult = try await firstTask.value
    let secondResult = try await secondTask.value
    XCTAssertEqual(firstResult.coordinate.latitude, location.coordinate.latitude)
    XCTAssertEqual(secondResult.coordinate.latitude, location.coordinate.latitude)
    XCTAssertEqual(manager.operations, [.request, .stop])
  }

  @MainActor
  func testLocationDeniedFailureStopsWithoutRetrying() async {
    let manager = TestHomeLocationManager()
    let scheduler = ManualHomeLocationTimeoutScheduler()
    let service = makeCoreLocationService(manager: manager, scheduler: scheduler)
    let locationTask = Task {
      try await service.currentLocation()
    }

    await waitUntil { manager.operations == [.request] }
    manager.fail(with: CLError(.denied))

    do {
      _ = try await locationTask.value
      XCTFail("Expected authorizationDenied.")
    } catch let error as HomeWeatherServiceError {
      XCTAssertEqual(error, .authorizationDenied)
    } catch {
      XCTFail("Unexpected location error: \(error)")
    }
    XCTAssertEqual(manager.operations, [.request, .stop])
  }

  @MainActor
  func testAuthorizedRequestMovesThroughPermissionLocationAndWeatherStates() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now)
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(authorizationStatus: .notDetermined)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()

    await service.waitForAuthorizationRequest(count: 1)
    XCTAssertEqual(viewModel.weatherState, .requestingPermission)

    service.fulfillAuthorization(with: .authorized)
    await service.waitForLocationRequest(count: 1)
    guard case .locating(let requestID) = viewModel.weatherState else {
      return XCTFail("Expected location loading after authorization.")
    }

    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)
    XCTAssertEqual(viewModel.weatherState, .loading(requestID))

    service.fulfillWeather(at: 0, with: snapshot)
    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(snapshot))
    }

    XCTAssertEqual(repository.savedSnapshots, [snapshot])
    XCTAssertEqual(
      viewModel.state.routineContent?.weather,
      .fresh(makeWeatherContent(snapshot))
    )
  }

  @MainActor
  func testAutomaticInitialWeatherLoadStartsWithoutTapAndOnlyOnce() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now)
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.loadWeatherAutomaticallyIfNeeded()
    viewModel.loadWeatherAutomaticallyIfNeeded()

    await service.waitForLocationRequest(count: 1)
    XCTAssertEqual(service.locationRequestCount, 1)

    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)
    service.fulfillWeather(at: 0, with: snapshot)

    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(snapshot))
    }

    viewModel.loadWeatherAutomaticallyIfNeeded()
    await Task.yield()

    XCTAssertEqual(service.locationRequestCount, 1)
    XCTAssertEqual(service.weatherRequestCount, 1)
  }

  @MainActor
  func testDeniedAndRestrictedPermissionEraseCachedWeather() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let cases: [(HomeWeatherAuthorizationStatus, HomeWeatherState)] = [
      (.denied, .denied),
      (.restricted, .restricted),
    ]

    for (authorizationStatus, expectedState) in cases {
      let repository = TestHomeWeatherRepository(
        cachedSnapshot: makeSnapshot(fetchedAt: now)
      )
      let service = ControlledHomeWeatherService(
        authorizationStatus: authorizationStatus
      )
      let viewModel = makeViewModel(repository: repository, service: service, now: now)

      viewModel.requestWeather()
      await waitUntil { viewModel.weatherState == expectedState }

      XCTAssertNil(repository.cachedSnapshot)
      XCTAssertEqual(repository.eraseCachedWeatherCount, 1)
      XCTAssertEqual(service.locationRequestCount, 0)
      XCTAssertEqual(service.weatherRequestCount, 0)
    }
  }

  @MainActor
  func testPermissionRecoveryAutomaticallyReloadsOnceAfterReturningActive() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let cases: [HomeWeatherAuthorizationStatus] = [.denied, .restricted]

    for initialAuthorizationStatus in cases {
      let snapshot = makeSnapshot(fetchedAt: now)
      let repository = TestHomeWeatherRepository()
      let service = ControlledHomeWeatherService(
        authorizationStatus: initialAuthorizationStatus
      )
      let viewModel = makeViewModel(repository: repository, service: service, now: now)

      viewModel.requestWeather()
      await waitUntil {
        viewModel.weatherState == (
          initialAuthorizationStatus == .denied ? .denied : .restricted
        )
      }
      await Task.yield()

      let cancelCountBeforeRecovery = service.cancelLocationRequestCount
      service.authorizationStatus = .authorized
      viewModel.resumeWeatherAfterAuthorizationChange()
      viewModel.resumeWeatherAfterAuthorizationChange()

      await service.waitForLocationRequest(count: 1)
      XCTAssertEqual(service.authorizationRequestCount, 0)
      XCTAssertEqual(service.locationRequestCount, 1)
      XCTAssertEqual(service.cancelLocationRequestCount, cancelCountBeforeRecovery)

      service.fulfillLocation(at: 0, with: seoulLocation)
      await service.waitForWeatherRequest(count: 1)
      service.fulfillWeather(at: 0, with: snapshot)
      await waitUntil {
        viewModel.weatherState == .fresh(makeWeatherContent(snapshot))
      }
    }
  }

  @MainActor
  func testPermissionRecoveryDoesNothingWhilePermissionRemainsDenied() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(authorizationStatus: .denied)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await waitUntil { viewModel.weatherState == .denied }
    await Task.yield()

    viewModel.resumeWeatherAfterAuthorizationChange()
    await Task.yield()

    XCTAssertEqual(viewModel.weatherState, .denied)
    XCTAssertEqual(service.authorizationRequestCount, 0)
    XCTAssertEqual(service.locationRequestCount, 0)
    XCTAssertEqual(service.weatherRequestCount, 0)
  }

  @MainActor
  func testSceneActivationDoesNotStartWeatherBeforeHomeTrigger() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.resumeWeatherAfterAuthorizationChange()
    await Task.yield()

    XCTAssertEqual(viewModel.weatherState, .notRequested)
    XCTAssertEqual(service.authorizationRequestCount, 0)
    XCTAssertEqual(service.locationRequestCount, 0)
    XCTAssertEqual(service.weatherRequestCount, 0)
  }

  @MainActor
  func testLocationFailureUsesFreshAndStaleCacheWithoutBlockingHome() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let cases: [(TimeInterval, (HomeWeatherContent) -> HomeWeatherState)] = [
      (30 * 60, HomeWeatherState.fresh),
      (30 * 60 + 1, HomeWeatherState.stale),
      (24 * 60 * 60, HomeWeatherState.stale),
    ]

    for (age, expectedState) in cases {
      let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-age))
      let repository = TestHomeWeatherRepository(cachedSnapshot: snapshot)
      let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
      let viewModel = makeViewModel(repository: repository, service: service, now: now)

      viewModel.requestWeather()
      await service.waitForLocationRequest(count: 1)
      service.failLocation(at: 0, with: .noLocationFix)
      await waitUntil {
        viewModel.weatherState == expectedState(makeWeatherContent(snapshot))
      }

      XCTAssertEqual(viewModel.state.loadState, .content)
      XCTAssertEqual(service.weatherRequestCount, 0)
    }
  }

  @MainActor
  func testWeatherFailureUsesNearbyCacheAndRejectsDistantCache() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-31 * 60))
    let nearbyRepository = TestHomeWeatherRepository(cachedSnapshot: snapshot)
    let nearbyService = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let nearbyViewModel = makeViewModel(
      repository: nearbyRepository,
      service: nearbyService,
      now: now
    )

    nearbyViewModel.requestWeather()
    await nearbyService.waitForLocationRequest(count: 1)
    nearbyService.fulfillLocation(at: 0, with: seoulLocation)
    await nearbyService.waitForWeatherRequest(count: 1)
    nearbyService.failWeather(at: 0, with: .weatherUnavailable)
    await waitUntil {
      nearbyViewModel.weatherState == .stale(makeWeatherContent(snapshot))
    }

    let distantRepository = TestHomeWeatherRepository(cachedSnapshot: snapshot)
    let distantService = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let distantViewModel = makeViewModel(
      repository: distantRepository,
      service: distantService,
      now: now
    )

    distantViewModel.requestWeather()
    await distantService.waitForLocationRequest(count: 1)
    distantService.fulfillLocation(
      at: 0,
      with: CLLocation(latitude: 37.5665, longitude: 127.0080)
    )
    await distantService.waitForWeatherRequest(count: 1)
    distantService.failWeather(at: 0, with: .weatherUnavailable)
    await waitUntil {
      distantViewModel.weatherState == .unavailable(.service(.weatherUnavailable))
    }

    XCTAssertNil(distantRepository.cachedSnapshot)
    XCTAssertEqual(distantRepository.eraseCachedWeatherCount, 1)
  }

  @MainActor
  func testCacheReadFailureStillLoadsLiveWeather() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now)
    let repository = TestHomeWeatherRepository(failsOnRead: true)
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)
    service.fulfillWeather(at: 0, with: snapshot)
    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(snapshot))
    }

    XCTAssertEqual(repository.cachedWeatherReadCount, 1)
    XCTAssertEqual(repository.saveWeatherAttemptCount, 1)
    XCTAssertEqual(service.locationRequestCount, 1)
    XCTAssertEqual(service.weatherRequestCount, 1)
  }

  @MainActor
  func testDistantCacheEraseFailureStillLoadsLiveWeather() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let cachedSnapshot = makeSnapshot(
      id: UUID(),
      fetchedAt: now.addingTimeInterval(-31 * 60)
    )
    let liveSnapshot = makeSnapshot(id: UUID(), fetchedAt: now)
    let repository = TestHomeWeatherRepository(
      cachedSnapshot: cachedSnapshot,
      failsOnErase: true
    )
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(
      at: 0,
      with: CLLocation(latitude: 37.5665, longitude: 127.0080)
    )
    await service.waitForWeatherRequest(count: 1)
    service.fulfillWeather(at: 0, with: liveSnapshot)
    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(liveSnapshot))
    }

    XCTAssertEqual(repository.eraseCachedWeatherCount, 1)
    XCTAssertEqual(repository.saveWeatherAttemptCount, 1)
    XCTAssertEqual(repository.cachedSnapshot, liveSnapshot)
    XCTAssertEqual(service.weatherRequestCount, 1)
  }

  @MainActor
  func testCacheWriteFailureStillShowsFreshWeather() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now)
    let repository = TestHomeWeatherRepository(failsOnSave: true)
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)
    service.fulfillWeather(at: 0, with: snapshot)
    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(snapshot))
    }

    XCTAssertEqual(repository.saveWeatherAttemptCount, 1)
    XCTAssertTrue(repository.savedSnapshots.isEmpty)
    XCTAssertNil(repository.cachedSnapshot)
  }

  @MainActor
  func testAttributionFailureNeverDisplaysWeatherValues() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now)
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(
      authorizationStatus: .authorized,
      attributionError: .attributionUnavailable
    )
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)
    service.fulfillWeather(at: 0, with: snapshot)

    await waitUntil {
      viewModel.weatherState
        == .unavailable(.service(.attributionUnavailable))
    }

    XCTAssertEqual(service.attributionRequestCount, 1)
    XCTAssertEqual(repository.savedSnapshots, [snapshot])
  }

  @MainActor
  func testPermissionStateWinsWhenCacheEraseFails() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let cases: [(HomeWeatherAuthorizationStatus, HomeWeatherState)] = [
      (.denied, .denied),
      (.restricted, .restricted),
    ]

    for (authorizationStatus, expectedState) in cases {
      let cachedSnapshot = makeSnapshot(fetchedAt: now)
      let repository = TestHomeWeatherRepository(
        cachedSnapshot: cachedSnapshot,
        failsOnErase: true
      )
      let service = ControlledHomeWeatherService(
        authorizationStatus: authorizationStatus
      )
      let viewModel = makeViewModel(repository: repository, service: service, now: now)

      viewModel.requestWeather()
      await waitUntil { viewModel.weatherState == expectedState }

      XCTAssertEqual(repository.eraseCachedWeatherCount, 1)
      XCTAssertEqual(repository.cachedSnapshot, cachedSnapshot)
      XCTAssertEqual(service.locationRequestCount, 0)
      XCTAssertEqual(service.weatherRequestCount, 0)
    }
  }

  @MainActor
  func testOnlyCurrentOverlappingRequestWritesWeather() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let firstSnapshot = makeSnapshot(id: UUID(), fetchedAt: now)
    let secondSnapshot = makeSnapshot(id: UUID(), fetchedAt: now)
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)

    #if DEBUG
    let staleResultDiscarded = expectation(description: "Stale weather is discarded")
    viewModel.onStaleWeatherResultDiscarded = { _ in
      staleResultDiscarded.fulfill()
    }
    #endif

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 2)
    service.fulfillLocation(at: 1, with: seoulLocation)
    await service.waitForWeatherRequest(count: 2)
    service.fulfillWeather(at: 1, with: secondSnapshot)
    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(secondSnapshot))
    }

    service.fulfillWeather(at: 0, with: firstSnapshot)
    #if DEBUG
    await fulfillment(of: [staleResultDiscarded], timeout: 1)
    #endif

    XCTAssertEqual(repository.savedSnapshots, [secondSnapshot])
    XCTAssertEqual(
      viewModel.weatherState,
      .fresh(makeWeatherContent(secondSnapshot))
    )
  }

  @MainActor
  func testLateAttributionResultCannotOverwriteNewerWeatherRequest() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let firstSnapshot = makeSnapshot(id: UUID(), fetchedAt: now)
    let secondSnapshot = makeSnapshot(id: UUID(), fetchedAt: now)
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(
      authorizationStatus: .authorized,
      automaticallyProvidesAttribution: false
    )
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(at: 0, with: seoulLocation)
    await service.waitForWeatherRequest(count: 1)
    service.fulfillWeather(at: 0, with: firstSnapshot)
    await service.waitForAttributionRequest(count: 1)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 2)
    service.fulfillLocation(at: 1, with: seoulLocation)
    await service.waitForWeatherRequest(count: 2)
    service.fulfillWeather(at: 1, with: secondSnapshot)
    await service.waitForAttributionRequest(count: 2)

    service.fulfillAttribution(at: 0, with: makeTestWeatherAttribution())
    await Task.yield()
    XCTAssertNotEqual(
      viewModel.weatherState,
      .fresh(makeWeatherContent(firstSnapshot))
    )

    service.fulfillAttribution(at: 1, with: makeTestWeatherAttribution())
    await waitUntil {
      viewModel.weatherState == .fresh(makeWeatherContent(secondSnapshot))
    }
  }

  @MainActor
  func testRepositoryKeepsTwentyFourHourBoundaryAndDeletesExpiredCache() throws {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataHomeWeatherRepository(
      modelContext: context,
      now: { now }
    )
    let boundarySnapshot = makeSnapshot(
      fetchedAt: now.addingTimeInterval(-24 * 60 * 60)
    )

    try repository.saveWeather(boundarySnapshot)
    XCTAssertEqual(try repository.cachedWeather(), boundarySnapshot)

    context.insert(
      makePersistedSnapshot(fetchedAt: now.addingTimeInterval(-(24 * 60 * 60 + 1)))
    )
    try context.save()
    XCTAssertEqual(try repository.cachedWeather(), boundarySnapshot)

    try repository.eraseCachedWeather()
    context.insert(makePersistedSnapshot(conditionRawValue: "invalid", fetchedAt: now))
    try context.save()
    XCTAssertNil(try repository.cachedWeather())
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
  }

  @MainActor
  func testLocalDataResetDeletesWeatherCache() throws {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    context.insert(makePersistedSnapshot(fetchedAt: now))
    context.insert(
      PersistedLocalProfile(
        id: UUID(),
        displayName: "모루",
        selectedVoiceID: VoiceProfile.aoede.id,
        createdAt: now,
        updatedAt: now
      )
    )
    try context.save()

    let repository = SwiftDataLocalDataResetRepository(modelContext: context)
    try repository.resetToFreshInstallState()

    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedLocalProfile>()).isEmpty)
  }

  @MainActor
  func testDiskBackedV1StoreMigratesWithoutLosingProfile() throws {
    let storeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("MoruWeatherMigration-\(UUID().uuidString)")
      .appendingPathExtension("sqlite")
    defer { removeStore(at: storeURL) }

    let profileID = UUID()
    let now = fixtureDate("2026-07-22T09:00:00Z")
    try createV1Store(at: storeURL, profileID: profileID, now: now)

    let migratedContainer = try ModelContainer.moruContainer(storeURL: storeURL)
    let context = migratedContainer.mainContext
    let profiles = try context.fetch(FetchDescriptor<PersistedLocalProfile>())

    XCTAssertEqual(profiles.map(\.id), [profileID])
    XCTAssertEqual(profiles.first?.displayName, "기존 사용자")
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
  }

  @MainActor
  func testWeatherFailureDoesNotPreventRoutineLaunch() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let repository = TestHomeWeatherRepository()
    let service = ControlledHomeWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.failLocation(at: 0, with: .noLocationFix)
    await waitUntil { viewModel.weatherState == .noFix }

    var launchedRoutineID: UUID?
    let boundary = HomeRoutineLaunchBoundary(
      onStartRoutine: { request in
        launchedRoutineID = request.routineID
        return .started
      },
      announceAccessibility: { _ in }
    )
    let routineID = UUID()

    XCTAssertEqual(boundary.start(routineID: routineID), .started)
    XCTAssertEqual(launchedRoutineID, routineID)
    XCTAssertEqual(viewModel.state.loadState, .content)
  }

  @MainActor
  private func makeViewModel(
    repository: any HomeWeatherRepository,
    service: any HomeWeatherService,
    now: Date
  ) -> HomeViewModel {
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeWeatherRoutinesUseCase(),
      weatherRepository: repository,
      weatherService: service,
      now: { now }
    )
    viewModel.load()
    return viewModel
  }

  @MainActor
  private func makeCoreLocationService(
    manager: TestHomeLocationManager,
    scheduler: ManualHomeLocationTimeoutScheduler,
    attributionProvider: HomeWeatherAttributionProvider? = nil,
    attributionAssetLoader: HomeWeatherAttributionAssetLoader? = nil
  ) -> CoreLocationWeatherService {
    CoreLocationWeatherService(
      locationManager: manager,
      weatherService: .shared,
      locationServicesEnabled: { true },
      scheduleLocationTimeout: { duration, action in
        scheduler.schedule(after: duration, action: action)
      },
      weatherAttributionProvider: attributionProvider,
      weatherAttributionAssetLoader: attributionAssetLoader
    )
  }

  @MainActor
  private func assertAttributionUnavailable(
    from service: CoreLocationWeatherService,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await service.weatherAttribution()
      XCTFail("Expected attributionUnavailable.", file: file, line: line)
    } catch let error as HomeWeatherServiceError {
      XCTAssertEqual(error, .attributionUnavailable, file: file, line: line)
    } catch {
      XCTFail("Unexpected attribution error: \(error)", file: file, line: line)
    }
  }

  private func validCurrentLocation() -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9781),
      altitude: 0,
      horizontalAccuracy: 1_000,
      verticalAccuracy: -1,
      timestamp: Date()
    )
  }

  @MainActor
  private func waitUntil(
    _ predicate: @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<100 {
      if predicate() {
        return
      }
      try? await Task.sleep(for: .milliseconds(10))
    }

    XCTFail("Expected weather state was not reached.", file: file, line: line)
  }

  @MainActor
  private func createV1Store(at storeURL: URL, profileID: UUID, now: Date) throws {
    let schema = Schema(versionedSchema: MoruSchemaV1.self)
    let configuration = ModelConfiguration(
      "Moru",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    container.mainContext.insert(
      PersistedLocalProfile(
        id: profileID,
        displayName: "기존 사용자",
        selectedVoiceID: VoiceProfile.aoede.id,
        createdAt: now,
        updatedAt: now
      )
    )
    try container.mainContext.save()
  }

  private var seoulLocation: CLLocation {
    CLLocation(latitude: 37.5666, longitude: 126.9781)
  }

  private func makeSnapshot(
    id: UUID = UUID(),
    fetchedAt: Date
  ) -> HomeWeatherSnapshot {
    HomeWeatherSnapshot(
      id: id,
      condition: .clear,
      temperatureCelsius: 20,
      latitudeE4: 375_666,
      longitudeE4: 1_269_781,
      fetchedAt: fetchedAt,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }

  private func makeWeatherContent(
    _ snapshot: HomeWeatherSnapshot
  ) -> HomeWeatherContent {
    HomeWeatherContent(
      snapshot: snapshot,
      attribution: makeTestWeatherAttribution()
    )
  }

  private func makePersistedSnapshot(
    conditionRawValue: String = HomeWeatherCondition.clear.rawValue,
    fetchedAt: Date
  ) -> PersistedHomeWeatherSnapshot {
    PersistedHomeWeatherSnapshot(
      id: UUID(),
      conditionRawValue: conditionRawValue,
      temperatureCelsius: 20,
      latitudeE4: 375_666,
      longitudeE4: 1_269_781,
      fetchedAt: fetchedAt,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }

  private func fixtureDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  private func removeStore(at storeURL: URL) {
    [
      storeURL,
      URL(fileURLWithPath: storeURL.path + "-shm"),
      URL(fileURLWithPath: storeURL.path + "-wal"),
    ].forEach { try? FileManager.default.removeItem(at: $0) }
  }
}

@MainActor
private final class StaticHomeWeatherRoutinesUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let result = HomeRoutineLoadResult(
    profile: LocalProfile(displayName: "테스트 사용자"),
    todayRoutine: nil,
    manualRoutines: [
      Routine(
        name: "테스트 루틴",
        steps: [RoutineStep(type: .confirm, title: "테스트 스텝", order: 0)]
      ),
    ],
    todayRunsByRoutineID: [:],
    streak: HomeRoutineStreak(currentDays: 0, bestDays: 0, completedWeekdays: [])
  )

  func execute() throws -> HomeRoutineLoadResult {
    result
  }
}

private enum TestHomeWeatherRepositoryError: Error {
  case forcedFailure
}

@MainActor
private final class TestHomeWeatherRepository: HomeWeatherRepository {
  var cachedSnapshot: HomeWeatherSnapshot?
  var failsOnRead: Bool
  var failsOnSave: Bool
  var failsOnErase: Bool
  private(set) var cachedWeatherReadCount = 0
  private(set) var saveWeatherAttemptCount = 0
  private(set) var eraseCachedWeatherCount = 0
  private(set) var savedSnapshots: [HomeWeatherSnapshot] = []

  init(
    cachedSnapshot: HomeWeatherSnapshot? = nil,
    failsOnRead: Bool = false,
    failsOnSave: Bool = false,
    failsOnErase: Bool = false
  ) {
    self.cachedSnapshot = cachedSnapshot
    self.failsOnRead = failsOnRead
    self.failsOnSave = failsOnSave
    self.failsOnErase = failsOnErase
  }

  func cachedWeather() throws -> HomeWeatherSnapshot? {
    cachedWeatherReadCount += 1
    if failsOnRead {
      throw TestHomeWeatherRepositoryError.forcedFailure
    }
    return cachedSnapshot
  }

  func saveWeather(_ snapshot: HomeWeatherSnapshot) throws {
    saveWeatherAttemptCount += 1
    if failsOnSave {
      throw TestHomeWeatherRepositoryError.forcedFailure
    }
    savedSnapshots.append(snapshot)
    cachedSnapshot = snapshot
  }

  func eraseCachedWeather() throws {
    eraseCachedWeatherCount += 1
    if failsOnErase {
      throw TestHomeWeatherRepositoryError.forcedFailure
    }
    cachedSnapshot = nil
  }
}

private final class TestHomeLocationManager: CLLocationManager {
  enum Operation: Equatable {
    case request
    case stop
  }

  var testAuthorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
  private(set) var operations: [Operation] = []

  override var authorizationStatus: CLAuthorizationStatus {
    testAuthorizationStatus
  }

  override func requestLocation() {
    operations.append(.request)
  }

  override func stopUpdatingLocation() {
    operations.append(.stop)
  }

  override func requestWhenInUseAuthorization() {}

  func deliver(_ location: CLLocation) {
    delegate?.locationManager?(self, didUpdateLocations: [location])
  }

  func fail(with error: Error) {
    delegate?.locationManager?(self, didFailWithError: error)
  }
}

@MainActor
private final class ManualHomeLocationTimeoutScheduler {
  private var actions: [@MainActor @Sendable () -> Void] = []

  func schedule(
    after duration: Duration,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> Task<Void, Never> {
    actions.append(action)
    return Task {}
  }

  func fire(at index: Int) {
    guard actions.indices.contains(index) else {
      XCTFail("Missing timeout action at index \(index).")
      return
    }

    actions[index]()
  }
}

@MainActor
private final class ControlledHomeWeatherService: HomeWeatherService {
  var authorizationStatus: HomeWeatherAuthorizationStatus
  private let locationServicesEnabledValue: Bool
  private let attributionError: HomeWeatherServiceError?
  private let automaticallyProvidesAttribution: Bool
  private(set) var authorizationRequestCount = 0
  private(set) var locationRequestCount = 0
  private(set) var weatherRequestCount = 0
  private(set) var attributionRequestCount = 0
  private(set) var cancelLocationRequestCount = 0

  private var authorizationContinuation:
    CheckedContinuation<HomeWeatherAuthorizationStatus, Never>?
  private var locationContinuations: [CheckedContinuation<CLLocation, Error>?] = []
  private var weatherContinuations: [CheckedContinuation<HomeWeatherSnapshot, Error>?] = []
  private var attributionContinuations: [
    CheckedContinuation<HomeWeatherAttribution, Error>?
  ] = []
  private var authorizationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var locationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var weatherWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var attributionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(
    authorizationStatus: HomeWeatherAuthorizationStatus,
    isLocationServiceEnabled: Bool = true,
    attributionError: HomeWeatherServiceError? = nil,
    automaticallyProvidesAttribution: Bool = true
  ) {
    self.authorizationStatus = authorizationStatus
    self.locationServicesEnabledValue = isLocationServiceEnabled
    self.attributionError = attributionError
    self.automaticallyProvidesAttribution = automaticallyProvidesAttribution
  }

  func locationServicesEnabled() async -> Bool {
    locationServicesEnabledValue
  }

  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus {
    authorizationRequestCount += 1
    resumeAuthorizationWaiters()

    return await withCheckedContinuation { continuation in
      authorizationContinuation = continuation
    }
  }

  func currentLocation() async throws -> CLLocation {
    locationRequestCount += 1
    resumeLocationWaiters()

    return try await withCheckedThrowingContinuation { continuation in
      locationContinuations.append(continuation)
    }
  }

  func weatherSnapshot(for location: CLLocation) async throws -> HomeWeatherSnapshot {
    weatherRequestCount += 1
    resumeWeatherWaiters()

    return try await withCheckedThrowingContinuation { continuation in
      weatherContinuations.append(continuation)
    }
  }

  func weatherAttribution() async throws -> HomeWeatherAttribution {
    attributionRequestCount += 1
    resumeAttributionWaiters()
    if let attributionError {
      throw attributionError
    }
    if automaticallyProvidesAttribution {
      return makeTestWeatherAttribution()
    }
    return try await withCheckedThrowingContinuation { continuation in
      attributionContinuations.append(continuation)
    }
  }

  func cancelCurrentLocationRequests() {
    cancelLocationRequestCount += 1
  }

  func waitForAuthorizationRequest(count: Int) async {
    guard authorizationRequestCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      authorizationWaiters.append((count, continuation))
    }
  }

  func waitForLocationRequest(count: Int) async {
    guard locationRequestCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      locationWaiters.append((count, continuation))
    }
  }

  func waitForWeatherRequest(count: Int) async {
    guard weatherRequestCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      weatherWaiters.append((count, continuation))
    }
  }

  func waitForAttributionRequest(count: Int) async {
    guard attributionRequestCount < count else {
      return
    }

    await withCheckedContinuation { continuation in
      attributionWaiters.append((count, continuation))
    }
  }

  func fulfillAuthorization(with status: HomeWeatherAuthorizationStatus) {
    authorizationStatus = status
    let continuation = authorizationContinuation
    authorizationContinuation = nil
    continuation?.resume(returning: status)
  }

  func fulfillLocation(at index: Int, with location: CLLocation) {
    locationContinuation(at: index).resume(returning: location)
  }

  func failLocation(at index: Int, with error: HomeWeatherServiceError) {
    locationContinuation(at: index).resume(throwing: error)
  }

  func fulfillWeather(at index: Int, with snapshot: HomeWeatherSnapshot) {
    weatherContinuation(at: index).resume(returning: snapshot)
  }

  func failWeather(at index: Int, with error: HomeWeatherServiceError) {
    weatherContinuation(at: index).resume(throwing: error)
  }

  func fulfillAttribution(
    at index: Int,
    with attribution: HomeWeatherAttribution
  ) {
    attributionContinuation(at: index).resume(returning: attribution)
  }

  private func locationContinuation(at index: Int) -> CheckedContinuation<CLLocation, Error> {
    guard locationContinuations.indices.contains(index),
          let continuation = locationContinuations[index] else {
      fatalError("Missing controlled location request at index \(index).")
    }
    locationContinuations[index] = nil
    return continuation
  }

  private func weatherContinuation(
    at index: Int
  ) -> CheckedContinuation<HomeWeatherSnapshot, Error> {
    guard weatherContinuations.indices.contains(index),
          let continuation = weatherContinuations[index] else {
      fatalError("Missing controlled weather request at index \(index).")
    }
    weatherContinuations[index] = nil
    return continuation
  }

  private func attributionContinuation(
    at index: Int
  ) -> CheckedContinuation<HomeWeatherAttribution, Error> {
    guard attributionContinuations.indices.contains(index),
          let continuation = attributionContinuations[index] else {
      fatalError("Missing controlled attribution request at index \(index).")
    }
    attributionContinuations[index] = nil
    return continuation
  }

  private func resumeAuthorizationWaiters() {
    let readyWaiters = authorizationWaiters.filter { $0.0 <= authorizationRequestCount }
    authorizationWaiters.removeAll { $0.0 <= authorizationRequestCount }
    readyWaiters.forEach { $0.1.resume() }
  }

  private func resumeLocationWaiters() {
    let readyWaiters = locationWaiters.filter { $0.0 <= locationRequestCount }
    locationWaiters.removeAll { $0.0 <= locationRequestCount }
    readyWaiters.forEach { $0.1.resume() }
  }

  private func resumeWeatherWaiters() {
    let readyWaiters = weatherWaiters.filter { $0.0 <= weatherRequestCount }
    weatherWaiters.removeAll { $0.0 <= weatherRequestCount }
    readyWaiters.forEach { $0.1.resume() }
  }

  private func resumeAttributionWaiters() {
    let readyWaiters = attributionWaiters.filter { $0.0 <= attributionRequestCount }
    attributionWaiters.removeAll { $0.0 <= attributionRequestCount }
    readyWaiters.forEach { $0.1.resume() }
  }
}

@MainActor
private final class TestWeatherAttributionSourceProvider {
  let source: HomeWeatherAttributionSource
  private(set) var requestCount = 0

  init(source: HomeWeatherAttributionSource) {
    self.source = source
  }

  func load() async throws -> HomeWeatherAttributionSource {
    requestCount += 1
    return source
  }
}

private actor TestWeatherAttributionAssetLoader {
  let responseData: Data
  let statusCode: Int
  private(set) var requestCount = 0

  init(responseData: Data, statusCode: Int = 200) {
    self.responseData = responseData
    self.statusCode = statusCode
  }

  func load(_ url: URL) throws -> HomeWeatherAttributionAssetResponse {
    requestCount += 1
    return HomeWeatherAttributionAssetResponse(
      data: responseData,
      statusCode: statusCode,
      finalURL: url
    )
  }
}

nonisolated private func makeTestAttributionSource() -> HomeWeatherAttributionSource {
  HomeWeatherAttributionSource(
    serviceName: "Apple Weather",
    combinedMarkLightURL: URL(string: "https://example.com/light.png")!,
    combinedMarkDarkURL: URL(string: "https://example.com/dark.png")!,
    legalPageURL: URL(
      string: "https://weatherkit.apple.com/legal-attribution.html"
    )!
  )
}

nonisolated private func makeTestWeatherAttribution() -> HomeWeatherAttribution {
  HomeWeatherAttribution(
    serviceName: "Apple Weather",
    combinedMarkLightData: testAttributionPNGData,
    combinedMarkDarkData: testAttributionPNGData,
    legalPageURL: URL(
      string: "https://weatherkit.apple.com/legal-attribution.html"
    )!
  )
}

nonisolated private let testAttributionPNGData = Data(
  base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)!
