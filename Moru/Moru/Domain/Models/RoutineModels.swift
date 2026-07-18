//
//  RoutineModels.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

nonisolated enum SyncStatus: String, Codable, CaseIterable, Hashable, Sendable {
  case localOnly
}

nonisolated struct SyncMetadata: Codable, Hashable, Sendable {
  var remoteID: String?
  var status: SyncStatus
  var lastSyncedAt: Date?
  var remoteRevision: String?

  init(
    remoteID: String? = nil,
    status: SyncStatus = .localOnly,
    lastSyncedAt: Date? = nil,
    remoteRevision: String? = nil
  ) {
    self.remoteID = remoteID
    self.status = status
    self.lastSyncedAt = lastSyncedAt
    self.remoteRevision = remoteRevision
  }

  static let localOnly = SyncMetadata()
}

nonisolated enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
  case sunday = 1
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday

  var id: Int {
    rawValue
  }
}

extension Weekday {
  static let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
  static let displayOrder: [Weekday] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
  ]

  var shortTitle: String {
    switch self {
    case .sunday:
      return "일"
    case .monday:
      return "월"
    case .tuesday:
      return "화"
    case .wednesday:
      return "수"
    case .thursday:
      return "목"
    case .friday:
      return "금"
    case .saturday:
      return "토"
    }
  }

  var displayOrderIndex: Int {
    Self.displayOrder.firstIndex(of: self) ?? rawValue
  }
}

extension Sequence where Element == Weekday {
  func sortedByDisplayOrder() -> [Weekday] {
    sorted { $0.displayOrderIndex < $1.displayOrderIndex }
  }
}

nonisolated struct VoiceProfile: Codable, Hashable, Identifiable, Sendable {
  var id: String
  var displayName: String
  var localeIdentifier: String
  var avSpeechVoiceIdentifier: String?

  init(
    id: String,
    displayName: String,
    localeIdentifier: String,
    avSpeechVoiceIdentifier: String? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.localeIdentifier = localeIdentifier
    self.avSpeechVoiceIdentifier = avSpeechVoiceIdentifier
  }

  static let yuna = VoiceProfile(
    id: "moru.ko.yuna",
    displayName: "유나",
    localeIdentifier: "ko-KR",
    avSpeechVoiceIdentifier: "com.apple.ttsbundle.Yuna-compact"
  )
  static let sora = VoiceProfile(
    id: "moru.ko.sora",
    displayName: "소라",
    localeIdentifier: "ko-KR",
    avSpeechVoiceIdentifier: "com.apple.ttsbundle.Sora-compact"
  )
  static let moru = VoiceProfile(
    id: "moru-local",
    displayName: "모루 기본 목소리",
    localeIdentifier: "ko-KR"
  )

  static let localVoices = [VoiceProfile.yuna, .sora]

  static func catalogueVoice(id: String) -> VoiceProfile? {
    localVoices.first { $0.id == id }
  }

  static func preserving(id: String) -> VoiceProfile {
    if id == moru.id {
      return .moru
    }

    return catalogueVoice(id: id) ?? VoiceProfile(
      id: id,
      displayName: id,
      localeIdentifier: ""
    )
  }
}

nonisolated enum VoiceSelection: Sendable, Equatable {
  case available(VoiceProfile)
  case unavailable(rawID: String)

  init(rawID: String) {
    if let voice = VoiceProfile.catalogueVoice(id: rawID) {
      self = .available(voice)
    } else {
      self = .unavailable(rawID: rawID)
    }
  }

  var rawID: String {
    switch self {
    case .available(let voice):
      voice.id
    case .unavailable(let rawID):
      rawID
    }
  }
}

nonisolated enum VoiceMigrationState: String, Sendable, Equatable {
  case unresolved
  case resolved
  case fallbackNoticePending
  case fallbackNoticeAcknowledged
  case noFallbackNoticePending
  case noFallbackNoticeAcknowledged
  case corruptRecoveryPending
}

nonisolated enum SchemaMigrationMarker: String, Sendable, Equatable {
  case v2Unresolved
  case v2Resolved
}

nonisolated struct LocalSettingsSnapshot: Sendable, Equatable {
  let id: UUID
  let profileID: UUID
  let voiceMigrationState: VoiceMigrationState
  let originalVoiceID: String?
  let resolvedVoiceID: String?
  let migrationUpdatedAt: Date?
  let schemaMigrationMarker: SchemaMigrationMarker

  var pendingVoiceMigrationNotice: String? {
    voiceMigrationState == .fallbackNoticePending ? Self.fallbackNotice : nil
  }

  private static let fallbackNotice = "사용 가능한 목소리로 변경했어요"
}

nonisolated enum RoutineStepType: String, Codable, CaseIterable, Hashable, Sendable {
  case confirm
  case timer
  case input
}

nonisolated struct RoutineStep: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var presetItemID: String?
  var type: RoutineStepType
  var title: String
  var instruction: String
  var order: Int
  var estimatedSeconds: Int?
  var isRequired: Bool

  init(
    id: UUID = UUID(),
    presetItemID: String? = nil,
    type: RoutineStepType,
    title: String,
    instruction: String = "",
    order: Int,
    estimatedSeconds: Int? = nil,
    isRequired: Bool = true
  ) {
    self.id = id
    self.presetItemID = presetItemID
    self.type = type
    self.title = title
    self.instruction = instruction
    self.order = order
    self.estimatedSeconds = estimatedSeconds
    self.isRequired = isRequired
  }
}

nonisolated enum RoutineDuration {
  static func roundedMinutes(for estimatedSeconds: Int?) -> Int {
    let seconds = max(0, estimatedSeconds ?? 60)
    return max(1, (seconds + 59) / 60)
  }

  static func totalMinutes(for routine: Routine) -> Int {
    routine.steps.reduce(0) { total, step in
      total + roundedMinutes(for: step.estimatedSeconds)
    }
  }
}

nonisolated struct AlarmSchedule: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var hour: Int
  var minute: Int
  var weekdays: [Weekday]
  var soundName: String
  var isEnabled: Bool
  var includeWeather: Bool
  var includeFortune: Bool

  init(
    id: UUID = UUID(),
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    soundName: String = "moru-default",
    isEnabled: Bool = true,
    includeWeather: Bool = false,
    includeFortune: Bool = false
  ) {
    self.id = id
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays
    self.soundName = soundName
    self.isEnabled = isEnabled
    self.includeWeather = includeWeather
    self.includeFortune = includeFortune
  }
}

nonisolated struct Routine: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var name: String
  var summary: String
  var goalTags: [String]
  var steps: [RoutineStep]
  var alarmSchedule: AlarmSchedule?
  var isActive: Bool
  var createdAt: Date
  var updatedAt: Date
  var sync: SyncMetadata?

  init(
    id: UUID = UUID(),
    name: String,
    summary: String = "",
    goalTags: [String] = [],
    steps: [RoutineStep],
    alarmSchedule: AlarmSchedule? = nil,
    isActive: Bool = true,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    sync: SyncMetadata? = .localOnly
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.goalTags = goalTags
    self.steps = steps
    self.alarmSchedule = alarmSchedule
    self.isActive = isActive
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.sync = sync
  }
}

nonisolated struct RoutineStepSnapshot: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var stepID: UUID
  var stepTitle: String
  var stepType: RoutineStepType
  var stepOrder: Int
  var estimatedSeconds: Int?
  var isRequired: Bool

  init(
    id: UUID = UUID(),
    stepID: UUID,
    stepTitle: String,
    stepType: RoutineStepType,
    stepOrder: Int,
    estimatedSeconds: Int? = nil,
    isRequired: Bool = true
  ) {
    self.id = id
    self.stepID = stepID
    self.stepTitle = stepTitle
    self.stepType = stepType
    self.stepOrder = stepOrder
    self.estimatedSeconds = estimatedSeconds
    self.isRequired = isRequired
  }

  init(step: RoutineStep) {
    self.init(
      stepID: step.id,
      stepTitle: step.title,
      stepType: step.type,
      stepOrder: step.order,
      estimatedSeconds: step.estimatedSeconds,
      isRequired: step.isRequired
    )
  }
}

nonisolated struct RoutineStepResult: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var stepID: UUID
  var stepTitle: String
  var stepType: RoutineStepType
  var completedAt: Date?
  var skipped: Bool
  var inputText: String?
  var transcript: String?
  var durationSeconds: Int?

  init(
    id: UUID = UUID(),
    stepID: UUID,
    stepTitle: String,
    stepType: RoutineStepType,
    completedAt: Date? = nil,
    skipped: Bool = false,
    inputText: String? = nil,
    transcript: String? = nil,
    durationSeconds: Int? = nil
  ) {
    self.id = id
    self.stepID = stepID
    self.stepTitle = stepTitle
    self.stepType = stepType
    self.completedAt = completedAt
    self.skipped = skipped
    self.inputText = inputText
    self.transcript = transcript
    self.durationSeconds = durationSeconds
  }

  var isCompleted: Bool {
    completedAt != nil && !skipped
  }
}

nonisolated struct RoutineRun: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var routineID: UUID
  var routineName: String
  var startedAt: Date
  var completedAt: Date?
  var results: [RoutineStepResult]
  var plannedSteps: [RoutineStepSnapshot]
  var endedEarly: Bool
  var sync: SyncMetadata?

  init(
    id: UUID = UUID(),
    routineID: UUID,
    routineName: String,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    results: [RoutineStepResult] = [],
    plannedSteps: [RoutineStepSnapshot] = [],
    endedEarly: Bool = false,
    sync: SyncMetadata? = .localOnly
  ) {
    self.id = id
    self.routineID = routineID
    self.routineName = routineName
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.results = results
    self.plannedSteps = plannedSteps
    self.endedEarly = endedEarly
    self.sync = sync
  }

  init(
    id: UUID = UUID(),
    routine: Routine,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    results: [RoutineStepResult] = [],
    endedEarly: Bool = false,
    sync: SyncMetadata? = .localOnly
  ) {
    self.init(
      id: id,
      routineID: routine.id,
      routineName: routine.name,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      plannedSteps: routine.steps
        .sorted { $0.order < $1.order }
        .map(RoutineStepSnapshot.init),
      endedEarly: endedEarly,
      sync: sync
    )
  }

  var plannedStepCount: Int {
    plannedSteps.count
  }

  var completionRate: Double {
    let denominator = plannedStepCount

    guard denominator > 0 else {
      return 0
    }

    let completedStepIDs = Set(results.filter(\.isCompleted).map(\.stepID))
    let completedCount = plannedSteps.filter { completedStepIDs.contains($0.stepID) }.count

    return Double(completedCount) / Double(denominator)
  }
}

nonisolated struct LocalProfile: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var displayName: String
  var selectedVoice: VoiceProfile
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    displayName: String = "모루 사용자",
    selectedVoice: VoiceProfile = .moru,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.displayName = displayName
    self.selectedVoice = selectedVoice
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
