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

  init(
    localDataResetRepository: any LocalDataResetRepository,
    alarmService: any ProfileAlarmServicing
  ) {
    self.localDataResetRepository = localDataResetRepository
    self.alarmService = alarmService
  }

  func execute() async throws {
    try alarmService.cancelAllAlarms()
    try localDataResetRepository.resetToFreshInstallState()
  }
}
