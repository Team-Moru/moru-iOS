//
//  RoutineRun.swift
//  Moru
//

import Foundation

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
