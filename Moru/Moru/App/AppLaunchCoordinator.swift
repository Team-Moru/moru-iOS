//
//  AppLaunchCoordinator.swift
//  Moru
//
//  Created by Codex on 7/18/26.
//

import Combine
import Foundation
import SwiftData
import SwiftUI

nonisolated struct SendableModelContainer: @unchecked Sendable {
  fileprivate let rawModelContainer: ModelContainer

  fileprivate init(_ rawModelContainer: ModelContainer) {
    self.rawModelContainer = rawModelContainer
  }

  @MainActor
  static func inMemoryForTesting() throws -> SendableModelContainer {
    SendableModelContainer(try ModelContainer.moruContainer(isStoredInMemoryOnly: true))
  }
}

nonisolated protocol ModelContainerFactory: Sendable {
  func makeContainer() async throws -> SendableModelContainer
}

nonisolated struct DefaultModelContainerFactory: ModelContainerFactory {
  func makeContainer() async throws -> SendableModelContainer {
    try await Task.detached(priority: .userInitiated) {
      SendableModelContainer(try ModelContainer.moruContainer())
    }.value
  }
}

nonisolated protocol AppLaunchClock: Sendable {
  func sleep(for duration: Duration) async throws
}

nonisolated struct ContinuousAppLaunchClock: AppLaunchClock {
  func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}

nonisolated struct SessionProfileSnapshot: Sendable, Equatable {
  let id: UUID
  let displayName: String
  let selectedVoiceID: String
  let createdAt: Date
  let updatedAt: Date

  init(
    id: UUID,
    displayName: String,
    selectedVoiceID: String,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.displayName = displayName
    self.selectedVoiceID = selectedVoiceID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

}

nonisolated enum SessionRoutineStepKind: String, Sendable, Equatable {
  case confirm
  case timer
  case input

}

nonisolated enum SessionWeekday: Int, Sendable, Equatable {
  case sunday = 1
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday

}

nonisolated struct SessionRoutineStepSnapshot: Sendable, Equatable {
  let id: UUID
  let presetItemID: String?
  let kind: SessionRoutineStepKind
  let title: String
  let instruction: String
  let order: Int
  let estimatedSeconds: Int?
  let isRequired: Bool

  init(
    id: UUID,
    presetItemID: String?,
    kind: SessionRoutineStepKind,
    title: String,
    instruction: String,
    order: Int,
    estimatedSeconds: Int?,
    isRequired: Bool
  ) {
    self.id = id
    self.presetItemID = presetItemID
    self.kind = kind
    self.title = title
    self.instruction = instruction
    self.order = order
    self.estimatedSeconds = estimatedSeconds
    self.isRequired = isRequired
  }

}

nonisolated struct SessionAlarmScheduleSnapshot: Sendable, Equatable {
  let id: UUID
  let hour: Int
  let minute: Int
  let weekdays: [SessionWeekday]
  let soundName: String
  let isEnabled: Bool
  let includeWeather: Bool
  let includeFortune: Bool

  init(
    id: UUID,
    hour: Int,
    minute: Int,
    weekdays: [SessionWeekday],
    soundName: String,
    isEnabled: Bool,
    includeWeather: Bool,
    includeFortune: Bool
  ) {
    self.id = id
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays
    self.soundName = soundName
    self.isEnabled = isEnabled
    self.includeWeather = includeWeather
    self.includeFortune = includeFortune
  }

}

nonisolated struct SessionRoutineSnapshot: Sendable, Equatable {
  let id: UUID
  let name: String
  let summary: String
  let goalTags: [String]
  let steps: [SessionRoutineStepSnapshot]
  let alarmSchedule: SessionAlarmScheduleSnapshot?
  let isActive: Bool
  let createdAt: Date
  let updatedAt: Date

  init(
    id: UUID,
    name: String,
    summary: String,
    goalTags: [String],
    steps: [SessionRoutineStepSnapshot],
    alarmSchedule: SessionAlarmScheduleSnapshot?,
    isActive: Bool,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.goalTags = goalTags
    self.steps = steps
    self.alarmSchedule = alarmSchedule
    self.isActive = isActive
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

}

nonisolated struct SessionSnapshot: Sendable, Equatable {
  let profile: SessionProfileSnapshot?
  let activeRoutines: [SessionRoutineSnapshot]
  let platformStates: [AlarmPlatformSnapshot]
  let settings: LocalSettingsSnapshot?
  let resetGeneration: UInt64?

  init(
    profile: SessionProfileSnapshot?,
    activeRoutines: [SessionRoutineSnapshot],
    platformStates: [AlarmPlatformSnapshot],
    settings: LocalSettingsSnapshot?,
    resetGeneration: UInt64?
  ) {
    self.profile = profile
    self.activeRoutines = activeRoutines
    self.platformStates = platformStates
    self.settings = settings
    self.resetGeneration = resetGeneration
  }
}

nonisolated protocol SessionSnapshotLoader: Sendable {
  func loadSnapshot() async throws -> SessionSnapshot
}

nonisolated protocol SessionSnapshotLoaderFactory: Sendable {
  func makeLoader(for container: SendableModelContainer) -> any SessionSnapshotLoader
}

nonisolated struct DefaultSessionSnapshotLoaderFactory: SessionSnapshotLoaderFactory {
  func makeLoader(for container: SendableModelContainer) -> any SessionSnapshotLoader {
    SessionSnapshotLoading(modelContainer: container.rawModelContainer)
  }
}

@ModelActor
actor SessionSnapshotLoading: SessionSnapshotLoader {
  func loadSnapshot() async throws -> SessionSnapshot {
    let profileDescriptor = FetchDescriptor<PersistedLocalProfile>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    let persistedProfile = try modelContext.fetch(profileDescriptor).first
    let profile = persistedProfile.map(makeProfileSnapshot)

    let routinesDescriptor = FetchDescriptor<PersistedRoutine>(
      predicate: #Predicate { $0.isActive },
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    let activeRoutines = try modelContext.fetch(routinesDescriptor).map {
      try makeRoutineSnapshot(from: $0)
    }
    let platformStates = try modelContext.fetch(FetchDescriptor<PersistedAlarmPlatformState>())
      .map(SwiftDataV2Mapper.makeAlarmPlatformSnapshot)
    let settings: LocalSettingsSnapshot?
    if let persistedProfile {
      settings = try loadSettings(for: persistedProfile)
    } else {
      settings = nil
    }

    return SessionSnapshot(
      profile: profile,
      activeRoutines: activeRoutines,
      platformStates: platformStates,
      settings: settings,
      resetGeneration: nil
    )
  }

  private func makeProfileSnapshot(
    from persisted: PersistedLocalProfile
  ) -> SessionProfileSnapshot {
    let profile = SwiftDataMapper.makeDomainProfile(from: persisted)

    return SessionProfileSnapshot(
      id: profile.id,
      displayName: profile.displayName,
      selectedVoiceID: profile.selectedVoice.id,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt
    )
  }

  private func makeRoutineSnapshot(
    from persisted: PersistedRoutine
  ) throws -> SessionRoutineSnapshot {
    let routine = try SwiftDataMapper.makeDomainRoutine(from: persisted)

    return SessionRoutineSnapshot(
      id: routine.id,
      name: routine.name,
      summary: routine.summary,
      goalTags: routine.goalTags,
      steps: routine.steps.map { makeRoutineStepSnapshot(from: $0) },
      alarmSchedule: routine.alarmSchedule.map { makeAlarmScheduleSnapshot(from: $0) },
      isActive: routine.isActive,
      createdAt: routine.createdAt,
      updatedAt: routine.updatedAt
    )
  }

  private func makeRoutineStepSnapshot(
    from step: RoutineStep
  ) -> SessionRoutineStepSnapshot {
    SessionRoutineStepSnapshot(
      id: step.id,
      presetItemID: step.presetItemID,
      kind: makeStepKind(step.type),
      title: step.title,
      instruction: step.instruction,
      order: step.order,
      estimatedSeconds: step.estimatedSeconds,
      isRequired: step.isRequired
    )
  }

  private func makeAlarmScheduleSnapshot(
    from schedule: AlarmSchedule
  ) -> SessionAlarmScheduleSnapshot {
    SessionAlarmScheduleSnapshot(
      id: schedule.id,
      hour: schedule.hour,
      minute: schedule.minute,
      weekdays: schedule.weekdays.map { makeSessionWeekday($0) },
      soundName: schedule.soundName,
      isEnabled: schedule.isEnabled,
      includeWeather: schedule.includeWeather,
      includeFortune: schedule.includeFortune
    )
  }

  private func makeStepKind(_ type: RoutineStepType) -> SessionRoutineStepKind {
    switch type {
    case .confirm:
      .confirm
    case .timer:
      .timer
    case .input:
      .input
    }
  }

  private func makeSessionWeekday(_ weekday: Weekday) -> SessionWeekday {
    switch weekday {
    case .sunday:
      .sunday
    case .monday:
      .monday
    case .tuesday:
      .tuesday
    case .wednesday:
      .wednesday
    case .thursday:
      .thursday
    case .friday:
      .friday
    case .saturday:
      .saturday
    }
  }
  private func loadSettings(
    for profile: PersistedLocalProfile
  ) throws -> LocalSettingsSnapshot? {
    let profileID = profile.id
    let descriptor = FetchDescriptor<PersistedLocalSettings>(
      predicate: #Predicate { $0.profileID == profileID }
    )

    return try modelContext.fetch(descriptor).first.map {
      try SwiftDataV2Mapper.makeLocalSettingsSnapshot(from: $0, profile: profile)
    }
  }
}

@MainActor
final class PendingLaunchResources {
  let launchGeneration: UInt64

  private var container: SendableModelContainer?
  private var loader: (any SessionSnapshotLoader)?
  private var ownership: Ownership = .pending
  private var sessionFailureCount = 0

  private(set) var wasTransferred = false
  private(set) var wasDisposed = false
  private(set) var transferCount = 0

  init(
    container: SendableModelContainer,
    launchGeneration: UInt64,
    loaderFactory: any SessionSnapshotLoaderFactory
  ) {
    self.container = container
    self.launchGeneration = launchGeneration
    loader = loaderFactory.makeLoader(for: container)
  }

  func loadSnapshot() async throws -> SessionSnapshot {
    guard case .pending = ownership, let loader else {
      throw PendingLaunchResourceError.unavailable
    }

    return try await loader.loadSnapshot()
  }

  func recordSessionFailure() -> Int {
    sessionFailureCount += 1
    return sessionFailureCount
  }

  fileprivate func transfer() -> TransferredLaunchResources? {
    guard case .pending = ownership, let container, let loader else {
      return nil
    }

    ownership = .transferred
    wasTransferred = true
    transferCount += 1
    self.container = nil
    self.loader = nil
    return TransferredLaunchResources(container: container, loader: loader)
  }

  func dispose() {
    guard case .pending = ownership else {
      return
    }

    ownership = .disposed
    wasDisposed = true
    container = nil
    loader = nil
  }

  private enum Ownership {
    case pending
    case transferred
    case disposed
  }
}

private struct TransferredLaunchResources {
  let container: SendableModelContainer
  let loader: any SessionSnapshotLoader
}

nonisolated enum PendingLaunchResourceError: Error, Equatable {
  case unavailable
}

nonisolated struct AppLaunchAttemptToken: Sendable, Equatable, Hashable {
  let launchGeneration: UInt64
  let attemptNumber: UInt64
}

nonisolated enum SessionReloadSource: Sendable, Hashable {
  case onboardingCompletion(UUID)
  case reset(UUID)
  case routineMutation(UUID)
  case trialDismissal(UUID)
}

nonisolated struct AppLaunchFailure: Equatable, Sendable {
  nonisolated enum Kind: Equatable, Sendable {
    case bootstrap
    case session
    case timedOut
  }

  let kind: Kind
  let message: String
  let diagnosticDescription: String?

  static let bootstrap = AppLaunchFailure(
    kind: .bootstrap,
    message: "저장소를 초기화할 수 없어요. 다시 시도해 주세요.",
    diagnosticDescription: nil
  )
  static let session = AppLaunchFailure(
    kind: .session,
    message: "저장된 세션을 불러올 수 없어요. 다시 시도해 주세요.",
    diagnosticDescription: nil
  )
  static let timedOut = AppLaunchFailure(
    kind: .timedOut,
    message: "앱을 시작하는 데 시간이 오래 걸리고 있어요. 다시 시도해 주세요.",
    diagnosticDescription: nil
  )

  static func bootstrap(capturing error: any Error) -> AppLaunchFailure {
    AppLaunchFailure(
      kind: .bootstrap,
      message: bootstrap.message,
      diagnosticDescription: String(reflecting: error)
    )
  }

  static func session(capturing error: any Error) -> AppLaunchFailure {
    AppLaunchFailure(
      kind: .session,
      message: session.message,
      diagnosticDescription: String(reflecting: error)
    )
  }
}

@MainActor
final class LaunchedApp {
  let modelContainer: ModelContainer
  let dependencies: DependencyContainer
  let sessionStore: SessionStore
  let navigationCoordinator: AppNavigationCoordinator
  let onboardingBuilder: any OnboardingFlowBuilding
  let routinePlayerBuilder: any RoutinePlayerBuilding
  let homeBuilder: any HomeFlowBuilding
  let routerState: AppRouterState

  fileprivate let sessionLoader: any SessionSnapshotLoader
  fileprivate let ownedContainer: SendableModelContainer

  fileprivate init(resources: TransferredLaunchResources, snapshot: SessionSnapshot) {
    ownedContainer = resources.container
    modelContainer = resources.container.rawModelContainer
    sessionLoader = resources.loader
    let appDependencies = DependencyContainer.local(
      modelContext: resources.container.rawModelContainer.mainContext
    )
    dependencies = appDependencies
    sessionStore = appDependencies.makeSessionStore()
    sessionStore.apply(snapshot: snapshot)
    navigationCoordinator = AppNavigationCoordinator()
    routerState = AppRouterState()
    onboardingBuilder = appDependencies.makeOnboardingBuilder()
    routinePlayerBuilder = appDependencies.makeRoutinePlayerBuilder()
    homeBuilder = DefaultHomeFlowBuilder(
      loadHomeRoutinesUseCase: LoadHomeRoutinesUseCase(
        routineRepository: appDependencies.routineRepository,
        routineRunRepository: appDependencies.routineRunRepository,
        localProfileRepository: appDependencies.localProfileRepository
      ),
      weatherRepository: appDependencies.homeWeatherRepository,
      weatherService: CoreLocationWeatherService(),
      routineSettingContentFactory: {
        AnyView(RoutineSettingView(dependencies: appDependencies))
      }
    )
  }
}

@MainActor
enum AppLaunchPhase {
  case idle
  case constructing
  case loadingSession(PendingLaunchResources)
  case ready(LaunchedApp)
  case bootstrapFailed(AppLaunchFailure)
  case sessionFailed(PendingLaunchResources, AppLaunchFailure)
  case recoveryRequired(AppLaunchFailure)
}

@MainActor
final class AppLaunchCoordinator: ObservableObject {
  @Published private(set) var phase: AppLaunchPhase = .idle
  @Published private(set) var showsLaunchStatus = false
  private(set) var activeAttemptToken: AppLaunchAttemptToken?
  private(set) var lastFailure: AppLaunchFailure?

  private let modelContainerFactory: any ModelContainerFactory
  private let loaderFactory: any SessionSnapshotLoaderFactory
  private let clock: any AppLaunchClock

  private var nextLaunchGeneration: UInt64 = 0
  private var nextAttemptNumber: UInt64 = 0
  private var constructionTask: Task<Void, Never>?
  private var sessionTask: Task<Void, Never>?
  private var statusTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var queuedReloadSources: [SessionReloadSource] = []
  private var completedReloadSources = Set<SessionReloadSource>()
  private var inFlightReloadSource: SessionReloadSource?
  private var failedReloadSource: SessionReloadSource?

  init(
    modelContainerFactory: any ModelContainerFactory = DefaultModelContainerFactory(),
    loaderFactory: any SessionSnapshotLoaderFactory = DefaultSessionSnapshotLoaderFactory(),
    clock: any AppLaunchClock = ContinuousAppLaunchClock()
  ) {
    self.modelContainerFactory = modelContainerFactory
    self.loaderFactory = loaderFactory
    self.clock = clock
  }

  deinit {
    constructionTask?.cancel()
    sessionTask?.cancel()
    statusTask?.cancel()
    timeoutTask?.cancel()
  }

  func start() {
    guard case .idle = phase else {
      return
    }

    beginConstruction()
  }

  func retry() {
    switch phase {
    case .bootstrapFailed:
      beginConstruction()
    case .sessionFailed(let pending, _):
      beginSessionLoading(pending)
    case .idle, .constructing, .loadingSession, .ready, .recoveryRequired:
      return
    }
  }

  func requestSessionReload(source: SessionReloadSource) {
    guard !completedReloadSources.contains(source),
          inFlightReloadSource != source,
          failedReloadSource != source,
          !queuedReloadSources.contains(source) else {
      return
    }

    queuedReloadSources.append(source)
    beginQueuedReloadIfPossible()
  }

  func retrySessionReload() {
    guard let source = failedReloadSource else {
      return
    }

    retrySessionReload(source: source)
  }

  func retrySessionReload(source: SessionReloadSource) {
    guard failedReloadSource == source,
          inFlightReloadSource == nil,
          activeAttemptToken == nil,
          case .ready(let launchedApp) = phase else {
      return
    }

    failedReloadSource = nil
    beginReload(source, for: launchedApp)
  }

  private func beginConstruction() {
    cancelOutstandingWork()
    nextLaunchGeneration &+= 1
    let token = makeAttemptToken(for: nextLaunchGeneration)
    phase = .constructing
    armTimers(for: token)

    let factory = modelContainerFactory
    constructionTask = Task { @MainActor [weak self, factory] in
      do {
        let container = try await factory.makeContainer()
        guard !Task.isCancelled else {
          return
        }
        self?.receivedConstruction(container, for: token)
      } catch is CancellationError {
        return
      } catch {
        self?.receivedConstructionFailure(
          for: token,
          failure: .bootstrap(capturing: error)
        )
      }
    }
  }

  private func receivedConstruction(
    _ container: SendableModelContainer,
    for token: AppLaunchAttemptToken
  ) {
    guard activeAttemptToken == token else {
      return
    }

    finishAttempt(token)
    let pending = PendingLaunchResources(
      container: container,
      launchGeneration: token.launchGeneration,
      loaderFactory: loaderFactory
    )
    phase = .loadingSession(pending)
    beginSessionLoading(pending)
  }

  private func receivedConstructionFailure(
    for token: AppLaunchAttemptToken,
    failure: AppLaunchFailure
  ) {
    guard activeAttemptToken == token else {
      return
    }

    lastFailure = failure
    finishAttempt(token)
    phase = .bootstrapFailed(failure)
  }

  private func beginSessionLoading(_ pending: PendingLaunchResources) {
    guard pending.launchGeneration == nextLaunchGeneration else {
      return
    }

    cancelOutstandingWork()
    let token = makeAttemptToken(for: pending.launchGeneration)
    phase = .loadingSession(pending)
    armTimers(for: token)

    sessionTask = Task { @MainActor [weak self, pending] in
      do {
        let snapshot = try await pending.loadSnapshot()
        guard !Task.isCancelled else {
          return
        }
        self?.receivedSessionSnapshot(snapshot, from: pending, for: token)
      } catch is CancellationError {
        return
      } catch {
        self?.receivedSessionFailure(
          from: pending,
          for: token,
          failure: .session(capturing: error)
        )
      }
    }
  }

  private func receivedSessionSnapshot(
    _ snapshot: SessionSnapshot,
    from pending: PendingLaunchResources,
    for token: AppLaunchAttemptToken
  ) {
    guard matchesCurrentSessionAttempt(token, pending: pending) else {
      return
    }

    lastFailure = nil
    finishAttempt(token)
    guard let resources = pending.transfer() else {
      pending.dispose()
      lastFailure = .session
      phase = .recoveryRequired(.session)
      return
    }

    let launchedApp = LaunchedApp(resources: resources, snapshot: snapshot)
    phase = .ready(launchedApp)
    beginQueuedReloadIfPossible()
  }

  private func receivedSessionFailure(
    from pending: PendingLaunchResources,
    for token: AppLaunchAttemptToken,
    failure: AppLaunchFailure
  ) {
    guard matchesCurrentSessionAttempt(token, pending: pending) else {
      return
    }

    finishAttempt(token)
    finishSessionFailure(for: pending, failure: failure)
  }

  private func finishSessionFailure(
    for pending: PendingLaunchResources,
    failure: AppLaunchFailure
  ) {
    lastFailure = failure
    if pending.recordSessionFailure() > 3 {
      pending.dispose()
      phase = .recoveryRequired(failure)
    } else {
      phase = .sessionFailed(pending, failure)
    }
  }

  private func beginQueuedReloadIfPossible() {
    guard activeAttemptToken == nil,
          inFlightReloadSource == nil,
          failedReloadSource == nil,
          case .ready(let launchedApp) = phase,
          !queuedReloadSources.isEmpty else {
      return
    }

    let source = queuedReloadSources.removeFirst()
    beginReload(source, for: launchedApp)
  }

  private func beginReload(_ source: SessionReloadSource, for launchedApp: LaunchedApp) {
    guard activeAttemptToken == nil,
          inFlightReloadSource == nil,
          case .ready(let activeApp) = phase,
          activeApp === launchedApp else {
      return
    }

    inFlightReloadSource = source
    let token = makeAttemptToken(for: nextLaunchGeneration)
    armTimers(for: token)

    sessionTask = Task { @MainActor [weak self, launchedApp] in
      do {
        let snapshot = try await launchedApp.sessionLoader.loadSnapshot()
        guard !Task.isCancelled else {
          return
        }
        self?.receivedReloadSnapshot(
          snapshot,
          source: source,
          for: launchedApp,
          token: token
        )
      } catch is CancellationError {
        return
      } catch {
        self?.receivedReloadFailure(
          source: source,
          for: launchedApp,
          token: token,
          failure: .session(capturing: error)
        )
      }
    }
  }

  private func receivedReloadSnapshot(
    _ snapshot: SessionSnapshot,
    source: SessionReloadSource,
    for launchedApp: LaunchedApp,
    token: AppLaunchAttemptToken
  ) {
    guard matchesCurrentReloadAttempt(token, source: source, launchedApp: launchedApp) else {
      return
    }

    lastFailure = nil
    finishAttempt(token)
    launchedApp.sessionStore.apply(snapshot: snapshot)
    inFlightReloadSource = nil
    completedReloadSources.insert(source)
    beginQueuedReloadIfPossible()
  }

  private func receivedReloadFailure(
    source: SessionReloadSource,
    for launchedApp: LaunchedApp,
    token: AppLaunchAttemptToken,
    failure: AppLaunchFailure
  ) {
    guard matchesCurrentReloadAttempt(token, source: source, launchedApp: launchedApp) else {
      return
    }

    lastFailure = failure
    finishAttempt(token)
    inFlightReloadSource = nil
    failedReloadSource = source
    launchedApp.sessionStore.apply(failure: failure)
  }

  private func armTimers(for token: AppLaunchAttemptToken) {
    activeAttemptToken = token
    showsLaunchStatus = false

    let clock = clock
    statusTask = Task { @MainActor [weak self, clock] in
      do {
        try await clock.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else {
          return
        }
        self?.showLaunchStatus(for: token)
      } catch is CancellationError {
        return
      } catch {
        self?.timedOut(token)
      }
    }

    timeoutTask = Task { @MainActor [weak self, clock] in
      do {
        try await clock.sleep(for: .seconds(8))
        guard !Task.isCancelled else {
          return
        }
        self?.timedOut(token)
      } catch is CancellationError {
        return
      } catch {
        self?.timedOut(token)
      }
    }
  }

  private func showLaunchStatus(for token: AppLaunchAttemptToken) {
    guard activeAttemptToken == token else {
      return
    }

    showsLaunchStatus = true
  }

  private func timedOut(_ token: AppLaunchAttemptToken) {
    guard activeAttemptToken == token else {
      return
    }

    switch phase {
    case .constructing:
      constructionTask?.cancel()
      finishAttempt(token)
      lastFailure = .timedOut
      phase = .bootstrapFailed(.timedOut)
    case .loadingSession(let pending):
      sessionTask?.cancel()
      finishAttempt(token)
      finishSessionFailure(for: pending, failure: .timedOut)
    case .ready(let launchedApp):
      guard let source = inFlightReloadSource else {
        return
      }

      sessionTask?.cancel()
      receivedReloadFailure(
        source: source,
        for: launchedApp,
        token: token,
        failure: .timedOut
      )
    case .idle, .bootstrapFailed, .sessionFailed, .recoveryRequired:
      return
    }
  }

  private func matchesCurrentSessionAttempt(
    _ token: AppLaunchAttemptToken,
    pending: PendingLaunchResources
  ) -> Bool {
    guard activeAttemptToken == token, case .loadingSession(let activePending) = phase else {
      return false
    }

    return activePending === pending
  }

  private func matchesCurrentReloadAttempt(
    _ token: AppLaunchAttemptToken,
    source: SessionReloadSource,
    launchedApp: LaunchedApp
  ) -> Bool {
    guard activeAttemptToken == token,
          inFlightReloadSource == source,
          case .ready(let activeApp) = phase else {
      return false
    }

    return activeApp === launchedApp
  }

  private func finishAttempt(_ token: AppLaunchAttemptToken) {
    guard activeAttemptToken == token else {
      return
    }

    activeAttemptToken = nil
    statusTask?.cancel()
    timeoutTask?.cancel()
    statusTask = nil
    timeoutTask = nil
    showsLaunchStatus = false
  }

  private func cancelOutstandingWork() {
    constructionTask?.cancel()
    sessionTask?.cancel()
    statusTask?.cancel()
    timeoutTask?.cancel()
    constructionTask = nil
    sessionTask = nil
    statusTask = nil
    timeoutTask = nil
    activeAttemptToken = nil
    showsLaunchStatus = false
  }

  private func makeAttemptToken(for launchGeneration: UInt64) -> AppLaunchAttemptToken {
    nextAttemptNumber &+= 1
    return AppLaunchAttemptToken(
      launchGeneration: launchGeneration,
      attemptNumber: nextAttemptNumber
    )
  }

}
