//
//  RoutineTTSAccountScopedDataCleaner.swift
//  Moru
//

import Foundation

enum RoutineTTSAccountCleanupError: Error, Equatable {
  case invalidMemberID
}

@MainActor
final class RoutineTTSAccountScopedDataCleaner:
  AccountScopedDataCleaning {
  private let linkRepository: any RoutineTTSLinkRepository
  private let removeAudioAssets: (UUID) throws -> Void
  private let preparationScheduler:
    (any RoutineTTSPreparationScheduling)?

  init(
    linkRepository: any RoutineTTSLinkRepository,
    audioFileStore: RoutineTTSAudioFileStore,
    preparationScheduler:
      (any RoutineTTSPreparationScheduling)? = nil
  ) {
    self.linkRepository = linkRepository
    self.preparationScheduler = preparationScheduler
    removeAudioAssets = { localRoutineID in
      try audioFileStore.removeAssets(
        localRoutineID: localRoutineID
      )
    }
  }

  init(
    linkRepository: any RoutineTTSLinkRepository,
    removeAudioAssets: @escaping (UUID) throws -> Void,
    preparationScheduler:
      (any RoutineTTSPreparationScheduling)? = nil
  ) {
    self.linkRepository = linkRepository
    self.removeAudioAssets = removeAudioAssets
    self.preparationScheduler = preparationScheduler
  }

  @MainActor
  func removeAccountScopedData(memberID: Int64) async throws {
    guard memberID > 0 else {
      throw RoutineTTSAccountCleanupError.invalidMemberID
    }

    preparationScheduler?.cancelAllPreparations()

    var firstError: Error?
    let localRoutineIDs: [UUID]

    do {
      localRoutineIDs = try linkRepository.localRoutineIDs(
        memberID: memberID
      )
    } catch {
      localRoutineIDs = []
      firstError = error
    }

    for localRoutineID in localRoutineIDs {
      do {
        try removeAudioAssets(localRoutineID)
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }

    do {
      try linkRepository.deleteLinks(memberID: memberID)
    } catch {
      if firstError == nil {
        firstError = error
      }
    }

    if let firstError {
      throw firstError
    }
  }
}
