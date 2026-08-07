//
//  SwiftDataRoutineTTSLinkRepository.swift
//  Moru
//

import Foundation
import SwiftData

nonisolated final class SwiftDataRoutineTTSLinkRepository:
  RoutineTTSLinkRepository {
  private let modelContext: ModelContext
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    modelContext: ModelContext,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.modelContext = modelContext
    self.encoder = encoder
    self.decoder = decoder
  }

  @MainActor
  func link(
    localRoutineID: UUID,
    memberID: Int64
  ) throws -> RoutineTTSLink? {
    guard memberID > 0 else {
      throw RoutineTTSLinkRepositoryError.invalidLink(
        .invalidMemberID(memberID)
      )
    }

    guard let persisted = try persistedLink(localRoutineID: localRoutineID),
          persisted.memberID == memberID else {
      return nil
    }

    return try makeDomainLink(from: persisted)
  }

  @MainActor
  func localRoutineIDs(memberID: Int64) throws -> [UUID] {
    guard memberID > 0 else {
      throw RoutineTTSLinkRepositoryError.invalidLink(
        .invalidMemberID(memberID)
      )
    }

    let descriptor = FetchDescriptor<PersistedRoutineTTSLink>(
      predicate: #Predicate { $0.memberID == memberID }
    )
    return try modelContext.fetch(descriptor)
      .map(\.localRoutineID)
      .sorted { $0.uuidString < $1.uuidString }
  }

  @MainActor
  func saveLink(_ link: RoutineTTSLink) throws {
    try validate(link)
    let assetsRawValue = try encodeAssets(link.assets)

    do {
      if let persisted = try persistedLink(
        localRoutineID: link.localRoutineID
      ) {
        update(
          persisted,
          with: link,
          assetsRawValue: assetsRawValue
        )
      } else {
        modelContext.insert(
          makePersistedLink(
            from: link,
            assetsRawValue: assetsRawValue
          )
        )
      }

      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  @MainActor
  func deleteLink(localRoutineID: UUID) throws {
    guard let persisted = try persistedLink(
      localRoutineID: localRoutineID
    ) else {
      return
    }

    try performMutation {
      modelContext.delete(persisted)
    }
  }

  @MainActor
  func deleteLinks(memberID: Int64) throws {
    guard memberID > 0 else {
      throw RoutineTTSLinkRepositoryError.invalidLink(
        .invalidMemberID(memberID)
      )
    }

    let descriptor = FetchDescriptor<PersistedRoutineTTSLink>(
      predicate: #Predicate { $0.memberID == memberID }
    )
    let links = try modelContext.fetch(descriptor)
    try performMutation {
      links.forEach(modelContext.delete)
    }
  }

  @MainActor
  func deleteAllLinks() throws {
    let links = try modelContext.fetch(
      FetchDescriptor<PersistedRoutineTTSLink>()
    )
    try performMutation {
      links.forEach(modelContext.delete)
    }
  }

  @MainActor
  private func persistedLink(
    localRoutineID: UUID
  ) throws -> PersistedRoutineTTSLink? {
    var descriptor = FetchDescriptor<PersistedRoutineTTSLink>(
      predicate: #Predicate { $0.localRoutineID == localRoutineID }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  @MainActor
  private func makePersistedLink(
    from link: RoutineTTSLink,
    assetsRawValue: String
  ) -> PersistedRoutineTTSLink {
    PersistedRoutineTTSLink(
      localRoutineID: link.localRoutineID,
      memberID: link.memberID,
      serverRoutineGroupID: link.serverRoutineGroupID,
      contentFingerprint: link.contentFingerprint,
      statusRawValue: link.status.rawValue,
      assetsRawValue: assetsRawValue,
      lastFailureCode: link.lastFailureCode,
      createdAt: link.createdAt,
      updatedAt: link.updatedAt
    )
  }

  @MainActor
  private func update(
    _ persisted: PersistedRoutineTTSLink,
    with link: RoutineTTSLink,
    assetsRawValue: String
  ) {
    persisted.memberID = link.memberID
    persisted.serverRoutineGroupID = link.serverRoutineGroupID
    persisted.contentFingerprint = link.contentFingerprint
    persisted.statusRawValue = link.status.rawValue
    persisted.assetsRawValue = assetsRawValue
    persisted.lastFailureCode = link.lastFailureCode
    persisted.createdAt = link.createdAt
    persisted.updatedAt = link.updatedAt
  }

  @MainActor
  private func makeDomainLink(
    from persisted: PersistedRoutineTTSLink
  ) throws -> RoutineTTSLink {
    guard let status = RoutineTTSLinkStatus(
      rawValue: persisted.statusRawValue
    ) else {
      throw RoutineTTSLinkRepositoryError.invalidStatus(
        persisted.statusRawValue
      )
    }

    let link = RoutineTTSLink(
      localRoutineID: persisted.localRoutineID,
      memberID: persisted.memberID,
      serverRoutineGroupID: persisted.serverRoutineGroupID,
      contentFingerprint: persisted.contentFingerprint,
      status: status,
      assets: try decodeAssets(persisted.assetsRawValue),
      lastFailureCode: persisted.lastFailureCode,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt
    )
    try validate(link)
    return link
  }

  @MainActor
  private func encodeAssets(
    _ assets: [RoutineTTSAsset]
  ) throws -> String {
    let data = try encoder.encode(assets)
    guard let rawValue = String(data: data, encoding: .utf8) else {
      throw RoutineTTSLinkRepositoryError.invalidManifest
    }
    return rawValue
  }

  @MainActor
  private func decodeAssets(
    _ rawValue: String
  ) throws -> [RoutineTTSAsset] {
    guard let data = rawValue.data(using: .utf8) else {
      throw RoutineTTSLinkRepositoryError.invalidManifest
    }

    do {
      return try decoder.decode([RoutineTTSAsset].self, from: data)
    } catch {
      throw RoutineTTSLinkRepositoryError.invalidManifest
    }
  }

  @MainActor
  private func validate(_ link: RoutineTTSLink) throws {
    guard link.memberID > 0 else {
      throw invalidLink(.invalidMemberID(link.memberID))
    }

    if let serverRoutineGroupID = link.serverRoutineGroupID,
       serverRoutineGroupID <= 0 {
      throw invalidLink(
        .invalidServerRoutineGroupID(serverRoutineGroupID)
      )
    }

    guard !link.contentFingerprint
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty else {
      throw invalidLink(.emptyContentFingerprint)
    }

    if let failureCode = link.lastFailureCode,
       failureCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw invalidLink(.emptyFailureCode)
    }

    var serverStepIDs = Set<Int64>()
    var serverRoutineIDsByLocalStepID: [UUID: Set<Int64>] = [:]
    var orderIndicesByLocalStepID: [UUID: Set<Int>] = [:]

    for asset in link.assets {
      guard asset.serverRoutineID > 0 else {
        throw invalidLink(
          .invalidServerRoutineID(asset.serverRoutineID)
        )
      }
      guard asset.serverStepID > 0 else {
        throw invalidLink(.invalidServerStepID(asset.serverStepID))
      }
      guard asset.orderIndex >= 0 else {
        throw invalidLink(.invalidOrderIndex(asset.orderIndex))
      }
      guard serverStepIDs.insert(asset.serverStepID).inserted else {
        throw invalidLink(.duplicateServerStepID(asset.serverStepID))
      }

      serverRoutineIDsByLocalStepID[
        asset.localStepID,
        default: []
      ].insert(asset.serverRoutineID)

      let insertedOrderIndex = orderIndicesByLocalStepID[
        asset.localStepID,
        default: []
      ].insert(asset.orderIndex)
      guard insertedOrderIndex.inserted else {
        throw invalidLink(
          .duplicateOrderIndex(
            localStepID: asset.localStepID,
            orderIndex: asset.orderIndex
          )
        )
      }

      if let path = asset.cachedRelativePath,
         !Self.isValidRelativePath(path) {
        throw invalidLink(.invalidCachedRelativePath(path))
      }
    }

    for (localStepID, serverRoutineIDs) in serverRoutineIDsByLocalStepID
    where serverRoutineIDs.count != 1 {
      throw invalidLink(
        .inconsistentServerRoutineMapping(localStepID: localStepID)
      )
    }

    switch link.status {
    case .creating:
      guard link.serverRoutineGroupID == nil, link.assets.isEmpty else {
        throw invalidLink(.invalidCreatingState)
      }
    case .generating:
      guard link.serverRoutineGroupID != nil, !link.assets.isEmpty else {
        throw invalidLink(.invalidGeneratingState)
      }
    case .ready:
      guard link.serverRoutineGroupID != nil,
            !link.assets.isEmpty,
            link.assets.allSatisfy({
              $0.cachedRelativePath != nil
            }) else {
        throw invalidLink(.invalidReadyState)
      }
    case .failed, .stale:
      break
    }
  }

  @MainActor
  private func invalidLink(
    _ error: RoutineTTSLinkValidationError
  ) -> RoutineTTSLinkRepositoryError {
    .invalidLink(error)
  }

  nonisolated private static func isValidRelativePath(
    _ path: String
  ) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else {
      return false
    }

    let components = path.split(
      separator: "/",
      omittingEmptySubsequences: false
    )
    guard !components.isEmpty else {
      return false
    }

    return components.allSatisfy { component in
      guard !component.isEmpty else {
        return false
      }
      let decoded = String(component).removingPercentEncoding
        ?? String(component)
      return decoded != "." && decoded != ".."
    }
  }

  @MainActor
  private func performMutation(
    _ mutation: () -> Void
  ) throws {
    do {
      mutation()
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }
}
