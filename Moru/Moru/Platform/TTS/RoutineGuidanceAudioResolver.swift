//
//  RoutineGuidanceAudioResolver.swift
//  Moru
//

import Foundation

enum RoutineGuidanceAudioSource: Equatable {
  case remoteCache
  case bundled
}

struct RoutineGuidanceAudioPlaybackPlan: Equatable {
  let source: RoutineGuidanceAudioSource
  let urls: [URL]
}

@MainActor
protocol RoutineTTSAudioAssetManifestProviding: AnyObject {
  func cachedAssets(
    localRoutineID: UUID,
    localStepID: UUID
  ) -> [RoutineTTSAudioAssetManifestItem]
}

@MainActor
final class EmptyRoutineTTSAudioAssetManifestProvider:
  RoutineTTSAudioAssetManifestProviding {
  func cachedAssets(
    localRoutineID: UUID,
    localStepID: UUID
  ) -> [RoutineTTSAudioAssetManifestItem] {
    []
  }
}

@MainActor
protocol RoutineGuidanceAudioResolving: AnyObject {
  func playbackPlans(
    for request: RoutineGuidanceCueRequest
  ) -> [RoutineGuidanceAudioPlaybackPlan]
}

@MainActor
final class RemoteFirstRoutineGuidanceAudioResolver:
  RoutineGuidanceAudioResolving {
  private let resourceLoader: RoutineAudioResourceLoader
  private let remoteAudioFileStore: RoutineTTSAudioFileStore?
  private let remoteManifestProvider:
    (any RoutineTTSAudioAssetManifestProviding)?

  init(
    resourceLoader: RoutineAudioResourceLoader,
    remoteAudioFileStore: RoutineTTSAudioFileStore? = nil,
    remoteManifestProvider:
      (any RoutineTTSAudioAssetManifestProviding)? = nil
  ) {
    self.resourceLoader = resourceLoader
    self.remoteAudioFileStore = remoteAudioFileStore
    self.remoteManifestProvider = remoteManifestProvider
  }

  func playbackPlans(
    for request: RoutineGuidanceCueRequest
  ) -> [RoutineGuidanceAudioPlaybackPlan] {
    var plans: [RoutineGuidanceAudioPlaybackPlan] = []

    if let remotePlan = remotePlaybackPlan(for: request) {
      plans.append(remotePlan)
    }
    if let bundledPlan = bundledPlaybackPlan(for: request) {
      plans.append(bundledPlan)
    }

    return plans
  }

  private func remotePlaybackPlan(
    for request: RoutineGuidanceCueRequest
  ) -> RoutineGuidanceAudioPlaybackPlan? {
    guard request.kind == .intro,
          let localRoutineID = request.localRoutineID,
          let localStepID = request.localStepID,
          let remoteAudioFileStore,
          let remoteManifestProvider else {
      return nil
    }

    let assets = remoteManifestProvider.cachedAssets(
      localRoutineID: localRoutineID,
      localStepID: localStepID
    )
    guard !assets.isEmpty,
          assets.allSatisfy({
            $0.localRoutineID == localRoutineID
              && $0.localStepID == localStepID
              && $0.serverStepID > 0
              && $0.orderIndex >= 0
          }),
          Set(assets.map(\.serverStepID)).count == assets.count,
          Set(assets.map(\.orderIndex)).count == assets.count else {
      return nil
    }

    let orderedAssets = assets.sorted { lhs, rhs in
      lhs.orderIndex < rhs.orderIndex
    }
    let urls = orderedAssets.compactMap {
      remoteAudioFileStore.cachedAudioURL(
        relativePath: $0.cachedRelativePath
      )
    }
    guard urls.count == orderedAssets.count else {
      return nil
    }

    return RoutineGuidanceAudioPlaybackPlan(
      source: .remoteCache,
      urls: urls
    )
  }

  private func bundledPlaybackPlan(
    for request: RoutineGuidanceCueRequest
  ) -> RoutineGuidanceAudioPlaybackPlan? {
    guard let presetItemID = request.presetItemID,
          let cue = try? resourceLoader.cue(
            itemID: presetItemID,
            voiceCode: request.voiceCode,
            kind: request.kind
          ),
          let resourceURL = resourceLoader.resourceURL(for: cue) else {
      return nil
    }

    return RoutineGuidanceAudioPlaybackPlan(
      source: .bundled,
      urls: [resourceURL]
    )
  }
}
