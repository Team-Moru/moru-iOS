//
//  HomeViewState.swift
//  Moru
//
//  Created by Codex on 7/9/26.
//

import Foundation

enum HomeLoadState: Equatable {
  case loading
  case content
  case empty
  case failed
}

enum HomeFailureCategory: String, Equatable {
  case localRoutineData
}

enum HomeFailure: Equatable {
  case localRoutineDataUnavailable(diagnostic: String)

  var userMessage: String {
    "홈 정보를 불러오지 못했어요. 다시 시도해 주세요."
  }

  var diagnosticCategory: HomeFailureCategory {
    switch self {
    case .localRoutineDataUnavailable:
      .localRoutineData
    }
  }

  var diagnosticDescription: String {
    switch self {
    case .localRoutineDataUnavailable(let diagnostic):
      diagnostic
    }
  }
}

enum HomeWeatherError: Error, Equatable {
  case cacheReadFailed
  case cacheEraseFailed
  case cacheWriteFailed
  case service(HomeWeatherServiceError)
  case unavailableConfiguration
}

enum HomeWeatherState: Equatable {
  case notRequested
  case requestingPermission
  case locating(UUID)
  case loading(UUID)
  case fresh(HomeWeatherSnapshot)
  case stale(HomeWeatherSnapshot)
  case denied
  case restricted
  case noFix
  case unavailable(HomeWeatherError)
}

enum HomeViewState: Equatable {
  case loading(previousContent: HomeContentState?)
  case content(HomeContentState)
  case empty(HomeContentState)
  case failed(HomeFailure, previousContent: HomeContentState?)

  var loadState: HomeLoadState {
    switch self {
    case .loading:
      .loading
    case .content:
      .content
    case .empty:
      .empty
    case .failed:
      .failed
    }
  }

  var failure: HomeFailure? {
    guard case .failed(let failure, previousContent: _) = self else {
      return nil
    }

    return failure
  }

  var userName: String {
    contentState?.userName ?? ""
  }

  var todayRoutine: HomeRoutineState? {
    contentState?.todayRoutine
  }

  var manualRoutines: [HomeRoutineState] {
    contentState?.manualRoutines ?? []
  }

  var todayProgress: HomeProgressState {
    contentState?.todayProgress ?? .empty
  }

  var streak: HomeStreakState {
    contentState?.streak ?? .empty
  }

  var isLoading: Bool {
    loadState == .loading
  }

  var errorMessage: String? {
    failure?.userMessage
  }

  var routineContent: HomeContentState? {
    switch self {
    case .loading(let previousContent), .failed(_, let previousContent):
      previousContent
    case .content(let content):
      content
    case .empty:
      nil
    }
  }

  private var contentState: HomeContentState? {
    switch self {
    case .loading(let previousContent), .failed(_, let previousContent):
      previousContent
    case .content(let content), .empty(let content):
      content
    }
  }
}

struct HomeContentState: Equatable {
  var userName: String
  var todayRoutine: HomeRoutineState?
  var manualRoutines: [HomeRoutineState]
  var todayProgress: HomeProgressState
  var streak: HomeStreakState
  var weather: HomeWeatherState = .notRequested
}

struct HomeProgressState: Equatable {
  var percentText: String
  var completedText: String
  var progress: Double

  static let empty = HomeProgressState(
    percentText: "0%",
    completedText: "0/0 완료",
    progress: 0
  )

  #if DEBUG
  static let placeholder = HomeProgressState(
    percentText: "100%",
    completedText: "8/8 완료",
    progress: 1
  )
  #endif
}

struct HomeStreakState: Equatable {
  var currentDays: Int
  var bestDays: Int
  var weekdays: [HomeWeekdayState]

  static let empty = HomeStreakState(
    currentDays: 0,
    bestDays: 0,
    weekdays: HomeWeekdayState.ordered(completedIDs: [])
  )

  #if DEBUG
  static let placeholder = HomeStreakState(
    currentDays: 12,
    bestDays: 18,
    weekdays: HomeWeekdayState.ordered(
      completedIDs: ["sunday", "monday", "tuesday", "wednesday", "thursday"]
    )
  )
  #endif
}

struct HomeWeekdayState: Equatable, Identifiable {
  let id: String
  let label: String
  let isCompleted: Bool

  private static let weekdayDefinitions: [(id: String, label: String)] = [
    (id: "monday", label: "월"),
    (id: "tuesday", label: "화"),
    (id: "wednesday", label: "수"),
    (id: "thursday", label: "목"),
    (id: "friday", label: "금"),
    (id: "saturday", label: "토"),
    (id: "sunday", label: "일"),
  ]

  static func ordered(completedIDs: Set<String>) -> [HomeWeekdayState] {
    weekdayDefinitions.map { definition in
      HomeWeekdayState(
        id: definition.id,
        label: definition.label,
        isCompleted: completedIDs.contains(definition.id)
      )
    }
  }
}

struct HomeRoutineState: Equatable, Identifiable {
  var id: UUID
  var title: String
  var statusText: String
  var estimatedDurationText: String
  var progressText: String
  var progress: Double
  var steps: [HomeRoutineStepState]

  #if DEBUG
  static let placeholder = HomeRoutineState(
    id: UUID(),
    title: "기본 루틴",
    statusText: "진행 완료",
    estimatedDurationText: "소요 시간 15분",
    progressText: "100%",
    progress: 1,
    steps: [
      HomeRoutineStepState(title: "물 한 잔 마시기", detail: "1:00", isCompleted: true),
      HomeRoutineStepState(title: "스트레칭 10분", detail: "11:19", isCompleted: true),
      HomeRoutineStepState(title: "오늘의 기록 한 줄", detail: "2:35", isCompleted: true),
      HomeRoutineStepState(title: "햇빛 5분 쬐기", detail: "5:02", isCompleted: true),
    ]
  )
  #endif
}

struct HomeRoutineStepState: Equatable, Identifiable {
  var id: UUID
  var title: String
  var detail: String
  var isCompleted: Bool

  init(
    id: UUID = UUID(),
    title: String,
    detail: String,
    isCompleted: Bool
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.isCompleted = isCompleted
  }
}
