//
//  DependencyContainer.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

struct DependencyContainer {

  let routineRepository: any RoutineRepository
  let routineRunRepository: any RoutineRunRepository
  let localProfileRepository: any LocalProfileRepository
  let localSettingsRepository: any LocalSettingsRepository
  let onboardingRepository: any OnboardingRepository
  let routineSuggestionService: any RoutineSuggestionService
  let homeWeatherRepository: (any HomeWeatherRepository)?
  let historyEvidenceRepository: any HistoryEvidenceRepository
  let voiceAvailabilityProbe: any VoiceAvailabilityProbing
  let alarmScheduleMutator: any AlarmScheduleMutating
  let localResetRepository: (any LocalResetDataRepository)?
  let localResetJournalStore: (any LocalResetJournalStoring)?

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    localSettingsRepository: any LocalSettingsRepository,
    onboardingRepository: any OnboardingRepository,
    routineSuggestionService: any RoutineSuggestionService,
    homeWeatherRepository: (any HomeWeatherRepository)?,
    historyEvidenceRepository: any HistoryEvidenceRepository,
    voiceAvailabilityProbe: any VoiceAvailabilityProbing,
    alarmScheduleMutator: any AlarmScheduleMutating,
    localResetRepository: (any LocalResetDataRepository)? = nil,
    localResetJournalStore: (any LocalResetJournalStoring)? = nil
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.localSettingsRepository = localSettingsRepository
    self.onboardingRepository = onboardingRepository
    self.routineSuggestionService = routineSuggestionService
    self.homeWeatherRepository = homeWeatherRepository
    self.historyEvidenceRepository = historyEvidenceRepository
    self.voiceAvailabilityProbe = voiceAvailabilityProbe
    self.alarmScheduleMutator = alarmScheduleMutator
    self.localResetRepository = localResetRepository
    self.localResetJournalStore = localResetJournalStore
  }

  @MainActor
  static func local(modelContext: ModelContext) -> DependencyContainer {
    let voiceAvailabilityProbe = AVSpeechVoiceAvailabilityProbe()
    let localProfileRepository = SwiftDataLocalProfileRepository(
      modelContext: modelContext,
      availabilityProbe: voiceAvailabilityProbe
    )
    let resetJournalStore = LocalResetJournalStore()
    let alarmScheduleMutator = NotificationAlarmMutationCoordinator(
      scheduler: UserNotificationAlarmScheduler(),
      platformRepository: SwiftDataAlarmPlatformStateRepository(modelContext: modelContext),
      resetGeneration: {
        try resetJournalStore.currentGeneration()
      },
      mutationAllowed: {
        do {
          guard let journal = try resetJournalStore.load() else {
            return true
          }

          return journal.phase.isTerminal
        } catch {
          return false
        }
      }
    )
    let localResetRepository = SwiftDataLocalResetRepository(modelContext: modelContext)

    return DependencyContainer(
      routineRepository: SwiftDataRoutineRepository(modelContext: modelContext),
      routineRunRepository: SwiftDataRoutineRunRepository(modelContext: modelContext),
      localProfileRepository: localProfileRepository,
      localSettingsRepository: localProfileRepository,
      onboardingRepository: SwiftDataOnboardingRepository(modelContext: modelContext),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      homeWeatherRepository: SwiftDataHomeWeatherRepository(modelContext: modelContext),
      historyEvidenceRepository: SwiftDataHistoryEvidenceRepository(modelContext: modelContext),
      voiceAvailabilityProbe: voiceAvailabilityProbe,
      alarmScheduleMutator: alarmScheduleMutator,
      localResetRepository: localResetRepository,
      localResetJournalStore: resetJournalStore
    )
  }

  @MainActor
  func makeSessionStore() -> SessionStore {
    SessionStore()
  }

  @MainActor
  func makeOnboardingBuilder() -> any OnboardingFlowBuilding {
    let completeOnboardingUseCase = CompleteOnboardingUseCase(
      onboardingRepository: onboardingRepository,
      routineSuggestionService: routineSuggestionService,
      alarmScheduleMutator: alarmScheduleMutator
    )

    return DefaultOnboardingFlowBuilder(
      routineSuggestionService: routineSuggestionService,
      completeOnboardingUseCase: completeOnboardingUseCase
    )
  }

  @MainActor
  func makeRoutinePlayerBuilder() -> any RoutinePlayerBuilding {
    let resolver = ResolveRoutineExecutionUseCase(
      routineRepository: routineRepository
    )
    let saveRoutineRunUseCase = SaveRoutineRunUseCase(
      routineRunRepository: routineRunRepository
    )

    return DefaultRoutinePlayerBuilder(
      resolver: resolver,
      saveRoutineRunUseCase: saveRoutineRunUseCase
    )
  }

  #if DEBUG
  static func mock() -> DependencyContainer {
    let routineRepository = MockRoutineRepository()
    let localProfileRepository = MockLocalProfileRepository()

    return DependencyContainer(
      routineRepository: routineRepository,
      routineRunRepository: MockRoutineRunRepository(),
      localProfileRepository: localProfileRepository,
      localSettingsRepository: localProfileRepository,
      onboardingRepository: MockOnboardingRepository(
        localProfileRepository: localProfileRepository,
        routineRepository: routineRepository
      ),
      routineSuggestionService: LocalTemplateSuggestionService.shared,
      homeWeatherRepository: nil,
      historyEvidenceRepository: MockHistoryEvidenceRepository(),
      voiceAvailabilityProbe: UnavailableVoiceAvailabilityProbe(),
      alarmScheduleMutator: DebugLocalCommitAlarmScheduleMutator()
    )
  }
  #endif
}

#if DEBUG
@MainActor
final class DebugLocalCommitAlarmScheduleMutator: AlarmScheduleMutating {
  private var freezeToken: AlarmMutationFreezeToken?

  func commit(
    routines: [Routine],
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try ensureMutationAllowed()
    try localCommit()
  }

  func delete(
    routineID: UUID,
    scheduleID: UUID?,
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws {
    try ensureMutationAllowed()
    try localCommit()
  }

  func reconcile(routines: [Routine]) async throws {
    try ensureMutationAllowed()
  }

  private func ensureMutationAllowed() throws {
    guard freezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
  }

  func freezeAndDrain() async throws -> AlarmMutationFreezeToken {
    guard freezeToken == nil else {
      throw NotificationAlarmMutationError.mutationFrozen
    }

    let token = AlarmMutationFreezeToken()
    freezeToken = token
    return token
  }

  func cancelAll(
    scheduleIDs: [UUID],
    using token: AlarmMutationFreezeToken
  ) async throws {
    guard freezeToken == token else {
      throw NotificationAlarmMutationError.mutationFrozen
    }
  }

  func thaw(_ token: AlarmMutationFreezeToken) {
    guard freezeToken == token else {
      return
    }

    freezeToken = nil
  }

  func permissionState() async -> AlarmNotificationPermissionState {
    .authorized
  }
}
#endif
