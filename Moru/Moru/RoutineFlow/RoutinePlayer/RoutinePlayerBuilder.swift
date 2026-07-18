//
//  RoutinePlayerBuilder.swift
//  Moru
//

import Foundation
import SwiftUI

@MainActor
protocol RoutinePlayerBuilding: AnyObject {
  func makeTrial(
    request: TrialRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView

  func makeRegular(
    request: RegularRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView
}
@MainActor
final class DefaultRoutinePlayerBuilder: RoutinePlayerBuilding {
  private let resolver: any ResolveRoutineExecutionUseCaseProtocol
  private let saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol

  init(
    resolver: any ResolveRoutineExecutionUseCaseProtocol,
    saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol
  ) {
    self.resolver = resolver
    self.saveRoutineRunUseCase = saveRoutineRunUseCase
  }

  func makeTrial(
    request: TrialRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView {
    let viewModel = RoutinePlayerViewModel(
      request: request,
      resolver: resolver,
      finalizer: DefaultTrialRoutineFinalizer(),
      presentationToken: presentationToken,
      onEvent: onEvent
    )

    return AnyView(RoutinePlayerView(viewModel: viewModel))
  }

  func makeRegular(
    request: RegularRoutineExecutionRequest,
    presentationToken: UUID,
    onEvent: @escaping RoutinePlayerEventHandler
  ) -> AnyView {
    let viewModel = RoutinePlayerViewModel(
      request: request,
      resolver: resolver,
      finalizer: DefaultRegularRoutineFinalizer(
        saveRoutineRunUseCase: saveRoutineRunUseCase
      ),
      presentationToken: presentationToken,
      onEvent: onEvent
    )

    return AnyView(RoutinePlayerView(viewModel: viewModel))
  }
}

@MainActor
private final class DefaultTrialRoutineFinalizer: TrialRoutineFinalizing {
  func finalize(
    routine: Routine,
    startedAt: Date,
    completedAt: Date,
    results: [RoutineStepResult]
  ) -> Result<RoutineCompletionSummary, RoutineCompletionSummaryValidationError> {
    makeRoutineCompletionSummary(
      routine: routine,
      persistedRunID: nil,
      startedAt: startedAt,
      completedAt: completedAt,
      results: results,
      endedEarly: false
    )
  }
}

@MainActor
final class DefaultRegularRoutineFinalizer: RegularRoutineFinalizing {
  private let saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol

  init(saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol) {
    self.saveRoutineRunUseCase = saveRoutineRunUseCase
  }

  func finalize(
    _ request: SaveRoutineRunRequest
  ) throws -> RegularRoutineCompletionResult {
    _ = try validateRoutineCompletionTimestamps(
      startedAt: request.startedAt,
      completedAt: request.completedAt
    ).get()

    let savedRun = try saveRoutineRunUseCase.execute(request)
    let summary = try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: savedRun.id,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly
    ).get()

    guard let result = RegularRoutineCompletionResult(summary) else {
      throw RegularRoutineFinalizationError.missingPersistedRunID
    }

    return result
  }
}
