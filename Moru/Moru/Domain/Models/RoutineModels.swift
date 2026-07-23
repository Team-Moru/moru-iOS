//
//  RoutineModels.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum SyncStatus: String, Codable, CaseIterable, Hashable {
  case localOnly
}

struct SyncMetadata: Codable, Hashable {
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

enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable {
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

struct VoiceProfile: Codable, Hashable, Identifiable {
  var id: String
  var displayName: String
  var assetVoiceCode: String

  init(
    id: String,
    displayName: String,
    assetVoiceCode: String
  ) {
    self.id = id
    self.displayName = displayName
    self.assetVoiceCode = assetVoiceCode
  }

  static let aoede = VoiceProfile(
    id: "moru.bundle.aoede",
    displayName: "민서",
    assetVoiceCode: "Aoede"
  )

  static let charon = VoiceProfile(
    id: "moru.bundle.charon",
    displayName: "현우",
    assetVoiceCode: "Charon"
  )

  static let kore = VoiceProfile(
    id: "moru.bundle.kore",
    displayName: "지유",
    assetVoiceCode: "Kore"
  )

  static let orus = VoiceProfile(
    id: "moru.bundle.orus",
    displayName: "은우",
    assetVoiceCode: "Orus"
  )

  static let localVoices = [VoiceProfile.aoede, .charon, .kore, .orus]

  static func fallback(id: String) -> VoiceProfile {
    localVoices.first { $0.id == id } ?? .aoede
  }
}

enum RoutineStepType: String, Codable, CaseIterable, Hashable {
  case confirm
  case timer
  case input
}

struct RoutineStep: Identifiable, Codable, Hashable {
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

struct AlarmSchedule: Identifiable, Codable, Hashable {
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

struct Routine: Identifiable, Codable, Hashable {
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

struct RoutineStepSnapshot: Identifiable, Codable, Hashable {
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

struct RoutineStepResult: Identifiable, Codable, Hashable {
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

struct RoutineRun: Identifiable, Codable, Hashable {
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

struct LocalProfile: Identifiable, Codable, Hashable {
  var id: UUID
  var displayName: String
  var selectedVoice: VoiceProfile
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    displayName: String = "모루 사용자",
    selectedVoice: VoiceProfile = .aoede,
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
