//
//  SwiftDataOnboardingRepository.swift
//  Moru
//
//  Created by Codex on 7/11/26.
//

import Foundation
import SwiftData

nonisolated final class SwiftDataOnboardingRepository: OnboardingRepository {
  private let modelContext: ModelContext
  private let routineSyncRepository: (any RoutineSyncRepository)?
  private weak var signedInMemberProvider: (any SignedInMemberProviding)?
  private let routineSyncWakeupRelay: RoutineSyncWakeupRelay?

  init(
    modelContext: ModelContext,
    routineSyncRepository: (any RoutineSyncRepository)? = nil,
    signedInMemberProvider: (any SignedInMemberProviding)? = nil,
    routineSyncWakeupRelay: RoutineSyncWakeupRelay? = nil
  ) {
    self.modelContext = modelContext
    self.routineSyncRepository = routineSyncRepository
    self.signedInMemberProvider = signedInMemberProvider
    self.routineSyncWakeupRelay = routineSyncWakeupRelay
  }

  @MainActor
  func fetchProfile() throws -> LocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )

    return try modelContext.fetch(descriptor).first.map(SwiftDataMapper.makeDomainProfile)
  }

  @MainActor
  func saveCompletion(profile: LocalProfile, routine: Routine) throws {
    do {
      let provisionalStore = SwiftDataProvisionalOnboardingDataStore(
        modelContext: modelContext
      )
      // Only a genuinely empty installation can acquire provisional
      // provenance. Existing data from older versions has no marker and must
      // never become replaceable merely because onboarding is shown again.
      let shouldRecordProvisionalMarker =
        try provisionalStore.localDataState() == .empty

      if let persistedProfile = try persistedProfile(id: profile.id) {
        SwiftDataMapper.update(persistedProfile, with: profile)
      } else {
        modelContext.insert(SwiftDataMapper.makePersistedProfile(from: profile))
      }

      let existingRoutine = try persistedRoutine(id: routine.id)
      if let persistedRoutine = existingRoutine {
        SwiftDataMapper.update(persistedRoutine, with: routine, in: modelContext)
      } else {
        modelContext.insert(SwiftDataMapper.makePersistedRoutine(from: routine))
      }

      if routine.isActive {
        try deactivateOtherActiveRoutines(except: routine.id, at: Date())
      }

      if let memberID = signedInMemberProvider?.signedInMemberID,
         let routineSyncRepository {
        let hasPendingCreate = try routineSyncRepository.mutation(
          memberID: memberID,
          operation: .createRoutineGroup,
          entityKind: .routineGroup,
          localEntityID: routine.id
        ) != nil
        if existingRoutine == nil || hasPendingCreate {
          try routineSyncRepository.stageEnqueue(
            EnqueuedRoutineSyncMutation(
              memberID: memberID,
              command: .createRoutineGroup(RoutineSyncGroupSnapshot(routine: routine))
            ),
            at: Date()
          )
          // The stored local ID creates an explicit dependency on the group
          // creation/binding. The sender only resolves its remote ID when the
          // group has settled successfully.
          try routineSyncRepository.stageEnqueue(
            EnqueuedRoutineSyncMutation(
              memberID: memberID,
              command: .completeOnboarding(groupLocalID: routine.id)
            ),
            at: Date()
          )
          if routine.isActive {
            try routineSyncRepository.stageEnqueue(
              EnqueuedRoutineSyncMutation(
                memberID: memberID,
                command: .selectActiveRoutineGroup(selectedGroupLocalID: routine.id)
              ),
              at: Date()
            )
          }
        }
      }

      if shouldRecordProvisionalMarker {
        try provisionalStore.stageRecord(
          profile: profile,
          routines: [routine],
          at: Date()
        )
      } else {
        // A repeated or non-fresh onboarding completion is established local
        // data. Clearing provenance never clears its content.
        try provisionalStore.stageInvalidate()
      }

      try modelContext.save()
      routineSyncWakeupRelay?.wake()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  private func persistedProfile(id: UUID) throws -> PersistedLocalProfile? {
    let descriptor = FetchDescriptor<PersistedLocalProfile>()
    return try modelContext.fetch(descriptor).first { $0.id == id }
  }

  @MainActor
  private func persistedRoutine(id: UUID) throws -> PersistedRoutine? {
    var descriptor = FetchDescriptor<PersistedRoutine>(
      predicate: #Predicate { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  @MainActor
  private func deactivateOtherActiveRoutines(except routineID: UUID, at date: Date) throws {
    let activeRoutines = try modelContext.fetch(
      FetchDescriptor<PersistedRoutine>(predicate: #Predicate { $0.isActive })
    )
    for persisted in activeRoutines where persisted.id != routineID {
      var routine = try SwiftDataMapper.makeDomainRoutine(from: persisted)
      routine.isActive = false
      // Keep its weekday settings but prevent another platform alarm from
      // remaining armed while a different group becomes the single active one.
      routine.alarmSchedule?.isEnabled = false
      routine.updatedAt = date
      SwiftDataMapper.update(persisted, with: routine, in: modelContext)
    }
  }
}
