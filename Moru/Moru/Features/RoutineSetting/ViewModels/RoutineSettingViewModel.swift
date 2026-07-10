//
//  RoutineSettingViewModel.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoutineSettingViewModel {
  private let routineRepository: any RoutineRepository
  private let calendar: Calendar

  var state: RoutineSettingViewState = .empty

  init(
    dependencies: DependencyContainer,
    calendar: Calendar = .current
  ) {
    self.routineRepository = dependencies.routineRepository
    self.calendar = calendar
  }

  func load() {
    state.isLoading = true
    state.errorMessage = nil

    do {
      let routines = try routineRepository.fetchRoutines()
      state = RoutineSettingViewState(
        routines: routines.map(makeItemState),
        isLoading: false,
        errorMessage: nil
      )
    } catch {
      state.isLoading = false
      state.errorMessage = "루틴 정보를 불러오지 못했어요."
    }
  }

  func makeNewDraft() -> RoutineDraftState {
    RoutineDraftState(title: "새 루틴")
  }

  func makeDraft(for routineID: UUID) -> RoutineDraftState? {
    guard let routine = try? routineRepository.routine(id: routineID) else {
      return nil
    }

    let schedule = routine.alarmSchedule
    return RoutineDraftState(
      routineID: routine.id,
      title: routine.name,
      summary: routine.summary,
      hour: schedule?.hour ?? 7,
      minute: schedule?.minute ?? 0,
      selectedWeekdays: Set(schedule?.weekdays ?? Weekday.weekdays),
      steps: routine.steps
        .sorted { $0.order < $1.order }
        .map { step in
          RoutineStepDraftState(
            id: step.id,
            type: step.type,
            title: step.title,
            estimatedMinutes: max((step.estimatedSeconds ?? 180) / 60, 1)
          )
        },
      isActive: routine.isActive
    )
  }

  func saveDraft(_ draft: RoutineDraftState) {
    do {
      let routine = makeRoutine(from: draft)
      try routineRepository.saveRoutine(routine)
      load()
    } catch {
      state.errorMessage = "루틴을 저장하지 못했어요."
    }
  }

  func saveDraftResolvingWeekdayConflict(_ draft: RoutineDraftState) {
    do {
      try removeConflictingWeekdays(for: draft)

      let routine = makeRoutine(from: draft)
      try routineRepository.saveRoutine(routine)
      load()
    } catch {
      state.errorMessage = "루틴을 저장하지 못했어요."
    }
  }

  func weekdayConflict(for draft: RoutineDraftState) -> RoutineWeekdayConflictState? {
    guard draft.isActive else {
      return nil
    }

    guard let routines = try? routineRepository.fetchRoutines() else {
      return nil
    }

    let selectedWeekdays = draft.selectedWeekdays
    let conflictingWeekdays = routines.reduce(into: Set<Weekday>()) { result, routine in
      guard routine.id != draft.routineID,
            routine.isActive,
            let schedule = routine.alarmSchedule,
            schedule.isEnabled else {
        return
      }

      result.formUnion(selectedWeekdays.intersection(Set(schedule.weekdays)))
    }

    guard !conflictingWeekdays.isEmpty else {
      return nil
    }

    return RoutineWeekdayConflictState(conflictingWeekdays: conflictingWeekdays)
  }

  func routineActivationDidChange(id: UUID, isActive: Bool) {
    do {
      try updateRoutineActivation(id: id, isActive: isActive)
      load()
    } catch {
      state.errorMessage = "루틴 상태를 변경하지 못했어요."
    }
  }

  func activationConflict(for routineID: UUID) -> RoutineWeekdayConflictState? {
    guard var draft = makeDraft(for: routineID) else {
      return nil
    }

    draft.isActive = true
    return weekdayConflict(for: draft)
  }

  func activateRoutineResolvingWeekdayConflict(id: UUID) {
    guard var draft = makeDraft(for: id) else {
      return
    }

    draft.isActive = true

    do {
      try removeConflictingWeekdays(for: draft)
      try updateRoutineActivation(id: id, isActive: true)
      load()
    } catch {
      state.errorMessage = "루틴 상태를 변경하지 못했어요."
    }
  }

  func deleteRoutine(id: UUID) {
    do {
      try routineRepository.deleteRoutine(id: id)
      load()
    } catch {
      state.errorMessage = "루틴을 삭제하지 못했어요."
    }
  }

  private func makeItemState(from routine: Routine) -> RoutineSettingItemState {
    RoutineSettingItemState(
      id: routine.id,
      title: routine.name,
      
      stepCountText: "\(routine.steps.count)개 항목",
      estimatedDurationText: "소요 시간 \(estimatedMinutes(for: routine))분",
      isActive: routine.isActive
    )
  }

  private func removeConflictingWeekdays(for draft: RoutineDraftState) throws {
    guard draft.isActive else {
      return
    }

    let selectedWeekdays = draft.selectedWeekdays
    let routines = try routineRepository.fetchRoutines()

    for var routine in routines {
      guard routine.id != draft.routineID,
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
      try routineRepository.saveRoutine(routine)
    }
  }

  private func updateRoutineActivation(id: UUID, isActive: Bool) throws {
    guard var routine = try routineRepository.routine(id: id) else {
      return
    }

    routine.isActive = isActive

    if var schedule = routine.alarmSchedule {
      schedule.isEnabled = isActive
      routine.alarmSchedule = schedule
    }

    routine.updatedAt = Date()
    try routineRepository.saveRoutine(routine)
  }

  private func makeRoutine(from draft: RoutineDraftState) -> Routine {
    let now = Date()
    let steps = draft.steps.enumerated().map { index, step in
      RoutineStep(
        id: step.id,
        type: step.type,
        title: step.title.trimmingCharacters(in: .whitespacesAndNewlines),
        order: index,
        estimatedSeconds: max(step.estimatedMinutes, 1) * 60
      )
    }

    return Routine(
      id: draft.routineID ?? UUID(),
      name: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
      summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
      steps: steps,
      alarmSchedule: AlarmSchedule(
        hour: draft.hour,
        minute: draft.minute,
        weekdays: draft.selectedWeekdays.sortedByDisplayOrder(),
        isEnabled: draft.isActive
      ),
      isActive: draft.isActive,
      createdAt: now,
      updatedAt: now
    )
  }

  private func scheduleText(for schedule: AlarmSchedule?) -> String {
    guard let schedule else {
      return "알람 없음"
    }

    let timeText = String(format: "%02d:%02d", schedule.hour, schedule.minute)
    let weekdaysSet = Set(schedule.weekdays)
    let weekdayText: String
    if weekdaysSet == Set(Weekday.weekdays) {
      weekdayText = "평일"
    } else if weekdaysSet == Set(Weekday.allCases) {
      weekdayText = "매일"
    } else if weekdaysSet == Set([.saturday, .sunday]) {
      weekdayText = "주말"
    } else {
      weekdayText = schedule.weekdays
        .sortedByDisplayOrder()
        .map(\.shortTitle)
        .joined(separator: " ")
    }

    return "\(timeText) · \(weekdayText)"
  }

  private func estimatedMinutes(for routine: Routine) -> Int {
    let seconds = routine.steps.compactMap(\.estimatedSeconds).reduce(0, +)

    guard seconds > 0 else {
      return max(routine.steps.count * 3, 1)
    }

    return max(Int(ceil(Double(seconds) / 60)), 1)
  }
}

extension Weekday {
  static let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
  static let displayOrder: [Weekday] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
  ]

  var shortTitle: String {
    switch self {
    case .sunday:
      return "일"
    case .monday:
      return "월"
    case .tuesday:
      return "화"
    case .wednesday:
      return "수"
    case .thursday:
      return "목"
    case .friday:
      return "금"
    case .saturday:
      return "토"
    }
  }

  var displayOrderIndex: Int {
    Self.displayOrder.firstIndex(of: self) ?? rawValue
  }
}

extension Sequence where Element == Weekday {
  func sortedByDisplayOrder() -> [Weekday] {
    sorted { $0.displayOrderIndex < $1.displayOrderIndex }
  }
}
