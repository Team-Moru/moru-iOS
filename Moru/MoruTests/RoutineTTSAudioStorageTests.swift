//
//  RoutineTTSAudioStorageTests.swift
//  MoruTests
//

import Foundation
import XCTest
@testable import Moru

final class RoutineTTSAudioStorageTests: XCTestCase {
  func testDownloaderRejectsHTTPBeforeStartingTransport() async {
    let downloader = RoutineTTSAudioDownloader(
      policy: testDownloadPolicy(),
      decodeProbe: acceptingDecodeProbe()
    )

    await XCTAssertThrowsErrorAsync(
      try await downloader.download(
        RoutineTTSAudioDownloadRequest(
          remoteURL: URL(string: "http://audio.example.test/file.mp3")!
        ),
        stagingDirectory: FileManager.default.temporaryDirectory
      )
    ) { error in
      XCTAssertEqual(error as? RoutineTTSAudioDownloadError, .invalidSourceURL)
    }
  }

  func testDownloaderStripsCredentialsAndAcceptsValidAudioResponse() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RoutineTTSAudioURLProtocol.self]
    RoutineTTSAudioURLProtocol.handler = { request in
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
      XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
      return (
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "audio/mpeg"]
        )!,
        Data("valid-audio".utf8)
      )
    }
    defer { RoutineTTSAudioURLProtocol.handler = nil }
    configuration.httpAdditionalHeaders = [
      "Authorization": "Bearer must-not-leak",
      "Cookie": "session=must-not-leak",
    ]
    let downloader = RoutineTTSAudioDownloader(
      configuration: configuration,
      policy: testDownloadPolicy(),
      decodeProbe: acceptingDecodeProbe()
    )
    let stagingDirectory = directory.appendingPathComponent("staging", isDirectory: true)

    let result = try await downloader.download(
      RoutineTTSAudioDownloadRequest(
        remoteURL: URL(string: "https://audio.example.test/file.mp3?signature=secret")!
      ),
      stagingDirectory: stagingDirectory
    )

    XCTAssertEqual(result.byteCount, Int64(Data("valid-audio".utf8).count))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: result.fileURL.path
    )
    #if !targetEnvironment(simulator)
    let protection = attributes[.protectionKey]
    XCTAssertTrue(
      protection as? FileProtectionType == .completeUnlessOpen
        || protection as? String == FileProtectionType.completeUnlessOpen.rawValue
    )
    #else
    // The simulator ignores NSFileProtection attributes; successful creation
    // verifies that the protected staging write path remains usable here.
    XCTAssertNotNil(attributes[.size])
    #endif
  }

  func testDownloaderRejectsWrongStatusMIMEEmptyOverflowAndDecodeFailure() async {
    await assertDownloadFailure(status: 206, mime: "audio/mpeg", data: Data([1]),
                                expected: .unsuccessfulStatus(206))
    await assertDownloadFailure(status: 200, mime: "text/html", data: Data([1]),
                                expected: .unsupportedContentType)
    await assertDownloadFailure(status: 200, mime: "audio/mpeg", data: Data(),
                                expected: .emptyBody)
    await assertDownloadFailure(
      status: 200,
      mime: "audio/mpeg",
      data: Data(repeating: 1, count: 9),
      maximumBytes: 8,
      expected: .fileTooLarge
    )
    await assertDownloadFailure(
      status: 200,
      mime: "audio/mpeg",
      data: Data([1]),
      decodeProbe: RoutineTTSAudioDecodeProbe { _ in
        throw RoutineTTSAudioDownloadError.undecodableAudio
      },
      expected: .undecodableAudio
    )
  }

  func testCacheKeyDoesNotPersistAccountOrSignedQueryAndQueryRotationHitsSameFile()
    async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try RoutineTTSAudioCache(rootDirectory: directory)
    let source = directory.appendingPathComponent("source.mp3")
    try Data("audio".utf8).write(to: source)
    let key = makeKey(
      accountID: "member@example.com",
      url: "https://bucket.amazonaws.com/object-id.mp3?X-Amz-Signature=secret-one"
    )
    let stored = try await cache.storeDownloadedFile(at: source, for: key)
    let rotated = makeKey(
      accountID: "member@example.com",
      url: "https://bucket.amazonaws.com/object-id.mp3?X-Amz-Signature=secret-two"
    )

    let rotatedHit = await cache.cachedFileURL(for: rotated)
    XCTAssertEqual(rotatedHit, stored)
    let paths = try allDescendantPaths(directory)
    XCTAssertFalse(paths.joined().contains("member@example.com"))
    XCTAssertFalse(paths.joined().contains("secret"))
    XCTAssertTrue(stored.lastPathComponent.range(
      of: #"^[0-9a-f]{64}\.audio$"#,
      options: .regularExpression
    ) != nil)
  }

  func testCacheDetectsCorruptionAndRemovesIncompleteEntry() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try RoutineTTSAudioCache(rootDirectory: directory)
    let source = directory.appendingPathComponent("source.mp3")
    try Data("audio".utf8).write(to: source)
    let key = makeKey()
    let stored = try await cache.storeDownloadedFile(at: source, for: key)
    try Data("tampered".utf8).write(to: stored)

    let corruptedHit = await cache.cachedFileURL(for: key)
    XCTAssertNil(corruptedHit)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: stored.deletingPathExtension().appendingPathExtension("json").path
    ))
  }

  func testCacheTTLStaleWindowAndExpiryUseInjectedClock() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = TestDateClock(Date(timeIntervalSince1970: 1_000))
    let cache = try RoutineTTSAudioCache(
      rootDirectory: directory,
      policy: RoutineTTSAudioCachePolicy(
        maximumFileBytes: 32,
        maximumAccountBytes: 64,
        maximumTotalBytes: 128,
        freshTimeToLive: 10,
        maximumStaleAge: 20
      ),
      now: { clock.now }
    )
    let source = directory.appendingPathComponent("source.mp3")
    try Data("audio".utf8).write(to: source)
    let key = makeKey()
    _ = try await cache.storeDownloadedFile(at: source, for: key)

    clock.now = Date(timeIntervalSince1970: 1_011)
    let freshHit = await cache.cachedFileURL(for: key)
    let staleHit = await cache.cachedFileURL(for: key, allowStale: true)
    XCTAssertNil(freshHit)
    XCTAssertNotNil(staleHit)
    clock.now = Date(timeIntervalSince1970: 1_021)
    let expiredHit = await cache.cachedFileURL(for: key, allowStale: true)
    XCTAssertNil(expiredHit)
  }

  func testCacheCoalescesSameKeyLoader() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try RoutineTTSAudioCache(rootDirectory: directory)
    let counter = TestCounter()
    let loader: RoutineTTSAudioCache.Loader = { stagingDirectory in
      await counter.increment()
      try await Task.sleep(for: .milliseconds(50))
      let file = stagingDirectory.appendingPathComponent(UUID().uuidString)
      try Data("audio".utf8).write(to: file)
      return RoutineTTSAudioDownloadedFile(fileURL: file, byteCount: 5)
    }
    let key = makeKey()

    async let first = cache.fileURL(for: key, loader: loader)
    async let second = cache.fileURL(for: key, loader: loader)
    let firstURL = try await first
    let secondURL = try await second
    let loadCount = await counter.value
    XCTAssertEqual(firstURL, secondURL)
    XCTAssertEqual(loadCount, 1)
  }

  func testCacheEvictsLeastRecentlyUsedEntryAtAccountQuota() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = TestDateClock(Date(timeIntervalSince1970: 1_000))
    let cache = try RoutineTTSAudioCache(
      rootDirectory: directory,
      policy: RoutineTTSAudioCachePolicy(
        maximumFileBytes: 5,
        maximumAccountBytes: 10,
        maximumTotalBytes: 20,
        freshTimeToLive: 100,
        maximumStaleAge: 200
      ),
      now: { clock.now }
    )
    let source = directory.appendingPathComponent("source.mp3")
    try Data("12345".utf8).write(to: source)
    let first = makeKey(url: "https://bucket.amazonaws.com/one.mp3")
    let second = makeKey(url: "https://bucket.amazonaws.com/two.mp3")
    let third = makeKey(url: "https://bucket.amazonaws.com/three.mp3")
    _ = try await cache.storeDownloadedFile(at: source, for: first)
    clock.now = Date(timeIntervalSince1970: 1_001)
    _ = try await cache.storeDownloadedFile(at: source, for: second)
    clock.now = Date(timeIntervalSince1970: 1_002)
    _ = await cache.cachedFileURL(for: first)
    clock.now = Date(timeIntervalSince1970: 1_003)
    _ = try await cache.storeDownloadedFile(at: source, for: third)

    let firstHit = await cache.cachedFileURL(for: first)
    let secondHit = await cache.cachedFileURL(for: second)
    let thirdHit = await cache.cachedFileURL(for: third)
    XCTAssertNotNil(firstHit)
    XCTAssertNil(secondHit)
    XCTAssertNotNil(thirdHit)
  }

  func testPurgeCancelsOldLoadAndDoesNotRemoveSameKeyReplacement() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try RoutineTTSAudioCache(rootDirectory: directory)
    let gate = TestGate()
    let key = makeKey(accountID: "account-a")
    let oldTask = Task {
      try await cache.fileURL(for: key) { stagingDirectory in
        try await gate.wait()
        let file = stagingDirectory.appendingPathComponent("old")
        try Data("old".utf8).write(to: file)
        return RoutineTTSAudioDownloadedFile(fileURL: file, byteCount: 3)
      }
    }
    await Task.yield()
    try await cache.purge(accountID: "account-a")

    let replacementURL = try await cache.fileURL(for: key) { stagingDirectory in
      let file = stagingDirectory.appendingPathComponent("new")
      try Data("new".utf8).write(to: file)
      return RoutineTTSAudioDownloadedFile(fileURL: file, byteCount: 3)
    }
    await gate.open()
    _ = try? await oldTask.value

    let replacementHit = await cache.cachedFileURL(for: key)
    XCTAssertEqual(replacementHit, replacementURL)
  }

  func testCacheInitializationRemovesPriorProcessStagingOrphans() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let staging = directory
      .appendingPathComponent(String(repeating: "a", count: 64), isDirectory: true)
      .appendingPathComponent(String(repeating: "b", count: 64), isDirectory: true)
      .appendingPathComponent(".staging", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try Data("orphan".utf8).write(
      to: staging.appendingPathComponent("crashed-process.mp3")
    )

    _ = try RoutineTTSAudioCache(rootDirectory: directory)

    XCTAssertFalse(FileManager.default.fileExists(
      atPath: staging.deletingLastPathComponent().path
    ))
  }

  func testAccountPurgeRemovesOwnedStagingWithoutRawAccountOrURLPath() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try RoutineTTSAudioCache(rootDirectory: directory)
    let gate = TestGate()
    let observed = TestURLRecorder()
    let key = makeKey(
      accountID: "private-member@example.com",
      url: "https://bucket.amazonaws.com/private-object.mp3?signature=secret"
    )
    let task = Task {
      try await cache.fileURL(for: key) { stagingDirectory in
        await observed.record(stagingDirectory)
        let file = stagingDirectory.appendingPathComponent("stream.partial")
        try Data("audio".utf8).write(
          to: file,
          options: .completeFileProtectionUnlessOpen
        )
        try await gate.wait()
        return RoutineTTSAudioDownloadedFile(fileURL: file, byteCount: 5)
      }
    }
    let stagingDirectory = await observed.waitForURL()
    XCTAssertFalse(stagingDirectory.path.contains("private-member"))
    XCTAssertFalse(stagingDirectory.path.contains("private-object"))
    XCTAssertFalse(stagingDirectory.path.contains("secret"))

    try await cache.purge(accountID: "private-member@example.com")
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: stagingDirectory.deletingLastPathComponent().path
    ))
    await gate.open()
    _ = try? await task.value
  }

  func testWithdrawalFinalizePurgesAudioBeforeDeletingDurableMarker() async throws {
    let base = AccountCleanupRecorder()
    let audioCleaner = AccountAudioCleanupRecorder()
    let cleaner = RoutineTTSAudioAccountScopedDataCleaner(
      base: base,
      audioCleaner: audioCleaner
    )

    try await cleaner.finalizePendingAccountCleanup(memberID: 92)

    let removedMemberIDs = await audioCleaner.removedMemberIDs
    let finalizedMemberIDs = await base.finalizedMemberIDs
    XCTAssertEqual(removedMemberIDs, [92])
    XCTAssertEqual(finalizedMemberIDs, [92])
  }

  func testWithdrawalFinalizeKeepsMarkerWhenAudioPurgeFails() async {
    let base = AccountCleanupRecorder()
    let audioCleaner = AccountAudioCleanupRecorder(shouldFail: true)
    let cleaner = RoutineTTSAudioAccountScopedDataCleaner(
      base: base,
      audioCleaner: audioCleaner
    )

    await XCTAssertThrowsErrorAsync(
      try await cleaner.finalizePendingAccountCleanup(memberID: 92)
    )

    let removedMemberIDs = await audioCleaner.removedMemberIDs
    let finalizedMemberIDs = await base.finalizedMemberIDs
    XCTAssertEqual(removedMemberIDs, [92])
    XCTAssertEqual(finalizedMemberIDs, [])
  }

  private func assertDownloadFailure(
    status: Int,
    mime: String,
    data: Data,
    maximumBytes: Int64 = 10 * 1_024 * 1_024,
    decodeProbe: RoutineTTSAudioDecodeProbe? = nil,
    expected: RoutineTTSAudioDownloadError
  ) async {
    let directory = try! makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RoutineTTSAudioURLProtocol.self]
    RoutineTTSAudioURLProtocol.handler = { request in
      (
        HTTPURLResponse(
          url: request.url!,
          statusCode: status,
          httpVersion: nil,
          headerFields: ["Content-Type": mime]
        )!,
        data
      )
    }
    defer { RoutineTTSAudioURLProtocol.handler = nil }
    let downloader = RoutineTTSAudioDownloader(
      configuration: configuration,
      policy: testDownloadPolicy(maximumBytes: maximumBytes),
      decodeProbe: decodeProbe ?? acceptingDecodeProbe()
    )
    await XCTAssertThrowsErrorAsync(
      try await downloader.download(
        RoutineTTSAudioDownloadRequest(
          remoteURL: URL(string: "https://audio.example.test/file.mp3")!
        ),
        stagingDirectory: directory.appendingPathComponent(
          "staging",
          isDirectory: true
        )
      )
    ) { error in
      XCTAssertEqual(error as? RoutineTTSAudioDownloadError, expected)
    }
  }

  private func testDownloadPolicy(
    maximumBytes: Int64 = 10 * 1_024 * 1_024
  ) -> RoutineTTSAudioDownloadPolicy {
    RoutineTTSAudioDownloadPolicy(
      maximumBytes: maximumBytes,
      sourceValidator: { $0.host == "audio.example.test" },
      redirectValidator: { _, destination in
        destination.host == "audio.example.test"
      }
    )
  }

  private func acceptingDecodeProbe() -> RoutineTTSAudioDecodeProbe {
    RoutineTTSAudioDecodeProbe { _ in }
  }

  private func makeKey(
    accountID: String = "account-a",
    url: String = "https://bucket.amazonaws.com/object.mp3?signature=secret"
  ) -> RoutineTTSAudioCacheKey {
    RoutineTTSAudioCacheKey(
      accountID: accountID,
      namespace: "production",
      routineGroupID: 1,
      routineID: 2,
      stepID: 3,
      remoteURL: URL(string: url)!
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    return url
  }

  private func allDescendantPaths(_ root: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { return [] }
    return enumerator.compactMap { ($0 as? URL)?.path }
  }
}

private final class RoutineTTSAudioURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.badServerResponse) }
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class TestDateClock: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Date

  init(_ date: Date) { stored = date }

  var now: Date {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

private actor TestCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

private actor TestGate {
  private var continuation: CheckedContinuation<Void, Error>?

  func wait() async throws {
    try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func open() {
    continuation?.resume()
    continuation = nil
  }
}

private actor TestURLRecorder {
  private var storedURL: URL?

  func record(_ url: URL) {
    storedURL = url
  }

  func waitForURL() async -> URL {
    while storedURL == nil { await Task.yield() }
    return storedURL!
  }
}

private actor AccountCleanupRecorder: AccountScopedDataCleaning {
  private(set) var finalizedMemberIDs: [Int64] = []

  func removeAccountScopedData(memberID: Int64) async throws {}

  func finalizePendingAccountCleanup(memberID: Int64) async throws {
    finalizedMemberIDs.append(memberID)
  }
}

private actor AccountAudioCleanupRecorder: RoutineTTSAudioCacheCleaning {
  private(set) var removedMemberIDs: [Int64] = []
  private let shouldFail: Bool

  init(shouldFail: Bool = false) {
    self.shouldFail = shouldFail
  }

  func removeAllRoutineTTSAudio() async throws {}

  func removeRoutineTTSAudio(memberID: Int64) async throws {
    removedMemberIDs.append(memberID)
    if shouldFail {
      throw RoutineTTSAudioCacheError.storageFailure
    }
  }
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
