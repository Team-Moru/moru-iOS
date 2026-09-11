//
//  LoadHomeRoutinesUseCase.swift
//  Moru
//

import Foundation

typealias HomeRoutineStreak = RoutineStreak

/// 홈 대표 카드가 주인공으로 삼는 "다음에 울릴 알람". 오늘 알람이 이미 지났으면
/// 내일이나 다음 요일의 알람이 된다.
struct HomeNextAlarm: Equatable {
  let routine: Routine
  let fireDate: Date
  let delivery: AlarmDeliveryRecord?
}

struct HomeRoutineLoadResult: Equatable {
  let profile: LocalProfile?
  let todayRoutine: Routine?
  let nextAlarm: HomeNextAlarm?
  let manualRoutines: [Routine]
  let todayRunsByRoutineID: [UUID: RoutineRun]
  let streak: HomeRoutineStreak
  let loadedAt: Date

  init(
    profile: LocalProfile?,
    todayRoutine: Routine?,
    nextAlarm: HomeNextAlarm? = nil,
    manualRoutines: [Routine],
    todayRunsByRoutineID: [UUID: RoutineRun],
    streak: HomeRoutineStreak,
    loadedAt: Date = Date()
  ) {
    self.profile = profile
    self.todayRoutine = todayRoutine
    self.nextAlarm = nextAlarm
    self.manualRoutines = manualRoutines
    self.todayRunsByRoutineID = todayRunsByRoutineID
    self.streak = streak
    self.loadedAt = loadedAt
  }
}

@MainActor
protocol LoadHomeRoutinesUseCaseProtocol: AnyObject {
  func execute() throws -> HomeRoutineLoadResult
}

@MainActor
final class LoadHomeRoutinesUseCase: LoadHomeRoutinesUseCaseProtocol {
  private let routineRepository: any RoutineRepository
  private let routineRunRepository: any RoutineRunRepository
  private let localProfileRepository: any LocalProfileRepository
  private let alarmPlatformStateRepository: (any AlarmPlatformStateRepository)?
  private let calendar: Calendar
  private let now: () -> Date
  private let streakCalculator: RoutineStreakCalculator

  init(
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    alarmPlatformStateRepository: (any AlarmPlatformStateRepository)? = nil,
    calendar: Calendar = .current,
    now: @escaping () -> Date = Date.init
  ) {
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.alarmPlatformStateRepository = alarmPlatformStateRepository
    self.calendar = calendar
    self.now = now
    self.streakCalculator = RoutineStreakCalculator(calendar: calendar)
  }

  func execute() throws -> HomeRoutineLoadResult {
    let currentDate = now()
    let profile = try localProfileRepository.fetchProfile()
    let activeRoutines = try routineRepository.fetchActiveRoutines().filter(\.isActive)
    let manualRoutines = manuallyLaunchableRoutines(from: activeRoutines)
    let todayRoutine = scheduledRoutine(for: currentDate, from: manualRoutines)
    let runs = try routineRunRepository.fetchRuns()

    return HomeRoutineLoadResult(
      profile: profile,
      todayRoutine: todayRoutine,
      nextAlarm: nextAlarm(after: currentDate, from: manualRoutines),
      manualRoutines: manualRoutines,
      todayRunsByRoutineID: latestTodayRuns(
        for: manualRoutines,
        from: runs,
        currentDate: currentDate
      ),
      streak: streakCalculator.calculate(
        from: runs,
        schedules: manualRoutines.compactMap(RoutineStreakSchedule.init),
        asOf: currentDate
      ),
      loadedAt: currentDate
    )
  }

  private func manuallyLaunchableRoutines(from routines: [Routine]) -> [Routine] {
    routines
      .filter { !$0.steps.isEmpty }
      .sorted { lhs, rhs in
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
      }
  }

  private func scheduledRoutine(for currentDate: Date, from routines: [Routine]) -> Routine? {
    let weekday = weekday(from: currentDate)

    return routines
      .filter { routine in
        guard let schedule = routine.alarmSchedule else {
          return false
        }

        return schedule.isEnabled && schedule.weekdays.contains(weekday)
      }
      .sorted { lhs, rhs in
        guard let lhsSchedule = lhs.alarmSchedule,
              let rhsSchedule = rhs.alarmSchedule else {
          return false
        }

        if lhsSchedule.hour != rhsSchedule.hour {
          return lhsSchedule.hour < rhsSchedule.hour
        }

        if lhsSchedule.minute != rhsSchedule.minute {
          return lhsSchedule.minute < rhsSchedule.minute
        }

        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
      }
      .first
  }

  /// 가장 먼저 울릴 알람. 같은 시각이면 오늘의 루틴을 고르는 규칙과 같은 순서로 깬다.
  private func nextAlarm(
    after currentDate: Date,
    from routines: [Routine]
  ) -> HomeNextAlarm? {
    let candidates = routines.compactMap { routine -> (routine: Routine, fireDate: Date)? in
      guard let fireDate = routine.alarmSchedule?.nextFireDate(
        after: currentDate,
        calendar: calendar
      ) else {
        return nil
      }

      return (routine, fireDate)
    }

    let earliest = candidates.min { lhs, rhs in
      if lhs.fireDate != rhs.fireDate {
        return lhs.fireDate < rhs.fireDate
      }

      if lhs.routine.createdAt != rhs.routine.createdAt {
        return lhs.routine.createdAt < rhs.routine.createdAt
      }

      return lhs.routine.id.uuidString < rhs.routine.id.uuidString
    }

    guard let earliest else {
      return nil
    }

    return HomeNextAlarm(
      routine: earliest.routine,
      fireDate: earliest.fireDate,
      delivery: deliveryRecord(for: earliest.routine)
    )
  }

  /// 예약 상태는 읽기 전용이다. 저장소가 없거나 읽기에 실패하면 배지를 감춘다.
  private func deliveryRecord(for routine: Routine) -> AlarmDeliveryRecord? {
    guard let alarmPlatformStateRepository,
          let scheduleID = routine.alarmSchedule?.id else {
      return nil
    }

    return try? alarmPlatformStateRepository.record(scheduleID: scheduleID)
  }

  private func latestTodayRuns(
    for routines: [Routine],
    from runs: [RoutineRun],
    currentDate: Date
  ) -> [UUID: RoutineRun] {
    let startOfDay = calendar.startOfDay(for: currentDate)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
      return [:]
    }

    let routineIDs = Set(routines.map(\.id))
    let todayRuns = runs
      .filter { run in
        routineIDs.contains(run.routineID)
          && run.startedAt >= startOfDay
          && run.startedAt < endOfDay
      }
      .sorted { lhs, rhs in
        if lhs.startedAt != rhs.startedAt {
          return lhs.startedAt > rhs.startedAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
      }

    return todayRuns.reduce(into: [:]) { result, run in
      if result[run.routineID] == nil {
        result[run.routineID] = run
      }
    }
  }

  private func weekday(from date: Date) -> Weekday {
    Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
  }
}
