//
//  RoutineModels.swift
//  Moru
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum SyncStatus: String, Codable, CaseIterable, Hashable {
  case localOnly
  case synced
  case pendingUpload
  case pendingDelete
  case conflict

  static func fallback(rawValue: String) -> SyncStatus {
    SyncStatus(rawValue: rawValue) ?? .localOnly
  }
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

struct VoiceProfile: Codable, Hashable, Identifiable {
  var id: String
  var displayName: String
  var localeIdentifier: String

  static let moru = VoiceProfile(
    id: "moru-local",
    displayName: "모루 기본 목소리",
    localeIdentifier: "ko-KR"
  )

  static let localVoices = [VoiceProfile.moru]

  static func fallback(id: String) -> VoiceProfile {
    localVoices.first { $0.id == id } ?? .moru
  }
}

enum RoutineStepType: String, Codable, CaseIterable, Hashable {
  case confirm
  case timer
  case input

  static func fallback(rawValue: String) -> RoutineStepType {
    RoutineStepType(rawValue: rawValue) ?? .confirm
  }
}

struct RoutineStep: Identifiable, Codable, Hashable {
  var id: UUID
  var type: RoutineStepType
  var title: String
  var instruction: String
  var order: Int
  var estimatedSeconds: Int?
  var isRequired: Bool

  init(
    id: UUID = UUID(),
    type: RoutineStepType,
    title: String,
    instruction: String = "",
    order: Int,
    estimatedSeconds: Int? = nil,
    isRequired: Bool = true
  ) {
    self.id = id
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
  var deletedAt: Date?
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
    deletedAt: Date? = nil,
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
    self.deletedAt = deletedAt
    self.sync = sync
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
  var endedEarly: Bool
  var sync: SyncMetadata?

  init(
    id: UUID = UUID(),
    routineID: UUID,
    routineName: String,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    results: [RoutineStepResult] = [],
    endedEarly: Bool = false,
    sync: SyncMetadata? = .localOnly
  ) {
    self.id = id
    self.routineID = routineID
    self.routineName = routineName
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.results = results
    self.endedEarly = endedEarly
    self.sync = sync
  }

  var completionRate: Double {
    guard !results.isEmpty else {
      return 0
    }

    let completedCount = results.filter(\.isCompleted).count
    return Double(completedCount) / Double(results.count)
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
