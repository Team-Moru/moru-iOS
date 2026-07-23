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
  private let routineSettingUseCase: RoutineSettingUseCase
  private let alarmStateRepository: (any AlarmPlatformStateRepository)?
  private let alarmScheduleMutator: (any AlarmScheduleMutating)?
  private let calendar: Calendar

  var state: RoutineSettingViewState = .empty

  init(
    dependencies: DependencyContainer,
    calendar: Calendar = .current
  ) {
    self.routineRepository = dependencies.routineRepository
    self.alarmStateRepository = dependencies.alarmPlatformStateRepository
    self.alarmScheduleMutator = dependencies.alarmScheduleMutator
    self.routineSettingUseCase = RoutineSettingUseCase(
      routineRepository: dependencies.routineRepository,
      alarmScheduleMutator: dependencies.alarmScheduleMutator
    )
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

  @discardableResult
  func saveDraft(_ draft: RoutineDraftState) async -> Bool {
    do {
      let result = try await routineSettingUseCase.saveRoutine(
        from: makeMutation(from: draft)
      )
      load()
      reportAlarmRepairIfNeeded(result)
      return true
    } catch {
      state.errorMessage = "루틴을 저장하지 못했어요."
      return false
    }
  }

  @discardableResult
  func saveDraftResolvingWeekdayConflict(_ draft: RoutineDraftState) async -> Bool {
    do {
      let result = try await routineSettingUseCase.saveRoutine(
        from: makeMutation(from: draft),
        resolvingWeekdayConflict: true
      )
      load()
      reportAlarmRepairIfNeeded(result)
      return true
    } catch {
      state.errorMessage = "루틴을 저장하지 못했어요."
      return false
    }
  }

  func weekdayConflict(for draft: RoutineDraftState) -> RoutineWeekdayConflictState? {
    guard draft.isActive else {
      return nil
    }

    guard let conflictingWeekdays = try? routineSettingUseCase.weekdayConflict(
      for: makeMutation(from: draft)
    ) else {
      return nil
    }

    guard !conflictingWeekdays.isEmpty else {
      return nil
    }

    return RoutineWeekdayConflictState(conflictingWeekdays: conflictingWeekdays)
  }

  @discardableResult
  func routineActivationDidChange(id: UUID, isActive: Bool) async -> Bool {
    do {
      let result = try await routineSettingUseCase.updateActivation(
        routineID: id,
        isActive: isActive
      )
      load()
      reportAlarmRepairIfNeeded(result)
      return true
    } catch {
      state.errorMessage = "루틴 상태를 변경하지 못했어요."
      return false
    }
  }

  func activationConflict(for routineID: UUID) -> RoutineWeekdayConflictState? {
    guard var draft = makeDraft(for: routineID) else {
      return nil
    }

    draft.isActive = true
    return weekdayConflict(for: draft)
  }

  @discardableResult
  func activateRoutineResolvingWeekdayConflict(id: UUID) async -> Bool {
    do {
      let result = try await routineSettingUseCase.updateActivation(
        routineID: id,
        isActive: true,
        resolvingWeekdayConflict: true
      )
      load()
      reportAlarmRepairIfNeeded(result)
      return true
    } catch {
      state.errorMessage = "루틴 상태를 변경하지 못했어요."
      return false
    }
  }

  func deleteRoutine(id: UUID) async -> Bool {
    do {
      try await routineSettingUseCase.deleteRoutine(id: id)
      load()
      return true
    } catch {
      state.errorMessage = "알람 취소에 실패해 루틴을 삭제하지 않았어요."
      return false
    }
  }

  func retryAlarmScheduling(id: UUID) async {
    guard let routine = try? routineRepository.routine(id: id),
          let alarmScheduleMutator else {
      state.errorMessage = "알람 예약을 다시 시도하지 못했어요."
      return
    }

    do {
      let result = try await alarmScheduleMutator.apply(
        .synchronize(routines: [routine])
      )
      load()
      reportAlarmRepairIfNeeded(result)
    } catch {
      state.errorMessage = "알람 예약을 다시 시도하지 못했어요."
    }
  }

  private func makeItemState(from routine: Routine) -> RoutineSettingItemState {
    let record: AlarmDeliveryRecord?
    if let scheduleID = routine.alarmSchedule?.id,
       let alarmStateRepository {
      record = try? alarmStateRepository.record(scheduleID: scheduleID)
    } else {
      record = nil
    }
    let deliveryState: AlarmDeliveryState?
    if alarmStateRepository != nil,
       routine.isActive,
       routine.alarmSchedule?.isEnabled == true {
      deliveryState = record?.state ?? .repairRequired
    } else {
      deliveryState = nil
    }

    return RoutineSettingItemState(
      id: routine.id,
      title: routine.name,
      stepCountText: "\(routine.steps.count)개 항목",
      estimatedDurationText: "\(estimatedMinutes(for: routine))분",
      isActive: routine.isActive,
      alarmDeliveryState: deliveryState,
      alarmDeliveryBackend: record?.backend
    )
  }

  private func makeMutation(from draft: RoutineDraftState) -> RoutineSettingMutation {
    RoutineSettingMutation(
      routineID: draft.routineID,
      name: draft.title,
      summary: draft.summary,
      hour: draft.hour,
      minute: draft.minute,
      selectedWeekdays: draft.selectedWeekdays,
      steps: draft.steps.map { step in
        RoutineStepMutation(
          id: step.id,
          type: step.type,
          title: step.title,
          estimatedMinutes: step.estimatedMinutes
        )
      },
      isActive: draft.isActive
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

  private func reportAlarmRepairIfNeeded(_ result: AlarmMutationResult) {
    guard result.requiresRepair else {
      return
    }

    state.errorMessage = "루틴은 저장됐지만 알람 예약을 확인해 주세요."
  }
}
