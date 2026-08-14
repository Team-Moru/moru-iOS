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
  private let routineRepository: any RoutineRepository
  private let routineRunRepository: any RoutineRunRepository
  private let localProfileRepository: any LocalProfileRepository
  private let guidancePlayer: any RoutineGuidancePlaying
  private let guidancePlaybackState: RoutineGuidancePlaybackState
  private let audioSessionCoordinator: RoutineAudioSessionCoordinator
  private weak var routineTTSWarmupCoordinator: (any RoutineTTSWarming)?

  init(
    resolver: any ResolveRoutineExecutionUseCaseProtocol,
    saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol,
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    localProfileRepository: any LocalProfileRepository,
    guidancePlayer: any RoutineGuidancePlaying,
    guidancePlaybackState: RoutineGuidancePlaybackState,
    audioSessionCoordinator: RoutineAudioSessionCoordinator,
    routineTTSWarmupCoordinator: (any RoutineTTSWarming)? = nil
  ) {
    self.resolver = resolver
    self.saveRoutineRunUseCase = saveRoutineRunUseCase
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.localProfileRepository = localProfileRepository
    self.guidancePlayer = guidancePlayer
    self.guidancePlaybackState = guidancePlaybackState
    self.audioSessionCoordinator = audioSessionCoordinator
    self.routineTTSWarmupCoordinator = routineTTSWarmupCoordinator
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
      guidanceCoordinator: makeGuidanceCoordinator(
        routineGroupLocalID: nil
      ),
      presentationToken: presentationToken,
      onEvent: onEvent
    )

    return AnyView(
      RoutinePlayerView(
        viewModel: viewModel,
        speechInputController: makeSpeechInputController()
      )
    )
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
        saveRoutineRunUseCase: saveRoutineRunUseCase,
        routineRepository: routineRepository,
        routineRunRepository: routineRunRepository
      ),
      guidanceCoordinator: makeGuidanceCoordinator(
        routineGroupLocalID: request.routineID
      ),
      presentationToken: presentationToken,
      onEvent: onEvent
    )

    return AnyView(
      RoutinePlayerView(
        viewModel: viewModel,
        speechInputController: makeSpeechInputController()
      )
    )
  }

  private func makeGuidanceCoordinator(
    routineGroupLocalID: UUID?
  ) -> RoutineGuidanceCoordinator {
    let selectedVoice = (try? localProfileRepository.fetchProfile())?
      .selectedVoice ?? .aoede

    return RoutineGuidanceCoordinator(
      player: guidancePlayer,
      playbackState: guidancePlaybackState,
      voiceCode: selectedVoice.assetVoiceCode,
      routineGroupLocalID: routineGroupLocalID,
      warmupCoordinator: routineTTSWarmupCoordinator
    )
  }

  private func makeSpeechInputController() -> SpeechInputController {
    SpeechInputController {
      AppleSpeechRecognitionSession(
        audioSessionCoordinator: self.audioSessionCoordinator
      )
    }
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
  private let routineRepository: any RoutineRepository
  private let routineRunRepository: any RoutineRunRepository
  private let streakCalculator: RoutineStreakCalculator

  init(
    saveRoutineRunUseCase: any SaveRoutineRunUseCaseProtocol,
    routineRepository: any RoutineRepository,
    routineRunRepository: any RoutineRunRepository,
    calendar: Calendar = .current
  ) {
    self.saveRoutineRunUseCase = saveRoutineRunUseCase
    self.routineRepository = routineRepository
    self.routineRunRepository = routineRunRepository
    self.streakCalculator = RoutineStreakCalculator(calendar: calendar)
  }

  func finalize(
    _ request: SaveRoutineRunRequest
  ) throws -> RoutineCompletionSummary {
    _ = try validateRoutineCompletionTimestamps(
      startedAt: request.startedAt,
      completedAt: request.completedAt
    ).get()

    let savedRun = try saveRoutineRunUseCase.execute(request)
    let schedules = try routineRepository.fetchActiveRoutines()
      .compactMap(RoutineStreakSchedule.init)
    let streak = streakCalculator.calculate(
      from: try routineRunRepository.fetchRuns(),
      schedules: schedules,
      asOf: request.completedAt
    )

    return try makeRoutineCompletionSummary(
      routine: request.routine,
      persistedRunID: savedRun.id,
      startedAt: request.startedAt,
      completedAt: request.completedAt,
      results: request.results,
      endedEarly: request.endedEarly,
      streak: streak
    ).get()
  }
}
