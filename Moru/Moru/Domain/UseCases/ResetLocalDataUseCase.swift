//
//  ResetLocalDataUseCase.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation

@MainActor
protocol ResetLocalDataUseCaseProtocol: AnyObject {
  func execute() async throws
}

@MainActor
final class ResetLocalDataUseCase: ResetLocalDataUseCaseProtocol {
  private let localDataResetRepository: any LocalDataResetRepository
  private let alarmService: any ProfileAlarmServicing
  private let routineTTSAudioCacheCleaner:
    (any RoutineTTSAudioCacheCleaning)?

  init(
    localDataResetRepository: any LocalDataResetRepository,
    alarmService: any ProfileAlarmServicing,
    routineTTSAudioCacheCleaner:
      (any RoutineTTSAudioCacheCleaning)? = nil
  ) {
    self.localDataResetRepository = localDataResetRepository
    self.alarmService = alarmService
    self.routineTTSAudioCacheCleaner = routineTTSAudioCacheCleaner
  }

  func execute() async throws {
    try await alarmService.cancelAllAlarms()
    // Cache is fully recoverable. A filesystem cleanup failure must not block
    // the user's explicit local-data reset after alarm cancellation succeeds.
    try? await routineTTSAudioCacheCleaner?.removeAllRoutineTTSAudio()
    try localDataResetRepository.resetToFreshInstallState()
  }
}
