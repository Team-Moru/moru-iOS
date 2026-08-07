//
//  ServerRoutineTTSModels.swift
//  Moru
//

import Foundation

nonisolated struct ServerRoutineGroupCreationRequest:
  Equatable,
  Sendable {
  let localRoutineID: UUID
  let title: String
  let description: String?
  let alarmDaysRaw: String?
  let alarmTimeRaw: String?
  let weatherNotificationEnabled: Bool
  let routines: [ServerRoutineCreationRequest]
}

nonisolated struct ServerRoutineCreationRequest:
  Equatable,
  Sendable {
  let localStepID: UUID
  let title: String
  let type: ServerRoutineCreationItemType
  let durationSeconds: Int
}

nonisolated enum ServerRoutineCreationItemType:
  Equatable,
  Sendable {
  case check
  case timer
  case input
}

nonisolated struct ServerRoutineGroupCreationResult:
  Equatable,
  Sendable {
  let localRoutineID: UUID
  let routineGroupID: Int64
  let routines: [ServerCreatedRoutine]
}

nonisolated struct ServerCreatedRoutine: Equatable, Sendable {
  let localStepID: UUID
  let routineID: Int64
  let title: String
  let type: ServerRoutineCreationItemType
  let durationSeconds: Int
  let steps: [ServerCreatedRoutineStep]
}

nonisolated struct ServerCreatedRoutineStep: Equatable, Sendable {
  let stepID: Int64
  let content: String?
  let orderIndex: Int
}

nonisolated struct ServerRoutineGroupDeletionResult:
  Equatable,
  Sendable {
  /// ID supplied to the routine-group DELETE path.
  let requestedRoutineGroupID: Int64

  /// Swagger currently names this response field `routineId`, even for a
  /// routine-group deletion. Preserve it without treating it as a group ID.
  let serverAcknowledgedRoutineID: Int64?
}

nonisolated struct ServerRoutineTTSManifest: Equatable, Sendable {
  let routineGroupID: Int64
  let routines: [ServerRoutineTTSItem]
}

nonisolated struct ServerRoutineTTSItem: Equatable, Sendable {
  let routineID: Int64
  let title: String?
  let type: ServerRoutineItemType?
  let steps: [ServerRoutineTTSStep]
}

nonisolated struct ServerRoutineTTSStep: Equatable, Sendable {
  let stepID: Int64
  let content: String?
  let synthesizedIntro: String?
  let status: ServerRoutineTTSStatus
  let audioURL: URL?
}

nonisolated enum ServerRoutineTTSStatus: Equatable, Sendable {
  case pending
  case completed
  case failed
  case unknown(String)
}
