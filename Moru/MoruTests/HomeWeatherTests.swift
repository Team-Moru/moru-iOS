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
  func testWeatherStaysOptInUntilExplicitRequest() {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let repository = TestHomeWeatherRepository(
      cachedSnapshot: makeSnapshot(fetchedAt: now)
    )
    let service = ControlledHomeWeatherService(authorizationStatus: .notDetermined)
    let viewModel = makeViewModel(repository: repository, service: service, now: now)

    XCTAssertEqual(viewModel.weatherState, .notRequested)
    XCTAssertEqual(viewModel.state.routineContent?.weather, .notRequested)
    XCTAssertEqual(service.authorizationRequestCount, 0)
    XCTAssertEqual(service.locationRequestCount, 0)
    XCTAssertEqual(service.weatherRequestCount, 0)
    XCTAssertEqual(repository.cachedWeatherReadCount, 0)
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
    await waitUntil { viewModel.weatherState == .fresh(snapshot) }

    XCTAssertEqual(repository.savedSnapshots, [snapshot])
    XCTAssertEqual(viewModel.state.routineContent?.weather, .fresh(snapshot))
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
  func testLocationFailureUsesFreshAndStaleCacheWithoutBlockingHome() async {
    let now = fixtureDate("2026-07-22T09:00:00Z")
    let cases: [(TimeInterval, (HomeWeatherSnapshot) -> HomeWeatherState)] = [
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
      await waitUntil { viewModel.weatherState == expectedState(snapshot) }

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
    await waitUntil { nearbyViewModel.weatherState == .stale(snapshot) }

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
    await waitUntil { viewModel.weatherState == .fresh(secondSnapshot) }

    service.fulfillWeather(at: 0, with: firstSnapshot)
    #if DEBUG
    await fulfillment(of: [staleResultDiscarded], timeout: 1)
    #endif

    XCTAssertEqual(repository.savedSnapshots, [secondSnapshot])
    XCTAssertEqual(viewModel.weatherState, .fresh(secondSnapshot))
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
        selectedVoiceID: VoiceProfile.yuna.id,
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
        selectedVoiceID: VoiceProfile.yuna.id,
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
    todayRun: nil,
    streak: HomeRoutineStreak(currentDays: 0, bestDays: 0, completedWeekdays: [])
  )

  func execute() throws -> HomeRoutineLoadResult {
    result
  }
}

@MainActor
private final class TestHomeWeatherRepository: HomeWeatherRepository {
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

@MainActor
private final class ControlledHomeWeatherService: HomeWeatherService {
  var authorizationStatus: HomeWeatherAuthorizationStatus
  let isLocationServiceEnabled: Bool
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

  func cancelCurrentLocationRequests() {}

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
