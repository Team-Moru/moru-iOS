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
  var hour: Int
  var minute: Int
  var selectedWeekdays: Set<Weekday>
  var steps: [RoutineStepMutation]
  var isActive: Bool
}

struct RoutineStepMutation {
  var id: UUID
  var type: RoutineStepType
  var title: String
  var estimatedMinutes: Int
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
    resolvingWeekdayConflict: Bool = false
  ) async throws -> AlarmMutationResult {
    let routines: [Routine]
    if resolvingWeekdayConflict {
      routines = try routinesByResolvingWeekdayConflict(for: mutation)
      try routineRepository.saveRoutines(routines)
    } else {
      let routine = try makeRoutine(from: mutation)
      routines = [routine]
      try routineRepository.saveRoutine(routine)
    }

    return await synchronizeAlarmSchedules(for: routines)
  }

  func weekdayConflict(for mutation: RoutineSettingMutation) throws -> Set<Weekday> {
    guard mutation.isActive else {
      return []
    }

    let routines = try routineRepository.fetchRoutines()
    let selectedWeekdays = mutation.selectedWeekdays

    return routines.reduce(into: Set<Weekday>()) { result, routine in
      guard routine.id != mutation.routineID,
            routine.isActive,
            let schedule = routine.alarmSchedule,
            schedule.isEnabled else {
        return
      }

      result.formUnion(selectedWeekdays.intersection(Set(schedule.weekdays)))
    }
  }

  func updateActivation(
    routineID: UUID,
    isActive: Bool,
    resolvingWeekdayConflict: Bool = false
  ) async throws -> AlarmMutationResult {
    guard var routine = try routineRepository.routine(id: routineID) else {
      return .empty
    }

    if resolvingWeekdayConflict {
      let mutation = makeMutation(from: routine, isActive: true)
      let routines = try routinesByResolvingWeekdayConflict(for: mutation)
      try routineRepository.saveRoutines(routines)
      return await synchronizeAlarmSchedules(for: routines)
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

  private func routinesByResolvingWeekdayConflict(
    for mutation: RoutineSettingMutation
  ) throws -> [Routine] {
    var routines = try routinesWithWeekdayConflictRemoved(for: mutation)
    let routine = try makeRoutine(from: mutation)

    if let index = routines.firstIndex(where: { $0.id == routine.id }) {
      routines[index] = routine
    } else {
      routines.append(routine)
    }

    return routines
  }

  private func routinesWithWeekdayConflictRemoved(
    for mutation: RoutineSettingMutation
  ) throws -> [Routine] {
    var routines = try routineRepository.fetchRoutines()

    guard mutation.isActive else {
      return routines
    }

    let selectedWeekdays = mutation.selectedWeekdays

    for index in routines.indices {
      var routine = routines[index]
      guard routine.id != mutation.routineID,
            routine.isActive,
            var schedule = routine.alarmSchedule,
            schedule.isEnabled else {
        continue
      }

      let originalWeekdays = schedule.weekdays
      let remainingWeekdays = originalWeekdays.filter { !selectedWeekdays.contains($0) }

      guard remainingWeekdays.count != originalWeekdays.count else {
        continue
      }

      if remainingWeekdays.isEmpty {
        schedule.isEnabled = false
        routine.isActive = false
      } else {
        schedule.weekdays = remainingWeekdays
      }

      routine.alarmSchedule = schedule
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
      steps: [],
      createdAt: now,
      updatedAt: now
    )

    let existingStepsByID = Dictionary(uniqueKeysWithValues: routine.steps.map { ($0.id, $0) })
    let steps = mutation.steps.enumerated().map { index, step in
      var routineStep = existingStepsByID[step.id] ?? RoutineStep(
        id: step.id,
        type: step.type,
        title: "",
        order: index
      )

      routineStep.type = step.type
      routineStep.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
      routineStep.order = index
      routineStep.estimatedSeconds = max(step.estimatedMinutes, 1) * 60
      return routineStep
    }

    let alarmSchedule: AlarmSchedule
    if var schedule = routine.alarmSchedule {
      schedule.hour = mutation.hour
      schedule.minute = mutation.minute
      schedule.weekdays = mutation.selectedWeekdays.sortedByDisplayOrder()
      schedule.isEnabled = mutation.isActive
      alarmSchedule = schedule
    } else {
      alarmSchedule = AlarmSchedule(
        hour: mutation.hour,
        minute: mutation.minute,
        weekdays: mutation.selectedWeekdays.sortedByDisplayOrder(),
        isEnabled: mutation.isActive
      )
    }

    routine.name = mutation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    routine.summary = mutation.summary.trimmingCharacters(in: .whitespacesAndNewlines)
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
      hour: schedule?.hour ?? 7,
      minute: schedule?.minute ?? 0,
      selectedWeekdays: Set(schedule?.weekdays ?? Weekday.weekdays),
      steps: routine.steps
        .sorted { $0.order < $1.order }
        .map { step in
          RoutineStepMutation(
            id: step.id,
            type: step.type,
            title: step.title,
            estimatedMinutes: max((step.estimatedSeconds ?? 180) / 60, 1)
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
