//
//  SwiftDataRoutineTTSAudioManifestProvider.swift
//  Moru
//

import Foundation

@MainActor
final class SwiftDataRoutineTTSAudioManifestProvider:
  RoutineTTSAudioAssetManifestProviding {
  private let linkRepository: any RoutineTTSLinkRepository
  private weak var signedInMemberProvider:
    (any SignedInMemberProviding)?

  init(
    linkRepository: any RoutineTTSLinkRepository,
    signedInMemberProvider: (any SignedInMemberProviding)?
  ) {
    self.linkRepository = linkRepository
    self.signedInMemberProvider = signedInMemberProvider
  }

  func cachedAssets(
    localRoutineID: UUID,
    localStepID: UUID
  ) -> [RoutineTTSAudioAssetManifestItem] {
    guard let memberID = signedInMemberProvider?.signedInMemberID,
          memberID > 0,
          let link = try? linkRepository.link(
            localRoutineID: localRoutineID,
            memberID: memberID
          ),
          link.status == .ready else {
      return []
    }

    return link.assets.compactMap { asset in
      guard asset.localStepID == localStepID,
            let relativePath = asset.cachedRelativePath else {
        return nil
      }

      return RoutineTTSAudioAssetManifestItem(
        localRoutineID: localRoutineID,
        localStepID: localStepID,
        serverStepID: asset.serverStepID,
        cachedRelativePath: relativePath,
        orderIndex: asset.orderIndex
      )
    }
  }
}
