//
//  RoutineExecutionContract.swift
//  Moru
//

import Foundation

struct TrialRoutineExecutionRequest: Equatable {
  let routineID: UUID
}
struct RegularRoutineExecutionRequest: Equatable {
  enum Source: Equatable {
    case manual
    case scheduled
  }

  let routineID: UUID
  let source: Source
}

struct RoutineCompletionSummary: Equatable {
  let routineID: UUID
  let persistedRunID: UUID?
  let routineName: String
  let startedAt: Date
  let completedAt: Date
  let totalStepCount: Int
  let completedStepCount: Int
  let skippedStepCount: Int
  let endedEarly: Bool
  let completionRate: Double
}
struct RegularRoutineCompletionResult: Equatable {
  let summary: RoutineCompletionSummary
  let persistedRunID: UUID

  init?(_ summary: RoutineCompletionSummary) {
    guard let persistedRunID = summary.persistedRunID else {
      return nil
    }

    self.summary = summary
    self.persistedRunID = persistedRunID
  }
}

enum RoutineCompletionPresentation: Equatable {
  case trial(RoutineCompletionSummary)
  case regular(RegularRoutineCompletionResult)
}
enum RoutineCompletionSummaryValidationError: Error, Equatable {
  case completedBeforeStarted
}
enum RegularRoutineFinalizationError: Error, Equatable {
  case missingPersistedRunID
}

func validateRoutineCompletionTimestamps(
  startedAt: Date,
  completedAt: Date
) -> Result<Void, RoutineCompletionSummaryValidationError> {
  guard completedAt >= startedAt else {
    return .failure(.completedBeforeStarted)
  }

  return .success(())
}

enum RoutineTerminalReason: Equatable {
  case notFound
  case ineligible(RoutineIneligibilityReason)
  case invalidCompletionSummary(RoutineCompletionSummaryValidationError)
  case missingPersistedRunID
}

enum RoutinePlayerExit: Equatable {
  case summaryHome
  case summaryRecord(persistedRunID: UUID)
  case endedEarly
  case terminalUnavailable
  case userDismissed
}

enum RoutinePlayerEvent: Equatable {
  case resolutionRetryDisplayed(RoutineResolutionRetryReason)
  case terminalFailureDisplayed(RoutineTerminalReason)
  case runnableContentDidAppear(Date)
  case completionDisplayed(RoutineCompletionSummary)
  case exitRequested(RoutinePlayerExit)
}

typealias RoutinePlayerEventHandler = @MainActor (
  _ presentationToken: UUID,
  _ event: RoutinePlayerEvent
) -> Void

@MainActor
protocol TrialRoutineFinalizing: AnyObject {
  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError>
}

@MainActor
protocol RegularRoutineFinalizing: AnyObject {
  func finalize(
    _ request: SaveRoutineRunRequest
  ) throws -> RegularRoutineCompletionResult
}

func makeRoutineCompletionSummary(
  routine: Routine,
  persistedRunID: UUID?,
  startedAt: Date,
  completedAt: Date,
  results: [RoutineStepResult],
  endedEarly: Bool
) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
  switch validateRoutineCompletionTimestamps(
    startedAt: startedAt,
    completedAt: completedAt
  ) {
  case .success:
    break

  case .failure(let error):
    return .failure(error)
  }

  let plannedStepIDs = Set(routine.steps.map(\.id))
  let completedStepIDs = Set(
    results
      .filter(\.isCompleted)
      .map(\.stepID)
      .filter { plannedStepIDs.contains($0) }
  )
  let skippedStepIDs = Set(
    results
      .filter(\.skipped)
      .map(\.stepID)
      .filter { plannedStepIDs.contains($0) }
  ).subtracting(completedStepIDs)
  let totalStepCount = max(routine.steps.count, 0)
  let completedStepCount = min(completedStepIDs.count, totalStepCount)
  let skippedStepCount = min(
    skippedStepIDs.count,
    max(totalStepCount - completedStepCount, 0)
  )
  let completionRate: Double

  if totalStepCount == 0 {
    completionRate = 0
  } else {
    completionRate = min(
      max(Double(completedStepCount) / Double(totalStepCount), 0),
      1
    )
  }

  return .success(RoutineCompletionSummary(
    routineID: routine.id,
    persistedRunID: persistedRunID,
    routineName: routine.name,
    startedAt: startedAt,
    completedAt: completedAt,
    totalStepCount: totalStepCount,
    completedStepCount: completedStepCount,
    skippedStepCount: skippedStepCount,
    endedEarly: endedEarly,
    completionRate: completionRate
  ))
}
