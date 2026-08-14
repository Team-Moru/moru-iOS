//
//  ServerVoicePreviewPlayerTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

@MainActor
final class ServerVoicePreviewPlayerTests: XCTestCase {
  func testPreviewDownloadsOnceCachesAndPlaysEachRequest() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let cache = try RoutineTTSAudioCache(rootDirectory: directory)
    let downloader = PreviewAudioDownloaderSpy()
    let localPlayer = PreviewLocalPlayer()
    let player = ServerVoicePreviewPlayer(
      audioCache: cache,
      downloader: downloader,
      localPlayer: localPlayer
    )
    let voice = previewVoice()

    player.togglePreview(voice, memberID: 98)
    await waitUntil { localPlayer.playedURLs.count == 1 && player.state == .idle }

    player.togglePreview(voice, memberID: 98)
    await waitUntil { localPlayer.playedURLs.count == 2 && player.state == .idle }

    let downloadCount = await downloader.downloadCount
    XCTAssertEqual(downloadCount, 1)
    XCTAssertTrue(localPlayer.playedURLs.allSatisfy(\.isFileURL))
    XCTAssertNil(player.errorMessage)
  }

  func testPreviewWithoutBackendURLShowsUnavailableState() {
    let player = ServerVoicePreviewPlayer()
    let voice = ServerTTSVoice(
      ttsID: 1,
      voiceCode: "MINSEO",
      displayName: "민서",
      description: "따뜻한 친구",
      isProOnly: false
    )

    XCTAssertFalse(player.isPreviewAvailable(for: voice))

    player.togglePreview(voice, memberID: 98)

    XCTAssertEqual(player.state, .failed(ttsID: 1))
    XCTAssertEqual(
      player.errorMessage,
      "이 음성의 미리듣기를 아직 준비하지 못했어요."
    )
  }

  private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
  ) async {
    while !predicate() {
      await Task.yield()
    }
  }

  private func previewVoice() -> ServerTTSVoice {
    ServerTTSVoice(
      ttsID: 1,
      voiceCode: "MINSEO",
      displayName: "민서",
      description: "따뜻한 친구",
      isProOnly: false,
      previewAudioURL: URL(string: "https://audio.example.com/minseo-preview.mp3")
    )
  }
}

private actor PreviewAudioDownloaderSpy: RoutineTTSAudioDownloading {
  private(set) var downloadCount = 0

  func download(
    _ request: RoutineTTSAudioDownloadRequest,
    stagingDirectory: URL
  ) async throws -> RoutineTTSAudioDownloadedFile {
    downloadCount += 1
    let fileURL = stagingDirectory.appendingPathComponent("preview.mp3")
    let data = Data("preview audio".utf8)
    try data.write(to: fileURL, options: .atomic)
    return RoutineTTSAudioDownloadedFile(
      fileURL: fileURL,
      byteCount: Int64(data.count)
    )
  }
}

@MainActor
private final class PreviewLocalPlayer: RoutineLocalAudioSequencePlaying {
  private(set) var playedURLs: [URL] = []

  func playLocalAudioSequence(_ urls: [URL]) async -> RoutineLocalAudioPlaybackResult {
    playedURLs.append(contentsOf: urls)
    return .completed
  }

  func stop() {}
  func stopAndWaitUntilIdle() async {}
  func resumeAfterSpeechInput() {}
}
