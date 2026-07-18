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

  init(loadHomeRoutinesUseCase: any LoadHomeRoutinesUseCaseProtocol) {
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
      )
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
