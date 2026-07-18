//
//  WeatherTests.swift
//  MoruTests
//

import CoreLocation
import Foundation
import SwiftData
import WeatherKit
import XCTest
@testable import Moru

final class WeatherTests: XCTestCase {
  @MainActor
  func testWeatherStaysOptInUntilAnExplicitRequest() {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let repository = TestWeatherRepository(cachedSnapshot: makeSnapshot(fetchedAt: now))
    let service = ControlledWeatherService(authorizationStatus: .notDetermined)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    XCTAssertEqual(viewModel.weatherState, .notRequested)
    XCTAssertEqual(viewModel.state.routineContent?.weather, .notRequested)
    XCTAssertEqual(service.authorizationRequestCount, 0)
    XCTAssertEqual(service.locationRequestCount, 0)
    XCTAssertEqual(service.weatherRequestCount, 0)
    XCTAssertEqual(repository.cachedWeatherReadCount, 0)
  }
  func testWeatherConditionMappingCoversPinnedCurrentSDKConditions() {
    let mappings: [(WeatherCondition, HomeWeatherCondition)] = [
      (.blizzard, .snow),
      (.blowingDust, .fog),
      (.blowingSnow, .snow),
      (.breezy, .wind),
      (.clear, .clear),
      (.cloudy, .cloudy),
      (.drizzle, .rain),
      (.foggy, .fog),
      (.freezingDrizzle, .rain),
      (.freezingRain, .rain),
      (.flurries, .snow),
      (.frigid, .other),
      (.hail, .mixed),
      (.haze, .fog),
      (.heavyRain, .rain),
      (.heavySnow, .snow),
      (.hot, .other),
      (.hurricane, .wind),
      (.isolatedThunderstorms, .thunderstorm),
      (.mostlyClear, .clear),
      (.mostlyCloudy, .cloudy),
      (.partlyCloudy, .cloudy),
      (.rain, .rain),
      (.scatteredThunderstorms, .thunderstorm),
      (.sleet, .mixed),
      (.smoky, .fog),
      (.snow, .snow),
      (.strongStorms, .thunderstorm),
      (.sunFlurries, .snow),
      (.sunShowers, .rain),
      (.thunderstorms, .thunderstorm),
      (.tropicalStorm, .thunderstorm),
      (.windy, .wind),
      (.wintryMix, .mixed),
    ]

    for (condition, expected) in mappings {
      XCTAssertEqual(CoreLocationWeatherService.condition(for: condition), expected)
    }
  }

  func testCurrentLocationFixRequiresFiniteAccuracyAndRequestRecency() {
    let requestedAt = fixtureDate("2026-07-18T09:00:00Z")
    let now = requestedAt.addingTimeInterval(1)
    let coordinate = CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9781)
    let validFix = CLLocation(
      coordinate: coordinate,
      altitude: 0,
      horizontalAccuracy: 10,
      verticalAccuracy: 10,
      timestamp: requestedAt.addingTimeInterval(-5)
    )
    let staleFix = CLLocation(
      coordinate: coordinate,
      altitude: 0,
      horizontalAccuracy: 10,
      verticalAccuracy: 10,
      timestamp: requestedAt.addingTimeInterval(-5.001)
    )
    let infiniteAccuracyFix = CLLocation(
      coordinate: coordinate,
      altitude: 0,
      horizontalAccuracy: .infinity,
      verticalAccuracy: 10,
      timestamp: requestedAt
    )
    let futureFix = CLLocation(
      coordinate: coordinate,
      altitude: 0,
      horizontalAccuracy: 10,
      verticalAccuracy: 10,
      timestamp: now.addingTimeInterval(5.001)
    )

    XCTAssertTrue(
      CoreLocationWeatherService.isValidLocationFix(
        validFix,
        requestedAt: requestedAt,
        now: now
      )
    )
    XCTAssertFalse(
      CoreLocationWeatherService.isValidLocationFix(
        staleFix,
        requestedAt: requestedAt,
        now: now
      )
    )
    XCTAssertFalse(
      CoreLocationWeatherService.isValidLocationFix(
        infiniteAccuracyFix,
        requestedAt: requestedAt,
        now: now
      )
    )
    XCTAssertFalse(
      CoreLocationWeatherService.isValidLocationFix(
        futureFix,
        requestedAt: requestedAt,
        now: now
      )
    )
    XCTAssertFalse(
      CoreLocationWeatherService.isValidLocationFix(
        validFix,
        requestedAt: nil,
        now: now
      )
    )
  }

  @MainActor
  func testAuthorizedRequestTransitionsFromPermissionToFixToFreshWeather() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now)
    let repository = TestWeatherRepository()
    let service = ControlledWeatherService(authorizationStatus: .notDetermined)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()

    await service.waitForAuthorizationRequest(count: 1)
    XCTAssertEqual(viewModel.weatherState, .requestingPermission)
    XCTAssertEqual(viewModel.state.routineContent?.weather, .requestingPermission)

    service.fulfillAuthorization(with: .authorized)
    await service.waitForLocationRequest(count: 1)
    guard case .locating(let locatingRequestID) = viewModel.weatherState else {
      return XCTFail("Expected the authorized request to locate the current position.")
    }
    XCTAssertEqual(viewModel.state.routineContent?.weather, .locating(locatingRequestID))

    service.fulfillLocation(
      at: 0,
      with: CLLocation(latitude: 37.5666, longitude: 126.9781)
    )
    await service.waitForWeatherRequest(count: 1)
    guard case .loading(let loadingRequestID) = viewModel.weatherState else {
      return XCTFail("Expected a valid location fix to start the weather fetch.")
    }
    XCTAssertEqual(loadingRequestID, locatingRequestID)
    XCTAssertEqual(viewModel.state.routineContent?.weather, .loading(locatingRequestID))

    service.fulfillWeather(at: 0, with: snapshot)
    await waitUntil { viewModel.weatherState == .fresh(snapshot) }

    XCTAssertEqual(viewModel.state.routineContent?.weather, .fresh(snapshot))
    XCTAssertEqual(repository.savedSnapshots, [snapshot])
    XCTAssertEqual(
      service.calls,
      [.cancelCurrentLocationRequests, .authorizationRequest, .currentLocation, .weatherSnapshot]
    )
  }

  @MainActor
  func testPromptReturnedDeniedAndRestrictedStatusesEraseCachedWeather() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let cases: [(HomeWeatherAuthorizationStatus, HomeWeatherState)] = [
      (.denied, .denied),
      (.restricted, .restricted),
    ]

    for (authorizationStatus, expectedState) in cases {
      let snapshot = makeSnapshot(fetchedAt: now)
      let repository = TestWeatherRepository(cachedSnapshot: snapshot)
      let service = ControlledWeatherService(authorizationStatus: .notDetermined)
      let viewModel = makeViewModel(repository: repository, service: service, now: now)

      viewModel.requestWeather()

      await service.waitForAuthorizationRequest(count: 1)
      XCTAssertEqual(viewModel.weatherState, .requestingPermission)

      service.fulfillAuthorization(with: authorizationStatus)
      await waitUntil { viewModel.weatherState == expectedState }

      XCTAssertEqual(viewModel.state.routineContent?.weather, expectedState)
      XCTAssertNil(repository.cachedSnapshot)
      XCTAssertEqual(repository.eraseCachedWeatherCount, 1)
      XCTAssertEqual(service.authorizationRequestCount, 1)
      XCTAssertEqual(service.locationRequestCount, 0)
      XCTAssertEqual(service.weatherRequestCount, 0)
    }
  }

  @MainActor
  func testDisabledLocationServicesStopsAtNoFixWithoutLocationOrWeatherRequests() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-30 * 60))
    let repository = TestWeatherRepository(cachedSnapshot: snapshot)
    let service = ControlledWeatherService(
      authorizationStatus: .authorized,
      isLocationServiceEnabled: false
    )
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await waitUntil { viewModel.weatherState == .noFix }

    XCTAssertEqual(viewModel.state.routineContent?.weather, .noFix)
    XCTAssertEqual(repository.cachedSnapshot, snapshot)
    XCTAssertEqual(repository.cachedWeatherReadCount, 0)
    XCTAssertEqual(repository.eraseCachedWeatherCount, 0)
    XCTAssertEqual(service.authorizationRequestCount, 0)
    XCTAssertEqual(service.locationRequestCount, 0)
    XCTAssertEqual(service.weatherRequestCount, 0)
  }

  @MainActor
  func testNoFixUsesCacheOnlyAtTheThirtyMinuteFreshnessBoundary() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-30 * 60))
    let repository = TestWeatherRepository(cachedSnapshot: snapshot)
    let service = ControlledWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.failLocation(at: 0, with: .noLocationFix)
    await waitUntil { viewModel.weatherState == .fresh(snapshot) }

    XCTAssertEqual(viewModel.state.routineContent?.weather, .fresh(snapshot))
    XCTAssertEqual(service.weatherRequestCount, 0)
    XCTAssertEqual(repository.eraseCachedWeatherCount, 0)
  }

  @MainActor
  func testNoFixDoesNotUseCacheOlderThanThirtyMinutes() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-(30 * 60 + 1)))
    let repository = TestWeatherRepository(cachedSnapshot: snapshot)
    let service = ControlledWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.failLocation(at: 0, with: .noLocationFix)
    await waitUntil { viewModel.weatherState == .noFix }

    XCTAssertEqual(viewModel.state.routineContent?.weather, .noFix)
    XCTAssertEqual(service.weatherRequestCount, 0)
    XCTAssertEqual(repository.cachedSnapshot, snapshot)
  }

  @MainActor
  func testWeatherFailureUsesAValidCachedFallbackWithinTwoKilometers() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-24 * 60 * 60))
    let repository = TestWeatherRepository(cachedSnapshot: snapshot)
    let service = ControlledWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(
      at: 0,
      with: CLLocation(latitude: 37.5666, longitude: 126.9781)
    )
    await service.waitForWeatherRequest(count: 1)
    service.failWeather(at: 0, with: .weatherUnavailable)
    await waitUntil { viewModel.weatherState == .stale(snapshot) }

    XCTAssertEqual(viewModel.state.routineContent?.weather, .stale(snapshot))
    XCTAssertEqual(repository.eraseCachedWeatherCount, 0)
    XCTAssertEqual(repository.savedSnapshots, [])
  }

  @MainActor
  func testDistantCachedWeatherIsErasedBeforeWeatherFailure() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let snapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-5 * 60))
    let repository = TestWeatherRepository(cachedSnapshot: snapshot)
    let service = ControlledWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(
      at: 0,
      with: CLLocation(latitude: 37.5665, longitude: 127.0080)
    )
    await service.waitForWeatherRequest(count: 1)

    guard case .loading = viewModel.weatherState else {
      return XCTFail("Expected the request to fetch after invalidating the distant cache.")
    }
    XCTAssertNil(repository.cachedSnapshot)
    XCTAssertEqual(repository.eraseCachedWeatherCount, 1)

    service.failWeather(at: 0, with: .weatherUnavailable)
    await waitUntil {
      viewModel.weatherState == .unavailable(.service(.weatherUnavailable))
    }

    XCTAssertEqual(
      viewModel.state.routineContent?.weather,
      .unavailable(.service(.weatherUnavailable))
    )
  }

  @MainActor
  func testOnlyTheCurrentOverlappingRequestWritesAndRendersWeather() async {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let firstSnapshot = makeSnapshot(
      id: fixtureUUID("00000000-0000-0000-0000-000000000001"),
      fetchedAt: now
    )
    let secondSnapshot = makeSnapshot(
      id: fixtureUUID("00000000-0000-0000-0000-000000000002"),
      fetchedAt: now
    )
    let repository = TestWeatherRepository()
    let service = ControlledWeatherService(authorizationStatus: .authorized)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)
    let location = CLLocation(latitude: 37.5666, longitude: 126.9781)

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 1)
    service.fulfillLocation(at: 0, with: location)
    await service.waitForWeatherRequest(count: 1)

    guard case .loading(let firstRequestID) = viewModel.weatherState else {
      return XCTFail("Expected the first request to start the weather fetch.")
    }

#if DEBUG
    let staleWeatherResultDiscarded = expectation(
      description: "The stale first weather result is discarded."
    )
    viewModel.onStaleWeatherResultDiscarded = { requestID in
      XCTAssertEqual(requestID, firstRequestID)
      staleWeatherResultDiscarded.fulfill()
    }
#endif

    viewModel.requestWeather()
    await service.waitForLocationRequest(count: 2)
    service.fulfillLocation(at: 1, with: location)
    await service.waitForWeatherRequest(count: 2)

    service.fulfillWeather(at: 1, with: secondSnapshot)
    await waitUntil { viewModel.weatherState == .fresh(secondSnapshot) }

    service.fulfillWeather(at: 0, with: firstSnapshot)
#if DEBUG
    await fulfillment(of: [staleWeatherResultDiscarded], timeout: 1)
#else
    XCTFail("Stale-result processing signals are only available in DEBUG test builds.")
#endif

    XCTAssertEqual(repository.savedSnapshots, [secondSnapshot])
    XCTAssertEqual(repository.cachedSnapshot, secondSnapshot)
    XCTAssertEqual(viewModel.weatherState, .fresh(secondSnapshot))
    XCTAssertEqual(viewModel.state.routineContent?.weather, .fresh(secondSnapshot))
  }

  @MainActor
  func testSwiftDataWeatherRepositoryKeepsValidCacheBoundarySnapshots() throws {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let repository = SwiftDataHomeWeatherRepository(
      modelContext: container.mainContext,
      now: { now }
    )
    let freshSnapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-30 * 60))
    let staleSnapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(-24 * 60 * 60))
    let approvedFutureSnapshot = makeSnapshot(fetchedAt: now.addingTimeInterval(5 * 60))

    try repository.saveWeather(freshSnapshot)
    XCTAssertEqual(try repository.cachedWeather(), freshSnapshot)

    try repository.saveWeather(staleSnapshot)
    XCTAssertEqual(try repository.cachedWeather(), staleSnapshot)

    try repository.saveWeather(approvedFutureSnapshot)
    XCTAssertEqual(try repository.cachedWeather(), approvedFutureSnapshot)

    XCTAssertThrowsError(
      try repository.saveWeather(
        makeSnapshot(fetchedAt: now.addingTimeInterval(-24 * 60 * 60 - 1))
      )
    ) { error in
      XCTAssertEqual(error as? HomeWeatherRepositoryError, .invalidCachedSnapshot)
    }
    XCTAssertThrowsError(
      try repository.saveWeather(makeSnapshot(fetchedAt: now.addingTimeInterval(5 * 60 + 1)))
    )
    XCTAssertEqual(try repository.cachedWeather(), approvedFutureSnapshot)
  }

  @MainActor
  func testSwiftDataWeatherRepositoryErasesStoredSnapshotWithUnknownCondition() throws {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataHomeWeatherRepository(modelContext: context, now: { now })

    context.insert(
      makePersistedWeatherSnapshot(conditionRawValue: "unknown", fetchedAt: now)
    )
    try context.save()

    XCTAssertNil(try repository.cachedWeather())
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
  }

  @MainActor
  func testSwiftDataWeatherRepositoryErasesStoredSnapshotOlderThanCacheLifetime() throws {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataHomeWeatherRepository(modelContext: context, now: { now })

    context.insert(
      makePersistedWeatherSnapshot(
        fetchedAt: now.addingTimeInterval(-24 * 60 * 60 - 1)
      )
    )
    try context.save()

    XCTAssertNil(try repository.cachedWeather())
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
  }

  @MainActor
  func testSwiftDataWeatherRepositoryErasesStoredSnapshotBeyondFutureTolerance() throws {
    let now = fixtureDate("2026-07-18T09:00:00Z")
    let container = try ModelContainer.moruContainer(isStoredInMemoryOnly: true)
    let context = container.mainContext
    let repository = SwiftDataHomeWeatherRepository(modelContext: context, now: { now })

    context.insert(
      makePersistedWeatherSnapshot(fetchedAt: now.addingTimeInterval(5 * 60 + 1))
    )
    try context.save()

    XCTAssertNil(try repository.cachedWeather())
    XCTAssertTrue(try context.fetch(FetchDescriptor<PersistedHomeWeatherSnapshot>()).isEmpty)
  }

  @MainActor
  private func makeViewModel(
    repository: any HomeWeatherRepository,
    service: any HomeWeatherService,
    now: Date
  ) -> HomeViewModel {
    let viewModel = HomeViewModel(
      loadHomeRoutinesUseCase: StaticHomeRoutinesUseCase(),
      weatherRepository: repository,
      weatherService: service,
      now: { now }
    )
    viewModel.load()
    return viewModel
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

    XCTFail("The expected weather state was not reached.", file: file, line: line)
  }

  private func makeSnapshot(
    id: UUID = UUID(),
    fetchedAt: Date
  ) -> HomeWeatherSnapshot {
    HomeWeatherSnapshot(
      id: id,
      condition: .clear,
      temperatureCelsius: 20,
      latitudeE4: 375_665,
      longitudeE4: 1_269_780,
      fetchedAt: fetchedAt,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }
  private func makePersistedWeatherSnapshot(
    conditionRawValue: String = HomeWeatherCondition.clear.rawValue,
    fetchedAt: Date
  ) -> PersistedHomeWeatherSnapshot {
    PersistedHomeWeatherSnapshot(
      id: UUID(),
      conditionRawValue: conditionRawValue,
      temperatureCelsius: 20,
      latitudeE4: 375_665,
      longitudeE4: 1_269_780,
      fetchedAt: fetchedAt,
      fetchedTimeZoneIdentifier: "Asia/Seoul",
      fetchedUTCOffsetSeconds: 32_400
    )
  }

  private func fixtureDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  private func fixtureUUID(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }
}

@MainActor
private final class StaticHomeRoutinesUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let result = HomeRoutineLoadResult(
    profile: LocalProfile(displayName: "테스트 사용자"),
    todayRoutine: nil,
    manualRoutines: [
      Routine(
        name: "테스트 루틴",
        steps: [RoutineStep(type: .confirm, title: "테스트 스텝", order: 0)]
      ),
    ],
    todayRun: nil,
    streak: HomeRoutineStreak(currentDays: 0, bestDays: 0, completedWeekdays: [])
  )

  func execute() throws -> HomeRoutineLoadResult {
    result
  }
}

@MainActor
private final class TestWeatherRepository: HomeWeatherRepository {
  var cachedSnapshot: HomeWeatherSnapshot?
  private(set) var cachedWeatherReadCount = 0
  private(set) var eraseCachedWeatherCount = 0
  private(set) var savedSnapshots: [HomeWeatherSnapshot] = []

  init(cachedSnapshot: HomeWeatherSnapshot? = nil) {
    self.cachedSnapshot = cachedSnapshot
  }

  func cachedWeather() throws -> HomeWeatherSnapshot? {
    cachedWeatherReadCount += 1
    return cachedSnapshot
  }

  func saveWeather(_ snapshot: HomeWeatherSnapshot) throws {
    savedSnapshots.append(snapshot)
    cachedSnapshot = snapshot
  }

  func eraseCachedWeather() throws {
    eraseCachedWeatherCount += 1
    cachedSnapshot = nil
  }
}

private enum WeatherServiceCall: Equatable {
  case authorizationRequest
  case currentLocation
  case weatherSnapshot
  case cancelCurrentLocationRequests
}

@MainActor
private final class ControlledWeatherService: HomeWeatherService {
  var authorizationStatus: HomeWeatherAuthorizationStatus
  let isLocationServiceEnabled: Bool
  private(set) var calls: [WeatherServiceCall] = []
  private(set) var authorizationRequestCount = 0
  private(set) var locationRequestCount = 0
  private(set) var weatherRequestCount = 0

  private var authorizationContinuation:
    CheckedContinuation<HomeWeatherAuthorizationStatus, Never>?
  private var locationContinuations: [CheckedContinuation<CLLocation, Error>?] = []
  private var weatherContinuations: [CheckedContinuation<HomeWeatherSnapshot, Error>?] = []
  private var authorizationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var locationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var weatherWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(
    authorizationStatus: HomeWeatherAuthorizationStatus,
    isLocationServiceEnabled: Bool = true
  ) {
    self.authorizationStatus = authorizationStatus
    self.isLocationServiceEnabled = isLocationServiceEnabled
  }

  func requestWhenInUseAuthorization() async -> HomeWeatherAuthorizationStatus {
    calls.append(.authorizationRequest)
    authorizationRequestCount += 1
    resumeAuthorizationWaiters()

    return await withCheckedContinuation { continuation in
      authorizationContinuation = continuation
    }
  }

  func currentLocation() async throws -> CLLocation {
    calls.append(.currentLocation)
    locationRequestCount += 1
    resumeLocationWaiters()

    return try await withCheckedThrowingContinuation { continuation in
      locationContinuations.append(continuation)
    }
  }

  func weatherSnapshot(for location: CLLocation) async throws -> HomeWeatherSnapshot {
    calls.append(.weatherSnapshot)
    weatherRequestCount += 1
    resumeWeatherWaiters()

    return try await withCheckedThrowingContinuation { continuation in
      weatherContinuations.append(continuation)
    }
  }

  func cancelCurrentLocationRequests() {
    calls.append(.cancelCurrentLocationRequests)
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

  func fulfillAuthorization(with status: HomeWeatherAuthorizationStatus) {
    authorizationStatus = status
    let continuation = authorizationContinuation
    authorizationContinuation = nil
    continuation?.resume(returning: status)
  }

  func fulfillLocation(at index: Int, with location: CLLocation) {
    let continuation = locationContinuation(at: index)
    continuation.resume(returning: location)
  }

  func failLocation(at index: Int, with error: HomeWeatherServiceError) {
    let continuation = locationContinuation(at: index)
    continuation.resume(throwing: error)
  }

  func fulfillWeather(at index: Int, with snapshot: HomeWeatherSnapshot) {
    let continuation = weatherContinuation(at: index)
    continuation.resume(returning: snapshot)
  }

  func failWeather(at index: Int, with error: HomeWeatherServiceError) {
    let continuation = weatherContinuation(at: index)
    continuation.resume(throwing: error)
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
}
