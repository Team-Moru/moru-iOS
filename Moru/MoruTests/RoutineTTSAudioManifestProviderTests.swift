//
//  RoutineTTSAudioManifestProviderTests.swift
//  MoruTests
//

import SwiftData
import XCTest

@testable import Moru

@MainActor
final class RoutineTTSAudioManifestProviderTests: XCTestCase {
  func testOnlyReadyAssetsForCurrentAccountAreExposed() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let memberProvider = TTSManifestMemberProvider(memberID: 7)
    let provider = SwiftDataRoutineTTSAudioManifestProvider(
      linkRepository: repository,
      signedInMemberProvider: memberProvider
    )
    let routineID = UUID()
    let firstStepID = UUID()
    let secondStepID = UUID()
    try repository.saveLink(
      readyLink(
        routineID: routineID,
        memberID: 7,
        assets: [
          RoutineTTSAsset(
            localStepID: firstStepID,
            serverRoutineID: 20,
            serverStepID: 31,
            orderIndex: 1,
            cachedRelativePath: "routine/first/31.mp3"
          ),
          RoutineTTSAsset(
            localStepID: firstStepID,
            serverRoutineID: 20,
            serverStepID: 30,
            orderIndex: 0,
            cachedRelativePath: "routine/first/30.mp3"
          ),
          RoutineTTSAsset(
            localStepID: secondStepID,
            serverRoutineID: 21,
            serverStepID: 40,
            orderIndex: 0,
            cachedRelativePath: "routine/second/40.mp3"
          ),
        ]
      )
    )

    let currentAssets = provider.cachedAssets(
      localRoutineID: routineID,
      localStepID: firstStepID
    )

    XCTAssertEqual(
      Set(currentAssets.map(\.serverStepID)),
      [30, 31]
    )
    XCTAssertTrue(
      currentAssets.allSatisfy {
        $0.localRoutineID == routineID
          && $0.localStepID == firstStepID
      }
    )

    memberProvider.memberID = 8
    XCTAssertTrue(
      provider.cachedAssets(
        localRoutineID: routineID,
        localStepID: firstStepID
      ).isEmpty
    )
    memberProvider.memberID = nil
    XCTAssertTrue(
      provider.cachedAssets(
        localRoutineID: routineID,
        localStepID: firstStepID
      ).isEmpty
    )
  }

  func testGeneratingLinkIsNeverExposedForPlayback() throws {
    let container = try ModelContainer.moruContainer(
      isStoredInMemoryOnly: true
    )
    let repository = SwiftDataRoutineTTSLinkRepository(
      modelContext: container.mainContext
    )
    let memberProvider = TTSManifestMemberProvider(memberID: 7)
    let provider = SwiftDataRoutineTTSAudioManifestProvider(
      linkRepository: repository,
      signedInMemberProvider: memberProvider
    )
    let routineID = UUID()
    let stepID = UUID()
    try repository.saveLink(
      RoutineTTSLink(
        localRoutineID: routineID,
        memberID: 7,
        serverRoutineGroupID: 10,
        contentFingerprint: "fingerprint",
        status: .generating,
        assets: [
          RoutineTTSAsset(
            localStepID: stepID,
            serverRoutineID: 20,
            serverStepID: 30,
            orderIndex: 0
          ),
        ]
      )
    )

    XCTAssertTrue(
      provider.cachedAssets(
        localRoutineID: routineID,
        localStepID: stepID
      ).isEmpty
    )
  }

  private func readyLink(
    routineID: UUID,
    memberID: Int64,
    assets: [RoutineTTSAsset]
  ) -> RoutineTTSLink {
    RoutineTTSLink(
      localRoutineID: routineID,
      memberID: memberID,
      serverRoutineGroupID: 10,
      contentFingerprint: "fingerprint",
      status: .ready,
      assets: assets
    )
  }
}

@MainActor
private final class TTSManifestMemberProvider:
  SignedInMemberProviding {
  var memberID: Int64?

  init(memberID: Int64?) {
    self.memberID = memberID
  }

  var signedInMemberID: Int64? {
    memberID
  }
}
