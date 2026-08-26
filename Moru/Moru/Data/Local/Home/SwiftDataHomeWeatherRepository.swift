//
//  SwiftDataHomeWeatherRepository.swift
//  Moru
//
//  Created by Codex on 7/22/26.
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataHomeWeatherRepository: HomeWeatherRepository {
  private static let maximumCacheAge: TimeInterval = 24 * 60 * 60

  private let modelContext: ModelContext
  private let now: @Sendable () -> Date

  init(
    modelContext: ModelContext,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.modelContext = modelContext
    self.now = now
  }

  func cachedWeather() throws -> HomeWeatherSnapshot? {
    let currentDate = now()
    let persistedSnapshots = try modelContext.fetch(
      FetchDescriptor<PersistedHomeWeatherSnapshot>()
    )
    var validSnapshots: [
      (model: PersistedHomeWeatherSnapshot, snapshot: HomeWeatherSnapshot)
    ] = []
    var didMutate = false

    for persisted in persistedSnapshots {
      do {
        let snapshot = try HomeWeatherSnapshotMapper.makeDomainSnapshot(
          from: persisted,
          now: currentDate
        )
        guard isWithinCacheLifetime(snapshot, now: currentDate) else {
          modelContext.delete(persisted)
          didMutate = true
          continue
        }

        validSnapshots.append((model: persisted, snapshot: snapshot))
      } catch {
        modelContext.delete(persisted)
        didMutate = true
      }
    }

    guard let newest = validSnapshots.max(
      by: { $0.snapshot.fetchedAt < $1.snapshot.fetchedAt }
    ) else {
      if didMutate {
        try modelContext.save()
      }
      return nil
    }

    for candidate in validSnapshots where candidate.model !== newest.model {
      modelContext.delete(candidate.model)
      didMutate = true
    }

    if didMutate {
      try modelContext.save()
    }

    return newest.snapshot
  }

  func saveWeather(_ snapshot: HomeWeatherSnapshot) throws {
    let currentDate = now()
    guard isWithinCacheLifetime(snapshot, now: currentDate) else {
      throw HomeWeatherRepositoryError.invalidCachedSnapshot
    }

    let persistedSnapshot = try HomeWeatherSnapshotMapper.makePersistedSnapshot(
      from: snapshot,
      now: currentDate
    )
    let existingSnapshots = try modelContext.fetch(
      FetchDescriptor<PersistedHomeWeatherSnapshot>()
    )
    existingSnapshots.forEach(modelContext.delete)
    modelContext.insert(persistedSnapshot)
    try modelContext.save()
  }

  func eraseCachedWeather() throws {
    let persistedSnapshots = try modelContext.fetch(
      FetchDescriptor<PersistedHomeWeatherSnapshot>()
    )
    guard !persistedSnapshots.isEmpty else {
      return
    }

    persistedSnapshots.forEach(modelContext.delete)
    try modelContext.save()
  }

  private func isWithinCacheLifetime(_ snapshot: HomeWeatherSnapshot, now: Date) -> Bool {
    snapshot.fetchedAt >= now.addingTimeInterval(-Self.maximumCacheAge)
  }
}
