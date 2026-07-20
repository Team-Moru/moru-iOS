//
//  ResetLocalDataUseCase.swift
//  Moru
//
//  Created by Codex on 7/13/26.
//

import Foundation

@MainActor
struct ResetLocalDataUseCase {
  private let localDataResetRepository: any LocalDataResetRepository

  init(localDataResetRepository: any LocalDataResetRepository) {
    self.localDataResetRepository = localDataResetRepository
  }

  func reset() throws {
    try localDataResetRepository.resetToFreshInstallState()
  }
}
