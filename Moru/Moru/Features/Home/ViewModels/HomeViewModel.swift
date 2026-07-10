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
  private let routineRepository: any RoutineRepository
  private let routineRunRepository: any RoutineRunRepository
  private let localProfileRepository: any LocalProfileRepository
  private let calendar: Calendar

  var state: HomeViewState

  init(
    dependencies: DependencyContainer,
    calendar: Calendar = .current
  ) {
    self.routineRepository = dependencies.routineRepository
    self.routineRunRepository = dependencies.routineRunRepository
    self.localProfileRepository = dependencies.localProfileRepository
    self.calendar = calendar
    self.state = .placeholder
  }

  func load() {
    state.isLoading = true
    state.errorMessage = nil

    do {
      let profile = try localProfileRepository.loadOrCreateDefaultProfile()
      let routines = try routineRepository.fetchActiveRoutines()
      let runs = try routineRunRepository.fetchRuns()
      let todayRoutine = currentRoutine(from: routines)
      let latestTodayRun: RoutineRun?
      if let todayRoutine {
        latestTodayRun = try todayRun(for: todayRoutine.id)
      } else {
        latestTodayRun = nil
      }

      state = HomeViewState(
        userName: profile.displayName,
        todayRoutine: todayRoutine.map { routine in
          makeRoutineState(routine: routine, todayRun: latestTodayRun)
        },
        todayProgress: makeProgressState(routine: todayRoutine, todayRun: latestTodayRun),
        streak: makeStreakState(from: runs),
        isLoading: false,
        errorMessage: nil
      )
    } catch {
      state.isLoading = false
      state.errorMessage = "홈 정보를 불러오지 못했어요."
    }
  }

  func startRoutineButtonDidTap() {
    // TODO: RoutinePlayer 라우팅이 정해지면 routineID를 넘겨 연결합니다.
  }

  func currentRoutineCardDidTap() {
    // TODO: RoutineSetting 상세 화면 라우팅이 정해지면 연결합니다.
  }

  private func currentRoutine(from routines: [Routine]) -> Routine? {
    let today = currentWeekday()
    let scheduledToday = routines.filter { routine in
      guard let schedule = routine.alarmSchedule else {
        return routine.isActive
      }

      return routine.isActive
        && schedule.isEnabled
        && schedule.weekdays.contains(today)
    }

    return scheduledToday.first ?? routines.first
  }

  private func todayRun(for routineID: UUID) throws -> RoutineRun? {
    let startOfDay = calendar.startOfDay(for: Date())

    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
      return nil
    }

    return try routineRunRepository
      .fetchRuns(for: routineID, from: startOfDay, to: endOfDay)
      .first
  }

  private func makeProgressState(
    routine: Routine?,
    todayRun: RoutineRun?
  ) -> HomeProgressState {
    guard let routine else {
      return .empty
    }

    let total = routine.steps.count
    let completed = completedStepCount(routine: routine, todayRun: todayRun)
    let progress = total == 0 ? 0 : Double(completed) / Double(total)

    return HomeProgressState(
      percentText: "\(Int((progress * 100).rounded()))%",
      completedText: "\(completed)/\(total) 완료",
      progress: progress
    )
  }

  private func makeRoutineState(
    routine: Routine,
    todayRun: RoutineRun?
  ) -> HomeRoutineState {
    let total = routine.steps.count
    let completed = completedStepCount(routine: routine, todayRun: todayRun)
    let progress = total == 0 ? 0 : Double(completed) / Double(total)
    let completedStepIDs = Set(todayRun?.results.filter(\.isCompleted).map(\.stepID) ?? [])

    return HomeRoutineState(
      id: routine.id,
      title: routine.name,
      statusText: progress >= 1 ? "진행 완료" : "진행 전",
      estimatedDurationText: "소요 시간 \(estimatedMinutes(for: routine))분",
      progressText: "\(Int((progress * 100).rounded()))%",
      progress: progress,
      steps: routine.steps
        .sorted { $0.order < $1.order }
        .map { step in
          HomeRoutineStepState(
            id: step.id,
            title: step.title,
            detail: stepDurationText(step),
            isCompleted: completedStepIDs.contains(step.id)
          )
        }
    )
  }

  private func completedStepCount(
    routine: Routine,
    todayRun: RoutineRun?
  ) -> Int {
    guard let todayRun else {
      return 0
    }

    let completedStepIDs = Set(todayRun.results.filter(\.isCompleted).map(\.stepID))
    return routine.steps.filter { completedStepIDs.contains($0.id) }.count
  }

  private func makeStreakState(from runs: [RoutineRun]) -> HomeStreakState {
    let completedDates = Set(
      runs.compactMap { run -> Date? in
        guard let completedAt = run.completedAt, !run.endedEarly else {
          return nil
        }

        return calendar.startOfDay(for: completedAt)
      }
    )

    let currentStreak = consecutiveCompletedDays(from: completedDates)
    let completedWeekdays = Set(
      completedDates
        .filter { calendar.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) }
        .map(weekday(from:))
    )

    return HomeStreakState(
      currentDays: currentStreak,
      bestDays: max(currentStreak, completedDates.count),
      completedWeekdays: completedWeekdays
    )
  }

  private func consecutiveCompletedDays(from completedDates: Set<Date>) -> Int {
    var count = 0
    var cursor = calendar.startOfDay(for: Date())

    while completedDates.contains(cursor) {
      count += 1

      guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
        break
      }

      cursor = previousDay
    }

    return count
  }

  private func estimatedMinutes(for routine: Routine) -> Int {
    let seconds = routine.steps.compactMap(\.estimatedSeconds).reduce(0, +)

    guard seconds > 0 else {
      return max(routine.steps.count * 3, 1)
    }

    return max(Int(ceil(Double(seconds) / 60)), 1)
  }

  private func stepDurationText(_ step: RoutineStep) -> String {
    guard let seconds = step.estimatedSeconds else {
      return "-"
    }

    let minutes = seconds / 60
    let remainder = seconds % 60

    return "\(minutes):\(String(format: "%02d", remainder))"
  }

  private func currentWeekday() -> Weekday {
    weekday(from: Date())
  }

  private func weekday(from date: Date) -> Weekday {
    let weekday = calendar.component(.weekday, from: date)
    return Weekday(rawValue: weekday) ?? .monday
  }
}
