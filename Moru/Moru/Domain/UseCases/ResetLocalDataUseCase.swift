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
  private let routineTTSAudioFileStore: RoutineTTSAudioFileStore?
  private let routineTTSPreparationScheduler:
    (any RoutineTTSPreparationScheduling)?

  init(
    localDataResetRepository: any LocalDataResetRepository,
    alarmService: any ProfileAlarmServicing,
    routineTTSAudioFileStore: RoutineTTSAudioFileStore? = nil,
    routineTTSPreparationScheduler:
      (any RoutineTTSPreparationScheduling)? = nil
  ) {
    self.localDataResetRepository = localDataResetRepository
    self.alarmService = alarmService
    self.routineTTSAudioFileStore = routineTTSAudioFileStore
    self.routineTTSPreparationScheduler =
      routineTTSPreparationScheduler
  }

  func execute() async throws {
    routineTTSPreparationScheduler?.cancelAllPreparations()
    try await alarmService.cancelAllAlarms()
    try localDataResetRepository.resetToFreshInstallState()
    try routineTTSAudioFileStore?.removeAllAssets()
  }
}
