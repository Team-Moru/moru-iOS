//
//  RoutineSettingViewState.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Foundation

enum RoutineSettingEntryPoint {
  case list
  case newRoutine
}

struct RoutineSettingViewState: Equatable {
  var routines: [RoutineSettingItemState]
  var isLoading: Bool
  var errorMessage: String?

  static let empty = RoutineSettingViewState(
    routines: [],
    isLoading: false,
    errorMessage: nil
  )
}

struct RoutineSettingItemState: Equatable, Identifiable {
  var id: UUID
  var title: String
  var stepCountText: String
  var estimatedDurationText: String
  var isActive: Bool
  var alarmDeliveryState: AlarmDeliveryState? = nil
  var alarmDeliveryBackend: AlarmDeliveryBackend? = nil

  var alarmDeliveryText: String? {
    switch alarmDeliveryState {
    case .scheduled where alarmDeliveryBackend == .alarmKit:
      "AlarmKit 예약됨"
    case .scheduled:
      "일반 알림으로 예약됨"
    case .authorizationRequired:
      "알람 권한 설정 필요"
    case .repairRequired:
      "예약 필요"
    case nil:
      nil
    }
  }

  var needsAlarmAction: Bool {
    alarmDeliveryState == .authorizationRequired
      || alarmDeliveryState == .repairRequired
  }
}

struct RoutineWeekdayConflictState: Equatable {
  var conflictingWeekdays: Set<Weekday>

  var weekdayText: String {
    let sortedWeekdays = conflictingWeekdays.sortedByDisplayOrder()

    guard sortedWeekdays.count != Weekday.allCases.count else {
      return "모든 요일"
    }

    return sortedWeekdays
      .map { "\($0.shortTitle)요일" }
      .joined(separator: ", ")
  }
}

struct RoutineDraftState: Equatable, Identifiable {
  var id: UUID
  var routineID: UUID?
  var title: String
  var summary: String
  var hour: Int
  var minute: Int
  var selectedWeekdays: Set<Weekday>
  var steps: [RoutineStepDraftState]
  var isActive: Bool

  init(
    id: UUID = UUID(),
    routineID: UUID? = nil,
    title: String = "",
    summary: String = "",
    hour: Int = 7,
    minute: Int = 0,
    selectedWeekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
    steps: [RoutineStepDraftState] = [],
    isActive: Bool = true
  ) {
    self.id = id
    self.routineID = routineID
    self.title = title
    self.summary = summary
    self.hour = hour
    self.minute = minute
    self.selectedWeekdays = selectedWeekdays
    self.steps = steps
    self.isActive = isActive
  }

  var canSave: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !selectedWeekdays.isEmpty
      && !steps.isEmpty
      && steps.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
}

struct RoutineStepDraftState: Equatable, Identifiable {
  var id: UUID
  var type: RoutineStepType
  var title: String
  var estimatedMinutes: Int

  init(
    id: UUID = UUID(),
    type: RoutineStepType = .confirm,
    title: String = "",
    estimatedMinutes: Int = 3
  ) {
    self.id = id
    self.type = type
    self.title = title
    self.estimatedMinutes = estimatedMinutes
  }
}

extension RoutineStepType {
  var routineSettingTitle: String {
    switch self {
    case .confirm:
      return "확인형"
    case .timer:
      return "타이머형"
    case .input:
      return "입력형"
    }
  }
}
