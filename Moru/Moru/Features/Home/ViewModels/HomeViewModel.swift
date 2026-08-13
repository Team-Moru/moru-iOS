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
  private let enrichHomeRoutinesUseCase:
    (any EnrichHomeRoutinesUseCaseProtocol)?
  private let weatherRepository: (any HomeWeatherRepository)?
  private let weatherService: (any HomeWeatherService)?
  private let now: @Sendable () -> Date
  private var activeWeatherRequestID: UUID?
  private var weatherTask: Task<Void, Never>?
  private var isWeatherRequestInProgress = false
  private var routineServerTask: Task<Void, Never>?
  private var routineServerRequestID: UUID?

  #if DEBUG
  var onStaleWeatherResultDiscarded: ((UUID) -> Void)?
  var onStaleRoutineServerResultDiscarded: (() -> Void)?
  #endif

  var state: HomeViewState
  private(set) var weatherState: HomeWeatherState
  private(set) var routineServerState: HomeRoutineServerState

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol,
    enrichHomeRoutinesUseCase:
      (any EnrichHomeRoutinesUseCaseProtocol)? = nil,
    weatherRepository: (any HomeWeatherRepository)? = nil,
    weatherService: (any HomeWeatherService)? = nil,
    initialWeatherState: HomeWeatherState = .notRequested,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.enrichHomeRoutinesUseCase = enrichHomeRoutinesUseCase
    self.weatherRepository = weatherRepository
    self.weatherService = weatherService
    self.now = now
    self.state = .loading(previousContent: nil)
    self.weatherState = initialWeatherState
    self.routineServerState = enrichHomeRoutinesUseCase == nil
      ? .notConfigured
      : .loading
  }

  func load() {
    routineServerTask?.cancel()
    routineServerTask = nil
    routineServerRequestID = nil
    let previousContent = state.routineContent
    state = .loading(previousContent: previousContent)

    do {
      let result = try loadHomeRoutinesUseCase.execute()
      state = makeViewState(from: result)
      startRoutineServerEnrichment(for: result)
    } catch {
      routineServerState = enrichHomeRoutinesUseCase == nil
        ? .notConfigured
        : .fallback(.localSyncStateUnavailable)
      state = .failed(
        .localRoutineDataUnavailable(diagnostic: String(reflecting: error)),
        previousContent: previousContent
      )
    }
  }

  func retry() {
    load()
  }

  private func startRoutineServerEnrichment(
    for result: HomeRoutineLoadResult
  ) {
    guard let enrichHomeRoutinesUseCase else {
      routineServerState = .notConfigured
      return
    }

    let requestID = UUID()
    routineServerRequestID = requestID
    routineServerState = .loading
    routineServerTask = Task { [weak self] in
      do {
        let enrichment = try await enrichHomeRoutinesUseCase.execute(
          localResult: result
        )
        guard let self else {
          return
        }
        guard self.routineServerRequestID == requestID,
              !Task.isCancelled else {
          #if DEBUG
          self.onStaleRoutineServerResultDiscarded?()
          #endif
          return
        }
        self.apply(enrichment)
        self.routineServerTask = nil
        self.routineServerRequestID = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self,
              self.routineServerRequestID == requestID,
              !Task.isCancelled else {
          return
        }
        self.routineServerState = .fallback(.remoteUnavailable)
        self.routineServerTask = nil
        self.routineServerRequestID = nil
      }
    }
  }

  private func apply(_ enrichment: HomeRoutineServerEnrichment) {
    switch enrichment {
    case .applied(let snapshot):
      if apply(snapshot) {
        routineServerState = .applied
      }
    case .noActive:
      routineServerState = .noActive
    case .fallback(let reason):
      routineServerState = .fallback(reason)
    }
  }

  @discardableResult
  private func apply(_ snapshot: HomeBoundActiveRoutineSnapshot) -> Bool {
    guard var content = state.routineContent else {
      return false
    }

    let mergedRoutine: HomeRoutineState
    if content.todayRoutine?.id == snapshot.localRoutineID,
       let todayRoutine = content.todayRoutine {
      guard hasExactStepIdentity(snapshot, routine: todayRoutine) else {
        routineServerState = .fallback(.activeRoutineIdentityMismatch)
        return false
      }
      let appliedRoutine = applying(snapshot, to: todayRoutine)
      content.todayRoutine = appliedRoutine
      mergedRoutine = appliedRoutine
    } else if let index = content.activeRoutines.firstIndex(
      where: { $0.id == snapshot.localRoutineID }
    ) {
      guard hasExactStepIdentity(
        snapshot,
        routine: content.activeRoutines[index]
      ) else {
        routineServerState = .fallback(.activeRoutineIdentityMismatch)
        return false
      }
      let appliedRoutine = applying(
        snapshot,
        to: content.activeRoutines[index]
      )
      content.activeRoutines[index] = appliedRoutine
      mergedRoutine = appliedRoutine
    } else {
      routineServerState = .fallback(.activeGroupIdentityMismatch)
      return false
    }

    let localTodayCompletedCount = mergedRoutine.steps
      .filter(\.isCompleted).count
    let completedCount = max(
      localTodayCompletedCount,
      snapshot.today.completedCount
    )
    let progress = max(
      max(content.todayProgress.progress, mergedRoutine.progress),
      max(
        snapshot.today.completionRate,
        self.progress(
          completed: completedCount,
          total: snapshot.today.totalCount
        )
      )
    )
    content.todayProgress = HomeProgressState(
      percentText: percentageText(progress),
      completedText:
        "\(completedCount)/\(snapshot.today.totalCount) 완료",
      progress: progress
    )
    state = content.activeRoutines.isEmpty && content.todayRoutine == nil
      ? .empty(content)
      : .content(content)
    return true
  }

  private func hasExactStepIdentity(
    _ snapshot: HomeBoundActiveRoutineSnapshot,
    routine: HomeRoutineState
  ) -> Bool {
    let visibleStepIDs = Set(routine.steps.map(\.id))
    let boundStepIDs = Set(snapshot.routines.map(\.localStepID))
    return visibleStepIDs.count == routine.steps.count
      && boundStepIDs.count == snapshot.routines.count
      && visibleStepIDs == boundStepIDs
  }

  private func applying(
    _ snapshot: HomeBoundActiveRoutineSnapshot,
    to routine: HomeRoutineState
  ) -> HomeRoutineState {
    var routine = routine
    let progressByStepID = Dictionary(
      uniqueKeysWithValues: snapshot.routines.map { ($0.localStepID, $0) }
    )
    routine.steps = routine.steps.map { step in
      guard let remote = progressByStepID[step.id] else {
        return step
      }
      var step = step
      step.isCompleted = step.isCompleted || remote.isCompleted
      if remote.isCompleted,
         let seconds = remote.completedTimeSeconds {
        step.detail = durationText(seconds)
      }
      return step
    }
    let completedCount = routine.steps.filter(\.isCompleted).count
    let mergedProgress = max(
      routine.progress,
      max(
        snapshot.completionRate,
        progress(completed: completedCount, total: snapshot.routines.count)
      )
    )

    routine.statusText = statusText(
      completed: completedCount,
      total: snapshot.routines.count
    )
    routine.completionText =
      "\(completedCount)/\(snapshot.routines.count) 완료"
    routine.progressText = percentageText(mergedProgress)
    routine.progress = mergedProgress
    return routine
  }

  private func percentageText(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  private func durationText(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    return "\(minutes):\(String(format: "%02d", remainder))"
  }

  func requestWeather() {
    startWeatherRequest(replacingCurrentRequest: true)
  }

  func loadWeatherAutomaticallyIfNeeded() {
    guard weatherState == .notRequested else {
      return
    }

    startWeatherRequest(replacingCurrentRequest: false)
  }

  func resumeWeatherAfterAuthorizationChange() {
    guard !isWeatherRequestInProgress else {
      return
    }

    switch weatherState {
    case .denied, .restricted:
      break
    case .notRequested, .requestingPermission, .locating, .loading,
         .fresh, .stale, .noFix, .unavailable:
      return
    }

    guard weatherService?.authorizationStatus == .authorized else {
      return
    }

    startWeatherRequest(replacingCurrentRequest: false)
  }

  private func startWeatherRequest(replacingCurrentRequest: Bool) {
    if isWeatherRequestInProgress {
      guard replacingCurrentRequest else {
        return
      }
    }

    if replacingCurrentRequest {
      weatherTask?.cancel()
      weatherService?.cancelCurrentLocationRequests()
    }

    let requestID = UUID()
    activeWeatherRequestID = requestID
    isWeatherRequestInProgress = true

    guard weatherRepository != nil, weatherService != nil else {
      apply(weatherState: .unavailable(.unavailableConfiguration), for: requestID)
      finishWeatherRequest(requestID: requestID)
      return
    }

    weatherTask = Task { [weak self] in
      guard let self else {
        return
      }

      await self.loadWeather(requestID: requestID)
      self.finishWeatherRequest(requestID: requestID)
    }
  }

  private func finishWeatherRequest(requestID: UUID) {
    guard activeWeatherRequestID == requestID else {
      return
    }

    weatherTask = nil
    activeWeatherRequestID = nil
    isWeatherRequestInProgress = false
  }

  private func loadWeather(requestID: UUID) async {
    guard let weatherRepository, let weatherService else {
      apply(weatherState: .unavailable(.unavailableConfiguration), for: requestID)
      return
    }

    var authorizationStatus = weatherService.authorizationStatus
    if authorizationStatus == .notDetermined {
      guard await weatherService.locationServicesEnabled() else {
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
      cachedWeather = nil
    }

    guard await weatherService.locationServicesEnabled() else {
      await applyCachedWeatherOrNoFix(
        cachedWeather,
        for: requestID,
        weatherService: weatherService
      )
      return
    }

    apply(weatherState: .locating(requestID), for: requestID)

    let location: CLLocation
    do {
      location = try await weatherService.currentLocation()
    } catch is CancellationError {
      return
    } catch let error as HomeWeatherServiceError {
      await handleLocationError(
        error,
        cachedWeather: cachedWeather,
        requestID: requestID,
        repository: weatherRepository,
        weatherService: weatherService
      )
      return
    } catch {
      await applyCachedWeatherOrNoFix(
        cachedWeather,
        for: requestID,
        weatherService: weatherService
      )
      return
    }

    guard isCurrentWeatherRequest(requestID) else {
      return
    }

    let usableCachedWeather: HomeWeatherSnapshot?
    if let cachedWeather, isWithinMaximumCacheDistance(cachedWeather, of: location) {
      usableCachedWeather = cachedWeather
    } else if cachedWeather != nil {
      try? weatherRepository.eraseCachedWeather()
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

      try? weatherRepository.saveWeather(snapshot)
      await applyAttributedWeather(
        snapshot,
        isLiveResult: true,
        for: requestID,
        weatherService: weatherService
      )
    } catch is CancellationError {
      return
    } catch let error as HomeWeatherServiceError {
      if let usableCachedWeather {
        await applyAttributedWeather(
          usableCachedWeather,
          isLiveResult: false,
          for: requestID,
          weatherService: weatherService
        )
      } else {
        apply(weatherState: .unavailable(.service(error)), for: requestID)
      }
    } catch {
      if let usableCachedWeather {
        await applyAttributedWeather(
          usableCachedWeather,
          isLiveResult: false,
          for: requestID,
          weatherService: weatherService
        )
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
    repository: any HomeWeatherRepository,
    weatherService: any HomeWeatherService
  ) async {
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
      await applyCachedWeatherOrNoFix(
        cachedWeather,
        for: requestID,
        weatherService: weatherService
      )
    case .weatherUnavailable, .attributionUnavailable, .invalidWeatherData:
      apply(weatherState: .unavailable(.service(error)), for: requestID)
    }
  }

  private func applyCachedWeatherOrNoFix(
    _ cachedWeather: HomeWeatherSnapshot?,
    for requestID: UUID,
    weatherService: any HomeWeatherService
  ) async {
    if let cachedWeather {
      await applyAttributedWeather(
        cachedWeather,
        isLiveResult: false,
        for: requestID,
        weatherService: weatherService
      )
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

    try? repository.eraseCachedWeather()
    apply(weatherState: weatherState, for: requestID)
  }

  private func applyAttributedWeather(
    _ snapshot: HomeWeatherSnapshot,
    isLiveResult: Bool,
    for requestID: UUID,
    weatherService: any HomeWeatherService
  ) async {
    do {
      let attribution = try await weatherService.weatherAttribution()
      guard isCurrentWeatherRequest(requestID) else {
        return
      }

      let content = HomeWeatherContent(
        snapshot: snapshot,
        attribution: attribution
      )
      let weatherState: HomeWeatherState = isLiveResult
        ? .fresh(content)
        : cacheState(for: content)
      apply(weatherState: weatherState, for: requestID)
    } catch is CancellationError {
      return
    } catch {
      apply(
        weatherState: .unavailable(.service(.attributionUnavailable)),
        for: requestID
      )
    }
  }

  private func cacheState(for content: HomeWeatherContent) -> HomeWeatherState {
    let freshnessInterval: TimeInterval = 30 * 60
    let age = now().timeIntervalSince(content.snapshot.fetchedAt)
    return age <= freshnessInterval ? .fresh(content) : .stale(content)
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
      makeRoutineState(
        routine: routine,
        todayRun: result.todayRunsByRoutineID[routine.id]
      )
    }
    let activeRoutines = result.manualRoutines
      .filter { $0.id != result.todayRoutine?.id }
      .map { routine in
        makeRoutineState(
          routine: routine,
          todayRun: result.todayRunsByRoutineID[routine.id]
        )
      }
    let todayRun = result.todayRoutine.flatMap {
      result.todayRunsByRoutineID[$0.id]
    }
    let content = HomeContentState(
      userName: result.profile?.displayName ?? "",
      todayRoutine: todayRoutineState,
      activeRoutines: activeRoutines,
      todayProgress: makeProgressState(
        routine: result.todayRoutine,
        todayRun: todayRun
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

    return result.manualRoutines.isEmpty ? .empty(content) : .content(content)
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
      statusText: statusText(completed: completed, total: steps.count),
      scheduleText: scheduleText(for: routine),
      stepSummaryText: "\(steps.count)개 스텝 · \(estimatedMinutes(for: steps))분",
      completionText: "\(completed)/\(steps.count) 완료",
      estimatedDurationText: "소요 시간 \(estimatedMinutes(for: steps))분",
      progressText: "\(Int((progress * 100).rounded()))%",
      progress: progress,
      isActive: routine.isActive,
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

  private func statusText(completed: Int, total: Int) -> String {
    if total > 0 && completed == total {
      return "진행 완료"
    }

    return completed > 0 ? "진행 중" : "진행 전"
  }

  private func scheduleText(for routine: Routine) -> String {
    guard let schedule = routine.alarmSchedule else {
      return "수동 실행"
    }

    let timeText = String(format: "%02d:%02d", schedule.hour, schedule.minute)
    guard schedule.isEnabled else {
      return "\(weekdayText(schedule.weekdays)) \(timeText) · 알람 꺼짐"
    }

    return "\(weekdayText(schedule.weekdays)) \(timeText)"
  }

  private func weekdayText(_ weekdays: [Weekday]) -> String {
    let weekdaySet = Set(weekdays)
    if weekdaySet == Set(Weekday.allCases) {
      return "매일"
    }

    if weekdaySet == Set(Weekday.weekdays) {
      return "평일"
    }

    if weekdaySet == Set([Weekday.saturday, .sunday]) {
      return "주말"
    }

    if weekdaySet.isEmpty {
      return "요일 미설정"
    }

    return weekdays
      .sortedByDisplayOrder()
      .map(\.shortTitle)
      .joined(separator: "·")
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
