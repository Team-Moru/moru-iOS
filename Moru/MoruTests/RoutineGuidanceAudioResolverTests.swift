//
//  RoutineGuidanceAudioResolverTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

@MainActor
final class RoutineGuidanceAudioResolverTests: XCTestCase {
  func testFileStoreUsesStableServerStepPathAndRejectsUnsafeReads() throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = RoutineTTSAudioFileStore(rootDirectory: directory)
    let routineID = UUID()
    let stepID = UUID()
    let relativePath = try store.store(
      Data("audio".utf8),
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 91
    )

    XCTAssertEqual(
      relativePath,
      [
        routineID.uuidString.lowercased(),
        stepID.uuidString.lowercased(),
        "91.mp3",
      ].joined(separator: "/")
    )
    XCTAssertNotNil(store.cachedAudioURL(relativePath: relativePath))
    XCTAssertNil(store.cachedAudioURL(relativePath: "../outside.mp3"))
  }

  func testFileStoreRejectsEmptyAudioWithoutCreatingCacheEntry() {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = RoutineTTSAudioFileStore(rootDirectory: directory)

    XCTAssertThrowsError(
      try store.store(
        Data(),
        localRoutineID: UUID(),
        localStepID: UUID(),
        serverStepID: 1
      )
    ) { error in
      XCTAssertEqual(
        error as? RoutineTTSAudioFileStoreError,
        .emptyAudio
      )
    }
  }

  func testFileStoreRemovesOneRoutineWithoutDeletingOtherRoutine() throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = RoutineTTSAudioFileStore(rootDirectory: directory)
    let removedRoutineID = UUID()
    let retainedRoutineID = UUID()
    let removedFirstPath = try store.store(
      Data("first".utf8),
      localRoutineID: removedRoutineID,
      localStepID: UUID(),
      serverStepID: 1
    )
    let removedSecondPath = try store.store(
      Data("second".utf8),
      localRoutineID: removedRoutineID,
      localStepID: UUID(),
      serverStepID: 2
    )
    let retainedPath = try store.store(
      Data("retained".utf8),
      localRoutineID: retainedRoutineID,
      localStepID: UUID(),
      serverStepID: 3
    )

    try store.removeAssets(localRoutineID: removedRoutineID)

    XCTAssertNil(store.cachedAudioURL(relativePath: removedFirstPath))
    XCTAssertNil(store.cachedAudioURL(relativePath: removedSecondPath))
    XCTAssertNotNil(store.cachedAudioURL(relativePath: retainedPath))
  }

  func testIntroUsesCompleteRemoteManifestInOrderBeforeBundledFallback() throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let routineID = UUID()
    let stepID = UUID()
    let store = RoutineTTSAudioFileStore(rootDirectory: directory)
    let laterPath = try store.store(
      Data("later".utf8),
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 22
    )
    let earlierPath = try store.store(
      Data("earlier".utf8),
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 11
    )
    let provider = RoutineTTSAudioManifestStub(
      assets: [
        manifestItem(
          routineID: routineID,
          stepID: stepID,
          serverStepID: 22,
          relativePath: laterPath,
          orderIndex: 1
        ),
        manifestItem(
          routineID: routineID,
          stepID: stepID,
          serverStepID: 11,
          relativePath: earlierPath,
          orderIndex: 0
        ),
      ]
    )
    let resolver = RemoteFirstRoutineGuidanceAudioResolver(
      resourceLoader: RoutineAudioResourceLoader(),
      remoteAudioFileStore: store,
      remoteManifestProvider: provider
    )

    let plans = resolver.playbackPlans(
      for: RoutineGuidanceCueRequest(
        localRoutineID: routineID,
        localStepID: stepID,
        presetItemID: BundledVoiceAvailabilityProbe.previewItemID,
        voiceCode: VoiceProfile.aoede.assetVoiceCode,
        kind: .intro
      )
    )

    XCTAssertEqual(plans.map(\.source), [.remoteCache, .bundled])
    XCTAssertEqual(
      plans[0].urls.map(\.lastPathComponent),
      ["11.mp3", "22.mp3"]
    )
    XCTAssertEqual(plans[1].urls.count, 1)
  }

  func testIncompleteRemoteManifestFallsBackToBundledPlan() throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let routineID = UUID()
    let stepID = UUID()
    let store = RoutineTTSAudioFileStore(rootDirectory: directory)
    let cachedPath = try store.store(
      Data("cached".utf8),
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 1
    )
    let missingPath = RoutineTTSAudioFileStore.relativePath(
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 2
    )
    let provider = RoutineTTSAudioManifestStub(
      assets: [
        manifestItem(
          routineID: routineID,
          stepID: stepID,
          serverStepID: 1,
          relativePath: cachedPath,
          orderIndex: 0
        ),
        manifestItem(
          routineID: routineID,
          stepID: stepID,
          serverStepID: 2,
          relativePath: missingPath,
          orderIndex: 1
        ),
      ]
    )
    let resolver = RemoteFirstRoutineGuidanceAudioResolver(
      resourceLoader: RoutineAudioResourceLoader(),
      remoteAudioFileStore: store,
      remoteManifestProvider: provider
    )

    let plans = resolver.playbackPlans(
      for: RoutineGuidanceCueRequest(
        localRoutineID: routineID,
        localStepID: stepID,
        presetItemID: BundledVoiceAvailabilityProbe.previewItemID,
        voiceCode: VoiceProfile.aoede.assetVoiceCode,
        kind: .intro
      )
    )

    XCTAssertEqual(plans.map(\.source), [.bundled])
  }

  func testRemoteCacheIsIntroOnlyAndCustomMissingCacheIsSilent() throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let routineID = UUID()
    let stepID = UUID()
    let store = RoutineTTSAudioFileStore(rootDirectory: directory)
    let path = try store.store(
      Data("cached".utf8),
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 1
    )
    let provider = RoutineTTSAudioManifestStub(
      assets: [
        manifestItem(
          routineID: routineID,
          stepID: stepID,
          serverStepID: 1,
          relativePath: path,
          orderIndex: 0
        ),
      ]
    )
    let resolver = RemoteFirstRoutineGuidanceAudioResolver(
      resourceLoader: RoutineAudioResourceLoader(),
      remoteAudioFileStore: store,
      remoteManifestProvider: provider
    )

    let reminderPlans = resolver.playbackPlans(
      for: RoutineGuidanceCueRequest(
        localRoutineID: routineID,
        localStepID: stepID,
        presetItemID: BundledVoiceAvailabilityProbe.previewItemID,
        voiceCode: VoiceProfile.aoede.assetVoiceCode,
        kind: .remind
      )
    )
    let missingCustomPlans = resolver.playbackPlans(
      for: RoutineGuidanceCueRequest(
        localRoutineID: routineID,
        localStepID: UUID(),
        presetItemID: nil,
        voiceCode: VoiceProfile.aoede.assetVoiceCode,
        kind: .intro
      )
    )

    XCTAssertEqual(reminderPlans.map(\.source), [.bundled])
    XCTAssertTrue(missingCustomPlans.isEmpty)
  }

  func testCorruptRemotePlanFallsBackToPlayableBundledCue() async throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let routineID = UUID()
    let stepID = UUID()
    let store = RoutineTTSAudioFileStore(rootDirectory: directory)
    let path = try store.store(
      Data("not an audio file".utf8),
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: 1
    )
    let provider = RoutineTTSAudioManifestStub(
      assets: [
        manifestItem(
          routineID: routineID,
          stepID: stepID,
          serverStepID: 1,
          relativePath: path,
          orderIndex: 0
        ),
      ]
    )
    let playbackState = RoutineGuidancePlaybackState()
    let player = BundledRoutineGuidancePlayer(
      resourceLoader: RoutineAudioResourceLoader(),
      remoteAudioFileStore: store,
      remoteManifestProvider: provider,
      playbackState: playbackState
    )
    let playbackTask = Task { @MainActor in
      await player.play(
        RoutineGuidanceCueRequest(
          localRoutineID: routineID,
          localStepID: stepID,
          presetItemID: BundledVoiceAvailabilityProbe.previewItemID,
          voiceCode: VoiceProfile.aoede.assetVoiceCode,
          kind: .intro
        )
      )
    }

    for _ in 0..<100 {
      guard !playbackState.isPlaying else {
        break
      }
      await Task.yield()
    }

    XCTAssertTrue(playbackState.isPlaying)
    player.stop()
    let result = await playbackTask.value
    XCTAssertEqual(result, .cancelled)
  }

  func testPlayerKeepsPlaybackActiveAcrossOrderedAudioFiles() async throws {
    let directory = makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appendingPathComponent("first.wav")
    let secondURL = directory.appendingPathComponent("second.wav")
    try makeSilentWAV(durationSeconds: 0.1).write(to: firstURL)
    try makeSilentWAV(durationSeconds: 0.8).write(to: secondURL)

    let playbackState = RoutineGuidancePlaybackState()
    let player = BundledRoutineGuidancePlayer(
      audioResolver: StaticRoutineGuidanceAudioResolver(
        plans: [
          RoutineGuidanceAudioPlaybackPlan(
            source: .remoteCache,
            urls: [firstURL, secondURL]
          ),
        ]
      ),
      playbackState: playbackState
    )
    let playbackTask = Task { @MainActor in
      await player.play(
        RoutineGuidanceCueRequest(
          presetItemID: nil,
          voiceCode: VoiceProfile.aoede.assetVoiceCode,
          kind: .intro
        )
      )
    }

    try await Task.sleep(for: .milliseconds(300))

    XCTAssertTrue(playbackState.isPlaying)
    player.stop()
    let result = await playbackTask.value
    XCTAssertEqual(result, .cancelled)
  }

  private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func makeSilentWAV(durationSeconds: Double) -> Data {
    let sampleRate: UInt32 = 8_000
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let bytesPerSample = UInt32(bitsPerSample / 8)
    let frameCount = UInt32(durationSeconds * Double(sampleRate))
    let audioByteCount = frameCount * bytesPerSample
    let byteRate = sampleRate * bytesPerSample

    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    appendLittleEndian(UInt32(36) + audioByteCount, to: &data)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    appendLittleEndian(UInt32(16), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(channelCount, to: &data)
    appendLittleEndian(sampleRate, to: &data)
    appendLittleEndian(byteRate, to: &data)
    appendLittleEndian(UInt16(bytesPerSample), to: &data)
    appendLittleEndian(bitsPerSample, to: &data)
    data.append(contentsOf: Array("data".utf8))
    appendLittleEndian(audioByteCount, to: &data)
    data.append(Data(repeating: 0, count: Int(audioByteCount)))
    return data
  }

  private func appendLittleEndian<Value: FixedWidthInteger>(
    _ value: Value,
    to data: inout Data
  ) {
    var littleEndianValue = value.littleEndian
    withUnsafeBytes(of: &littleEndianValue) {
      data.append(contentsOf: $0)
    }
  }

  private func manifestItem(
    routineID: UUID,
    stepID: UUID,
    serverStepID: Int64,
    relativePath: String,
    orderIndex: Int
  ) -> RoutineTTSAudioAssetManifestItem {
    RoutineTTSAudioAssetManifestItem(
      localRoutineID: routineID,
      localStepID: stepID,
      serverStepID: serverStepID,
      cachedRelativePath: relativePath,
      orderIndex: orderIndex
    )
  }
}

@MainActor
private final class RoutineTTSAudioManifestStub:
  RoutineTTSAudioAssetManifestProviding {
  let assets: [RoutineTTSAudioAssetManifestItem]

  init(assets: [RoutineTTSAudioAssetManifestItem]) {
    self.assets = assets
  }

  func cachedAssets(
    localRoutineID: UUID,
    localStepID: UUID
  ) -> [RoutineTTSAudioAssetManifestItem] {
    assets
  }
}

@MainActor
private final class StaticRoutineGuidanceAudioResolver:
  RoutineGuidanceAudioResolving {
  let plans: [RoutineGuidanceAudioPlaybackPlan]

  init(plans: [RoutineGuidanceAudioPlaybackPlan]) {
    self.plans = plans
  }

  func playbackPlans(
    for request: RoutineGuidanceCueRequest
  ) -> [RoutineGuidanceAudioPlaybackPlan] {
    plans
  }
}
