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

enum HomeViewState: Equatable {
  case loading
  case content(HomeContentState)
  case empty(HomeContentState)
  case failed

  var loadState: HomeLoadState {
    switch self {
    case .loading:
      return .loading
    case .content:
      return .content
    case .empty:
      return .empty
    case .failed:
      return .failed
    }
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
    loadState == .failed ? "홈 정보를 불러오지 못했어요." : nil
  }

  private var contentState: HomeContentState? {
    switch self {
    case .content(let content), .empty(let content):
      return content
    case .loading, .failed:
      return nil
    }
  }
}

struct HomeContentState: Equatable {
  var userName: String
  var todayRoutine: HomeRoutineState?
  var manualRoutines: [HomeRoutineState]
  var todayProgress: HomeProgressState
  var streak: HomeStreakState
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

  static let placeholder = HomeProgressState(
    percentText: "100%",
    completedText: "8/8 완료",
    progress: 1
  )
}

struct HomeStreakState: Equatable {
  var currentDays: Int
  var bestDays: Int
  var completedWeekdays: Set<Weekday>

  static let empty = HomeStreakState(
    currentDays: 0,
    bestDays: 0,
    completedWeekdays: []
  )

  static let placeholder = HomeStreakState(
    currentDays: 12,
    bestDays: 18,
    completedWeekdays: [.sunday, .monday, .tuesday, .wednesday, .thursday]
  )
}

struct HomeRoutineState: Equatable, Identifiable {
  var id: UUID
  var title: String
  var statusText: String
  var estimatedDurationText: String
  var progressText: String
  var progress: Double
  var steps: [HomeRoutineStepState]

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
