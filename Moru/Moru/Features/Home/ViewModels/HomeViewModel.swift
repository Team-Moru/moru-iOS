//
//  HomeViewModel.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
  private let loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol
  private let weatherRepository: (any HomeWeatherRepository)?
  private let weatherService: (any HomeWeatherService)?
  private let now: @Sendable () -> Date
  private var activeWeatherRequestID: UUID?
  private var weatherTask: Task<Void, Never>?

  #if DEBUG
  var onStaleWeatherResultDiscarded: ((UUID) -> Void)?
  #endif

  var state: HomeViewState
  private(set) var weatherState: HomeWeatherState

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol,
    weatherRepository: (any HomeWeatherRepository)? = nil,
    weatherService: (any HomeWeatherService)? = nil,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.weatherRepository = weatherRepository
    self.weatherService = weatherService
    self.now = now
    self.state = .loading(previousContent: nil)
    self.weatherState = .notRequested
  }

  func load() {
    let previousContent = state.routineContent
    state = .loading(previousContent: previousContent)

    do {
      state = makeViewState(from: try loadHomeRoutinesUseCase.execute())
    } catch {
      state = .failed(
        .localRoutineDataUnavailable(diagnostic: String(reflecting: error)),
        previousContent: previousContent
      )
    }
  }

  func retry() {
    load()
  }

  func requestWeather() {
    weatherTask?.cancel()
    weatherService?.cancelCurrentLocationRequests()

    let requestID = UUID()
    activeWeatherRequestID = requestID

    guard weatherRepository != nil, weatherService != nil else {
      apply(weatherState: .unavailable(.unavailableConfiguration), for: requestID)
      return
    }

    weatherTask = Task { [weak self] in
      await self?.loadWeather(requestID: requestID)
    }
  }

  private func loadWeather(requestID: UUID) async {
    guard let weatherRepository, let weatherService else {
      apply(weatherState: .unavailable(.unavailableConfiguration), for: requestID)
      return
    }

    var authorizationStatus = weatherService.authorizationStatus
    if authorizationStatus == .notDetermined {
      guard weatherService.isLocationServiceEnabled else {
        apply(weatherState: .noFix, for: requestID)
        return
      }

      apply(weatherState: .requestingPermission, for: requestID)
      authorizationStatus = await weatherService.requestWhenInUseAuthorization()

      guard isCurrentWeatherRequest(requestID) else {
        return
      }
    }

    switch authorizationStatus {
    case .authorized:
      await loadAuthorizedWeather(
        requestID: requestID,
        weatherRepository: weatherRepository,
        weatherService: weatherService
      )
    case .denied:
      eraseCachedWeatherAndApply(
        .denied,
        requestID: requestID,
        repository: weatherRepository
      )
    case .restricted:
      eraseCachedWeatherAndApply(
        .restricted,
        requestID: requestID,
        repository: weatherRepository
      )
    case .notDetermined:
      apply(weatherState: .noFix, for: requestID)
    }
  }

  private func loadAuthorizedWeather(
    requestID: UUID,
    weatherRepository: any HomeWeatherRepository,
    weatherService: any HomeWeatherService
  ) async {
    let cachedWeather: HomeWeatherSnapshot?
    do {
      cachedWeather = try weatherRepository.cachedWeather()
    } catch {
      apply(weatherState: .unavailable(.cacheReadFailed), for: requestID)
      return
    }

    guard weatherService.isLocationServiceEnabled else {
      applyCachedWeatherOrNoFix(cachedWeather, for: requestID)
      return
    }

    apply(weatherState: .locating(requestID), for: requestID)

    let location: CLLocation
    do {
      location = try await weatherService.currentLocation()
    } catch is CancellationError {
      return
    } catch let error as HomeWeatherServiceError {
      handleLocationError(
        error,
        cachedWeather: cachedWeather,
        requestID: requestID,
        repository: weatherRepository
      )
      return
    } catch {
      applyCachedWeatherOrNoFix(cachedWeather, for: requestID)
      return
    }

    guard isCurrentWeatherRequest(requestID) else {
      return
    }

    let usableCachedWeather: HomeWeatherSnapshot?
    if let cachedWeather, isWithinMaximumCacheDistance(cachedWeather, of: location) {
      usableCachedWeather = cachedWeather
    } else if cachedWeather != nil {
      do {
        try weatherRepository.eraseCachedWeather()
      } catch {
        apply(weatherState: .unavailable(.cacheEraseFailed), for: requestID)
        return
      }
      usableCachedWeather = nil
    } else {
      usableCachedWeather = nil
    }

    apply(weatherState: .loading(requestID), for: requestID)

    do {
      let snapshot = try await weatherService.weatherSnapshot(for: location)

      guard isCurrentWeatherRequest(requestID) else {
        #if DEBUG
        onStaleWeatherResultDiscarded?(requestID)
        #endif
        return
      }

      do {
        try weatherRepository.saveWeather(snapshot)
      } catch {
        apply(weatherState: .unavailable(.cacheWriteFailed), for: requestID)
        return
      }

      apply(weatherState: .fresh(snapshot), for: requestID)
    } catch is CancellationError {
      return
    } catch let error as HomeWeatherServiceError {
      if let usableCachedWeather {
        apply(weatherState: cacheState(for: usableCachedWeather), for: requestID)
      } else {
        apply(weatherState: .unavailable(.service(error)), for: requestID)
      }
    } catch {
      if let usableCachedWeather {
        apply(weatherState: cacheState(for: usableCachedWeather), for: requestID)
      } else {
        apply(
          weatherState: .unavailable(.service(.weatherUnavailable)),
          for: requestID
        )
      }
    }
  }

  private func handleLocationError(
    _ error: HomeWeatherServiceError,
    cachedWeather: HomeWeatherSnapshot?,
    requestID: UUID,
    repository: any HomeWeatherRepository
  ) {
    guard isCurrentWeatherRequest(requestID) else {
      return
    }

    switch error {
    case .authorizationDenied:
      eraseCachedWeatherAndApply(.denied, requestID: requestID, repository: repository)
    case .authorizationRestricted:
      eraseCachedWeatherAndApply(
        .restricted,
        requestID: requestID,
        repository: repository
      )
    case .locationServicesDisabled, .noLocationFix:
      applyCachedWeatherOrNoFix(cachedWeather, for: requestID)
    case .weatherUnavailable, .invalidWeatherData:
      apply(weatherState: .unavailable(.service(error)), for: requestID)
    }
  }

  private func applyCachedWeatherOrNoFix(
    _ cachedWeather: HomeWeatherSnapshot?,
    for requestID: UUID
  ) {
    if let cachedWeather {
      apply(weatherState: cacheState(for: cachedWeather), for: requestID)
    } else {
      apply(weatherState: .noFix, for: requestID)
    }
  }

  private func eraseCachedWeatherAndApply(
    _ weatherState: HomeWeatherState,
    requestID: UUID,
    repository: any HomeWeatherRepository
  ) {
    guard isCurrentWeatherRequest(requestID) else {
      return
    }

    do {
      try repository.eraseCachedWeather()
      apply(weatherState: weatherState, for: requestID)
    } catch {
      apply(weatherState: .unavailable(.cacheEraseFailed), for: requestID)
    }
  }

  private func cacheState(for snapshot: HomeWeatherSnapshot) -> HomeWeatherState {
    let freshnessInterval: TimeInterval = 30 * 60
    let age = now().timeIntervalSince(snapshot.fetchedAt)
    return age <= freshnessInterval ? .fresh(snapshot) : .stale(snapshot)
  }

  private func isWithinMaximumCacheDistance(
    _ snapshot: HomeWeatherSnapshot,
    of location: CLLocation
  ) -> Bool {
    let earthRadiusMeters = 6_371_000.0
    let cachedLatitude = Double(snapshot.latitudeE4) / 10_000
    let cachedLongitude = Double(snapshot.longitudeE4) / 10_000
    let currentLatitude = location.coordinate.latitude
    let currentLongitude = location.coordinate.longitude
    let latitudeDelta = (currentLatitude - cachedLatitude) * .pi / 180
    let longitudeDelta = (currentLongitude - cachedLongitude) * .pi / 180
    let cachedLatitudeRadians = cachedLatitude * .pi / 180
    let currentLatitudeRadians = currentLatitude * .pi / 180
    let haversine = pow(sin(latitudeDelta / 2), 2)
      + cos(cachedLatitudeRadians)
      * cos(currentLatitudeRadians)
      * pow(sin(longitudeDelta / 2), 2)
    let boundedHaversine = min(max(haversine, 0), 1)
    let distance = 2 * earthRadiusMeters * atan2(
      sqrt(boundedHaversine),
      sqrt(1 - boundedHaversine)
    )

    return distance <= 2_000
  }

  private func isCurrentWeatherRequest(_ requestID: UUID) -> Bool {
    activeWeatherRequestID == requestID && !Task.isCancelled
  }

  private func apply(weatherState: HomeWeatherState, for requestID: UUID) {
    guard isCurrentWeatherRequest(requestID) else {
      return
    }

    self.weatherState = weatherState
    switch state {
    case .loading(var previousContent):
      previousContent?.weather = weatherState
      state = .loading(previousContent: previousContent)
    case .content(var content):
      content.weather = weatherState
      state = .content(content)
    case .empty(var content):
      content.weather = weatherState
      state = .empty(content)
    case .failed(let failure, var previousContent):
      previousContent?.weather = weatherState
      state = .failed(failure, previousContent: previousContent)
    }
  }

  private func makeViewState(from result: HomeRoutineLoadResult) -> HomeViewState {
    let todayRoutineState = result.todayRoutine.map { routine in
      makeRoutineState(routine: routine, todayRun: result.todayRun)
    }
    let manualRoutines = result.manualRoutines.map { routine in
      let todayRun = routine.id == result.todayRoutine?.id ? result.todayRun : nil
      return makeRoutineState(routine: routine, todayRun: todayRun)
    }
    let content = HomeContentState(
      userName: result.profile?.displayName ?? "",
      todayRoutine: todayRoutineState,
      manualRoutines: manualRoutines,
      todayProgress: makeProgressState(
        routine: result.todayRoutine,
        todayRun: result.todayRun
      ),
      streak: HomeStreakState(
        currentDays: result.streak.currentDays,
        bestDays: result.streak.bestDays,
        weekdays: makeWeekdayStates(
          completedWeekdays: result.streak.completedWeekdays
        )
      ),
      weather: weatherState
    )

    return manualRoutines.isEmpty ? .empty(content) : .content(content)
  }

  private func makeWeekdayStates(completedWeekdays: Set<Weekday>) -> [HomeWeekdayState] {
    let completedIDs = Set(completedWeekdays.map(weekdayID))
    return HomeWeekdayState.ordered(completedIDs: completedIDs)
  }

  private func weekdayID(_ weekday: Weekday) -> String {
    switch weekday {
    case .monday:
      "monday"
    case .tuesday:
      "tuesday"
    case .wednesday:
      "wednesday"
    case .thursday:
      "thursday"
    case .friday:
      "friday"
    case .saturday:
      "saturday"
    case .sunday:
      "sunday"
    }
  }

  private func makeProgressState(
    routine: Routine?,
    todayRun: RoutineRun?
  ) -> HomeProgressState {
    guard let routine else {
      return .empty
    }

    let steps = plannedSteps(for: routine, todayRun: todayRun)
    let completed = completedStepCount(steps: steps, todayRun: todayRun)
    let progress = progress(completed: completed, total: steps.count)

    return HomeProgressState(
      percentText: "\(Int((progress * 100).rounded()))%",
      completedText: "\(completed)/\(steps.count) 완료",
      progress: progress
    )
  }

  private func makeRoutineState(
    routine: Routine,
    todayRun: RoutineRun?
  ) -> HomeRoutineState {
    let steps = plannedSteps(for: routine, todayRun: todayRun)
    let completedStepIDs = Set(todayRun?.results.filter(\.isCompleted).map(\.stepID) ?? [])
    let completed = completedStepCount(steps: steps, todayRun: todayRun)
    let progress = progress(completed: completed, total: steps.count)

    return HomeRoutineState(
      id: routine.id,
      title: routine.name,
      statusText: progress >= 1 ? "진행 완료" : "진행 전",
      estimatedDurationText: "소요 시간 \(estimatedMinutes(for: steps))분",
      progressText: "\(Int((progress * 100).rounded()))%",
      progress: progress,
      steps: steps.map { step in
        HomeRoutineStepState(
          id: step.stepID,
          title: step.stepTitle,
          detail: stepDurationText(step),
          isCompleted: completedStepIDs.contains(step.stepID)
        )
      }
    )
  }

  private func plannedSteps(for routine: Routine, todayRun: RoutineRun?) -> [RoutineStepSnapshot] {
    if let todayRun {
      return todayRun.plannedSteps.sorted { $0.stepOrder < $1.stepOrder }
    }

    return routine.steps
      .sorted { $0.order < $1.order }
      .map(RoutineStepSnapshot.init)
  }

  private func completedStepCount(
    steps: [RoutineStepSnapshot],
    todayRun: RoutineRun?
  ) -> Int {
    let completedStepIDs = Set(todayRun?.results.filter(\.isCompleted).map(\.stepID) ?? [])
    return steps.filter { completedStepIDs.contains($0.stepID) }.count
  }

  private func progress(completed: Int, total: Int) -> Double {
    guard total > 0 else {
      return 0
    }

    return Double(completed) / Double(total)
  }

  private func estimatedMinutes(for steps: [RoutineStepSnapshot]) -> Int {
    let seconds = steps.compactMap(\.estimatedSeconds).reduce(0, +)

    guard seconds > 0 else {
      return max(steps.count * 3, 1)
    }

    return max(Int(ceil(Double(seconds) / 60)), 1)
  }

  private func stepDurationText(_ step: RoutineStepSnapshot) -> String {
    guard let seconds = step.estimatedSeconds else {
      return "-"
    }

    let minutes = seconds / 60
    let remainder = seconds % 60

    return "\(minutes):\(String(format: "%02d", remainder))"
  }
}
