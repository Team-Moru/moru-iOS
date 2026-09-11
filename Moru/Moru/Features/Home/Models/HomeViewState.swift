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
  case service(HomeWeatherServiceError)
  case unavailableConfiguration
}

enum HomeWeatherState: Equatable {
  case notRequested
  case requestingPermission
  case locating(UUID)
  case loading(UUID)
  case fresh(HomeWeatherContent)
  case stale(HomeWeatherContent)
  case denied
  case restricted
  case noFix
  case unavailable(HomeWeatherError)
}

enum HomeRoutineServerState: Equatable {
  case notConfigured
  case loading
  case applied
  case noActive
  case fallback(HomeRoutineServerFallbackReason)
}

enum HomeRoutineServerNotice: Equatable {
  case syncing
  case showingSavedRoutines

  static let syncingMessage = "루틴을 동기화하고 있어요."
  static let showingSavedRoutinesMessage =
    "서버 정보를 확인할 수 없어요."

  var message: String {
    switch self {
    case .syncing:
      Self.syncingMessage
    case .showingSavedRoutines:
      Self.showingSavedRoutinesMessage
    }
  }

  var canRetry: Bool {
    self == .showingSavedRoutines
  }
}

extension HomeRoutineServerState {
  var notice: HomeRoutineServerNotice? {
    switch self {
    case .loading, .fallback(.pendingLocalExecution):
      .syncing
    case .fallback(.remoteUnavailable):
      .showingSavedRoutines
    case .notConfigured,
         .applied,
         .noActive,
         .fallback(.signedOut),
         .fallback(.localActiveMissing),
         .fallback(.localActiveAmbiguous),
         .fallback(.remoteHasNoActiveLocalHasActive),
         .fallback(.activeGroupBindingMissing),
         .fallback(.activeGroupIdentityMismatch),
         .fallback(.activeRoutineBindingMissing),
         .fallback(.activeRoutineIdentityMismatch),
         .fallback(.inconsistentRemoteSnapshot),
         .fallback(.localSyncStateUnavailable),
         .fallback(.serverProjectionDayMismatch):
      nil
    }
  }
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

  var nextAlarmRoutine: HomeRoutineState? {
    contentState?.nextAlarmRoutine
  }

  var activeRoutines: [HomeRoutineState] {
    contentState?.activeRoutines ?? []
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
  /// 오늘 요일에 예약된 루틴. 진행률 카드가 "오늘"을 말하려면 이 선택이 필요하다.
  var todayRoutine: HomeRoutineState?
  /// 대표 카드의 주인공. 오늘 알람이 지났으면 내일 이후의 루틴이라 todayRoutine과 다를 수 있다.
  var nextAlarmRoutine: HomeRoutineState?
  var activeRoutines: [HomeRoutineState]
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
  var weekdays: [HomeWeekdayState]

  static let empty = HomeStreakState(
    currentDays: 0,
    bestDays: 0,
    weekdays: HomeWeekdayState.ordered(completedIDs: [])
  )

  static let placeholder = HomeStreakState(
    currentDays: 12,
    bestDays: 18,
    weekdays: HomeWeekdayState.ordered(
      completedIDs: ["sunday", "monday", "tuesday", "wednesday", "thursday"]
    )
  )
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

/// 홈 대표 카드가 보여 주는 알람 예약 상태. `AlarmDeliveryRecord`를 화면 문구로 좁힌 것이고,
/// 재시도·권한 요청 같은 조치는 루틴 탭 카드가 담당한다.
enum HomeAlarmDeliveryState: Equatable {
  case scheduled(AlarmDeliveryBackend)
  case authorizationRequired
  case repairRequired

  var text: String {
    switch self {
    case .scheduled(.alarmKit):
      "알람 예약됨"
    case .scheduled:
      "일반 알림으로 예약됨"
    case .authorizationRequired:
      "알람 권한 필요"
    case .repairRequired:
      "알람 예약 필요"
    }
  }

  var needsAttention: Bool {
    switch self {
    case .scheduled:
      false
    case .authorizationRequired, .repairRequired:
      true
    }
  }

  init(_ record: AlarmDeliveryRecord) {
    switch record.state {
    case .scheduled:
      // 예약에 성공했는데 backend가 비어 있는 기록은 관측된 적이 없지만,
      // 값이 없다고 배지를 감추기보다 보수적으로 일반 알림으로 표시한다.
      self = .scheduled(record.backend ?? .localNotification)
    case .authorizationRequired:
      self = .authorizationRequired
    case .repairRequired:
      self = .repairRequired
    }
  }
}

struct HomeRoutineState: Equatable, Identifiable {
  var id: UUID
  var title: String
  var statusText: String
  var scheduleText: String
  var stepSummaryText: String
  var completionText: String
  var estimatedDurationText: String
  var progressText: String
  var progress: Double
  var isActive: Bool
  var steps: [HomeRoutineStepState]
  /// 다음 알람 시각 문구. 대표 카드로 뽑힌 루틴에만 채워진다.
  var nextAlarmText: String?
  var alarmDelivery: HomeAlarmDeliveryState?

  static let placeholder = HomeRoutineState(
    id: UUID(),
    title: "기본 루틴",
    statusText: "진행 완료",
    scheduleText: "매일 06:15",
    stepSummaryText: "4개 스텝 · 20분",
    completionText: "4/4 완료",
    estimatedDurationText: "소요 시간 15분",
    progressText: "100%",
    progress: 1,
    isActive: true,
    steps: [
      HomeRoutineStepState(title: "물 한 잔 마시기", detail: "1:00", isCompleted: true),
      HomeRoutineStepState(title: "스트레칭 10분", detail: "11:19", isCompleted: true),
      HomeRoutineStepState(title: "오늘의 기록 한 줄", detail: "2:35", isCompleted: true),
      HomeRoutineStepState(title: "햇빛 5분 쬐기", detail: "5:02", isCompleted: true),
    ]
  )
}

enum HomeRoutineStepStatus: Equatable {
  case notStarted
  case completed
  case skipped
}

struct HomeRoutineStepState: Equatable, Identifiable {
  var id: UUID
  var title: String
  var detail: String
  var status: HomeRoutineStepStatus

  var isCompleted: Bool {
    status == .completed
  }

  var isSkipped: Bool {
    status == .skipped
  }

  var displayDetail: String {
    isSkipped ? HomeCopy.skipped : detail
  }

  var accessibilityValue: String {
    if isSkipped {
      return HomeCopy.skipped
    }

    return isCompleted ? "완료, \(detail)" : "미실행, \(detail)"
  }

  init(
    id: UUID = UUID(),
    title: String,
    detail: String,
    isCompleted: Bool,
    isSkipped: Bool = false
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    if isCompleted {
      status = .completed
    } else if isSkipped {
      status = .skipped
    } else {
      status = .notStarted
    }
  }

  init(
    id: UUID = UUID(),
    title: String,
    detail: String,
    status: HomeRoutineStepStatus
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.status = status
  }
}
