//
//  RoutineSettingViewState.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Foundation

enum RoutineCreationFlowMode: Hashable, Identifiable {
  case onboarding
  case recommendedAddition
  case directAddition

  var id: Self {
    self
  }

  var completionDestination: RoutineCreationCompletionDestination {
    switch self {
    case .onboarding:
      return .routineTrial
    case .recommendedAddition, .directAddition:
      return .routineList
    }
  }

  var includesVoiceSelection: Bool {
    self == .onboarding
  }

  var includesCompletionTrial: Bool {
    self == .onboarding
  }
}

enum RoutineCreationCompletionDestination: Equatable {
  case routineTrial
  case routineList
}

enum RoutineSettingEntryPoint: Equatable {
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
  var goalTags: [String]
  var alarmScheduleID: UUID?
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
    goalTags: [String] = [],
    alarmScheduleID: UUID? = nil,
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
    self.goalTags = goalTags
    self.alarmScheduleID = alarmScheduleID
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
  var presetItemID: String?
  var type: RoutineStepType
  var title: String
  var instruction: String
  var estimatedMinutes: Int
  var isRequired: Bool

  init(
    id: UUID = UUID(),
    presetItemID: String? = nil,
    type: RoutineStepType = .confirm,
    title: String = "",
    instruction: String = "",
    estimatedMinutes: Int = 3,
    isRequired: Bool = true
  ) {
    self.id = id
    self.presetItemID = presetItemID
    self.type = type
    self.title = title
    self.instruction = instruction
    self.estimatedMinutes = estimatedMinutes
    self.isRequired = isRequired
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
