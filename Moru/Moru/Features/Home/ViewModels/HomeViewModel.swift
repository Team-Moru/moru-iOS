//
//  HomeViewModel.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
  private let loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol

  var state: HomeViewState

  init(
    loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol
  ) {
    self.loadHomeRoutinesUseCase = loadHomeRoutinesUseCase
    self.state = .loading(previousContent: nil)
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
      )
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
