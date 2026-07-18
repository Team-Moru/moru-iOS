//
//  SwiftDataHistoryEvidenceRepository.swift
//  Moru
//

import Foundation
import SwiftData

nonisolated final class SwiftDataHistoryEvidenceRepository: HistoryEvidenceRepository {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  @MainActor
  func fetchEvidence() throws -> HistoryEvidence {
    let persistedObservations = try modelContext.fetch(
      FetchDescriptor<PersistedScheduledAlarmStartObservation>(
        sortBy: [
          SortDescriptor(\.actionObservedAt, order: .forward),
          SortDescriptor(\.occurrenceID, order: .forward),
        ]
      )
    )
    let observations = try persistedObservations.map(
      SwiftDataV2Mapper.makeObservationSnapshot
    )
    let observationsByOccurrenceID = Dictionary(
      grouping: observations,
      by: \.occurrenceID
    )
    let persistedRootChainStates = try modelContext.fetch(
      FetchDescriptor<PersistedAlarmRootChainState>(
        sortBy: [
          SortDescriptor(\.updatedAt, order: .forward),
          SortDescriptor(\.rootOccurrenceID, order: .forward),
        ]
      )
    )
    let rootChainStates = try persistedRootChainStates.map { persistedRoot in
      let matchingTerminalObservation = terminalObservation(
        for: persistedRoot.terminalOccurrenceID,
        observationsByOccurrenceID: observationsByOccurrenceID
      )
      return try SwiftDataV2Mapper.makeAlarmRootChainStateSnapshot(
        from: persistedRoot,
        terminalObservation: matchingTerminalObservation
      )
    }

    return HistoryEvidence(
      observations: observations,
      rootChainStates: rootChainStates
    )
  }

  @MainActor
  private func terminalObservation(
    for occurrenceID: String?,
    observationsByOccurrenceID: [String: [ScheduledAlarmStartObservationSnapshot]]
  ) -> ScheduledAlarmStartObservationSnapshot? {
    guard let occurrenceID,
          let observations = observationsByOccurrenceID[occurrenceID],
          observations.count == 1 else {
      return nil
    }

    return observations[0]
  }
}
