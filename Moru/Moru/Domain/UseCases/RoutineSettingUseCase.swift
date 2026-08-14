//
//  RoutineSettingUseCase.swift
//  Moru
//
//  Created by Codex on 7/12/26.
//

import Foundation

struct RoutineSettingMutation {
  var routineID: UUID?
  var name: String
  var summary: String
  var goalTags: [String] = []
  var alarmScheduleID: UUID? = nil
  var hour: Int
  var minute: Int
  var selectedWeekdays: Set<Weekday>
  var includeWeather: Bool? = nil
  var includeFortune: Bool? = nil
  var steps: [RoutineStepMutation]
  var isActive: Bool
}

struct RoutineStepMutation {
  var id: UUID
  var presetItemID: String? = nil
  var type: RoutineStepType
  var title: String
  var instruction: String = ""
  var estimatedMinutes: Int
  var isRequired: Bool = true
}

enum RoutineSettingError: Error, Equatable {
  case activeRoutineReplacementRequired
}

@MainActor
struct RoutineSettingUseCase {
  private let routineRepository: any RoutineRepository
  private let alarmScheduleMutator: (any AlarmScheduleMutating)?

  init(
    routineRepository: any RoutineRepository,
    alarmScheduleMutator: (any AlarmScheduleMutating)? = nil
  ) {
    self.routineRepository = routineRepository
    self.alarmScheduleMutator = alarmScheduleMutator
  }

  func saveRoutine(
    from mutation: RoutineSettingMutation,
    replacingActiveRoutine: Bool = false
  ) async throws -> AlarmMutationResult {
    let conflictingIDs = try activeRoutineConflictIDs(for: mutation)

    let routines: [Routine]
    if !conflictingIDs.isEmpty {
      guard replacingActiveRoutine else {
        throw RoutineSettingError.activeRoutineReplacementRequired
      }

      routines = try routinesByReplacingActiveRoutine(
        for: mutation,
        conflictingIDs: conflictingIDs
      )
      try routineRepository.saveRoutines(routines)
    } else {
      let routine = try makeRoutine(from: mutation)
      routines = [routine]
      try routineRepository.saveRoutine(routine)
    }

    return await synchronizeAlarmSchedules(for: routines)
  }

  func activeRoutineConflictIDs(
    for mutation: RoutineSettingMutation
  ) throws -> Set<UUID> {
    guard mutation.isActive else {
      return []
    }

    let routines = try routineRepository.fetchRoutines()
    return routines.reduce(into: Set<UUID>()) { result, routine in
      guard routine.id != mutation.routineID,
            routine.isActive,
            let schedule = routine.alarmSchedule,
            !mutation.selectedWeekdays.isDisjoint(with: schedule.weekdays) else {
        return
      }

      result.insert(routine.id)
    }
  }

  func updateActivation(
    routineID: UUID,
    isActive: Bool,
    replacingActiveRoutine: Bool = false
  ) async throws -> AlarmMutationResult {
    guard var routine = try routineRepository.routine(id: routineID) else {
      return .empty
    }

    if isActive {
      let mutation = makeMutation(from: routine, isActive: true)
      let conflictingIDs = try activeRoutineConflictIDs(for: mutation)

      if !conflictingIDs.isEmpty {
        guard replacingActiveRoutine else {
          throw RoutineSettingError.activeRoutineReplacementRequired
        }

        let routines = try routinesByReplacingActiveRoutine(
          for: mutation,
          conflictingIDs: conflictingIDs
        )
        try routineRepository.saveRoutines(routines)
        return await synchronizeAlarmSchedules(for: routines)
      }
    }

    routine.isActive = isActive

    if var schedule = routine.alarmSchedule {
      schedule.isEnabled = isActive
      routine.alarmSchedule = schedule
    }

    routine.updatedAt = Date()
    try routineRepository.saveRoutine(routine)
    return await synchronizeAlarmSchedules(for: [routine])
  }

  func deleteRoutine(id: UUID) async throws {
    guard let routine = try routineRepository.routine(id: id) else {
      return
    }

    if let scheduleID = routine.alarmSchedule?.id,
       let alarmScheduleMutator {
      _ = try await alarmScheduleMutator.apply(.delete(scheduleID: scheduleID))
    }

    do {
      try routineRepository.deleteRoutine(id: id)
    } catch {
      if let alarmScheduleMutator {
        _ = try? await alarmScheduleMutator.apply(
          .synchronize(routines: [routine])
        )
      }
      throw error
    }
  }

  private func routinesByReplacingActiveRoutine(
    for mutation: RoutineSettingMutation,
    conflictingIDs: Set<UUID>
  ) throws -> [Routine] {
    var routines = try routinesWithConflictingRoutinesDisabled(
      conflictingIDs
    )
    let routine = try makeRoutine(from: mutation)

    if let index = routines.firstIndex(where: { $0.id == routine.id }) {
      routines[index] = routine
    } else {
      routines.append(routine)
    }

    return routines
  }

  private func routinesWithConflictingRoutinesDisabled(
    _ conflictingIDs: Set<UUID>
  ) throws -> [Routine] {
    var routines = try routineRepository.fetchRoutines().filter {
      conflictingIDs.contains($0.id)
    }

    for index in routines.indices {
      var routine = routines[index]
      guard conflictingIDs.contains(routine.id),
            routine.isActive else {
        continue
      }

      if var schedule = routine.alarmSchedule {
        schedule.isEnabled = false
        routine.alarmSchedule = schedule
      }

      routine.isActive = false
      routine.updatedAt = Date()
      routines[index] = routine
    }

    return routines
  }

  private func makeRoutine(from mutation: RoutineSettingMutation) throws -> Routine {
    let now = Date()
    var routine = try existingRoutine(for: mutation) ?? Routine(
      id: mutation.routineID ?? UUID(),
      name: mutation.name.trimmingCharacters(in: .whitespacesAndNewlines),
      goalTags: mutation.goalTags,
      steps: [],
      createdAt: now,
      updatedAt: now
    )

    let existingStepsByID = Dictionary(uniqueKeysWithValues: routine.steps.map { ($0.id, $0) })
    let steps = mutation.steps.enumerated().map { index, step in
      var routineStep = existingStepsByID[step.id] ?? RoutineStep(
        id: step.id,
        presetItemID: step.presetItemID,
        type: step.type,
        title: "",
        instruction: step.instruction,
        order: index
      )

      routineStep.presetItemID = step.presetItemID
      routineStep.type = step.type
      routineStep.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
      routineStep.instruction = step.instruction
      routineStep.order = index
      routineStep.estimatedSeconds = max(step.estimatedMinutes, 1) * 60
      routineStep.isRequired = step.isRequired
      return routineStep
    }

    let alarmSchedule: AlarmSchedule
    if var schedule = routine.alarmSchedule {
      schedule.hour = mutation.hour
      schedule.minute = mutation.minute
      schedule.weekdays = mutation.selectedWeekdays.sortedByDisplayOrder()
      schedule.isEnabled = mutation.isActive
      schedule.includeWeather =
        mutation.includeWeather ?? schedule.includeWeather
      schedule.includeFortune =
        mutation.includeFortune ?? schedule.includeFortune
      alarmSchedule = schedule
    } else {
      alarmSchedule = AlarmSchedule(
        id: mutation.alarmScheduleID ?? UUID(),
        hour: mutation.hour,
        minute: mutation.minute,
        weekdays: mutation.selectedWeekdays.sortedByDisplayOrder(),
        isEnabled: mutation.isActive,
        includeWeather: mutation.includeWeather ?? false,
        includeFortune: mutation.includeFortune ?? false
      )
    }

    routine.name = mutation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    routine.summary = mutation.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    routine.goalTags = mutation.goalTags
    routine.steps = steps
    routine.alarmSchedule = alarmSchedule
    routine.isActive = mutation.isActive
    routine.updatedAt = now
    return routine
  }

  private func existingRoutine(for mutation: RoutineSettingMutation) throws -> Routine? {
    guard let routineID = mutation.routineID else {
      return nil
    }

    return try routineRepository.routine(id: routineID)
  }

  private func makeMutation(from routine: Routine, isActive: Bool) -> RoutineSettingMutation {
    let schedule = routine.alarmSchedule

    return RoutineSettingMutation(
      routineID: routine.id,
      name: routine.name,
      summary: routine.summary,
      goalTags: routine.goalTags,
      alarmScheduleID: schedule?.id,
      hour: schedule?.hour ?? 7,
      minute: schedule?.minute ?? 0,
      selectedWeekdays: Set(schedule?.weekdays ?? Weekday.weekdays),
      includeWeather: schedule?.includeWeather,
      includeFortune: schedule?.includeFortune,
      steps: routine.steps
        .sorted { $0.order < $1.order }
        .map { step in
          RoutineStepMutation(
            id: step.id,
            presetItemID: step.presetItemID,
            type: step.type,
            title: step.title,
            instruction: step.instruction,
            estimatedMinutes: max((step.estimatedSeconds ?? 180) / 60, 1),
            isRequired: step.isRequired
          )
        },
      isActive: isActive
    )
  }

  private func synchronizeAlarmSchedules(
    for routines: [Routine]
  ) async -> AlarmMutationResult {
    guard let alarmScheduleMutator else {
      return .empty
    }

    return (try? await alarmScheduleMutator.apply(
      .synchronize(routines: routines)
    )) ?? AlarmMutationResult(
      records: routines.compactMap { routine in
        guard let request = AlarmScheduleRequest(routine: routine) else {
          return nil
        }
        return AlarmDeliveryRecord(
          request: request,
          backend: nil,
          state: .repairRequired,
          platformIdentifiers: [],
          lastErrorMessage: "alarm-state-persistence-failed",
          updatedAt: Date()
        )
      }
    )
  }
}
