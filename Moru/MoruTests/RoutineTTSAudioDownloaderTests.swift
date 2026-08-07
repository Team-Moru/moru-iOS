//
//  RoutineTTSAudioDownloaderTests.swift
//  MoruTests
//

import Foundation
import XCTest

@testable import Moru

@MainActor
final class RoutineTTSAudioDownloaderTests: XCTestCase {
  func testDownloadsSupportedHTTPSAudioWithoutAuthorization()
    async throws {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "audio/mpeg",
        data: Data([1, 2, 3])
      )
    )
    defer { harness.finish() }

    let data = try await harness.downloader.downloadAudio(
      from: harness.url
    )

    XCTAssertEqual(data, Data([1, 2, 3]))
    let request = try XCTUnwrap(harness.capturedRequest)
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Accept"),
      "audio/mpeg, audio/*"
    )
    XCTAssertNil(
      request.value(forHTTPHeaderField: "Authorization")
    )
  }

  func testAcceptsApplicationOctetStream() async throws {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "application/octet-stream",
        data: Data([4, 5])
      )
    )
    defer { harness.finish() }

    let data = try await harness.downloader.downloadAudio(
      from: harness.url
    )

    XCTAssertEqual(data, Data([4, 5]))
  }

  func testRejectsInsecureURLBeforeTransport() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [
      RoutineTTSAudioStubURLProtocol.self,
    ]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let downloader = URLSessionRoutineTTSAudioDownloader(
      session: session
    )

    await assertDownloadError(.insecureURL) {
      try await downloader.downloadAudio(
        from: URL(string: "http://audio.example.test/file.mp3")!
      )
    }
  }

  func testRejectsNonSuccessHTTPStatus() async {
    let harness = DownloaderHarness(
      stub: .init(
        statusCode: 503,
        contentType: "audio/mpeg",
        data: Data([1])
      )
    )
    defer { harness.finish() }

    await assertDownloadError(.httpStatus(503)) {
      try await harness.downloader.downloadAudio(
        from: harness.url
      )
    }
  }

  func testRejectsEmptyAudio() async {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "audio/mpeg",
        data: Data()
      )
    )
    defer { harness.finish() }

    await assertDownloadError(.emptyAudio) {
      try await harness.downloader.downloadAudio(
        from: harness.url
      )
    }
  }

  func testRejectsContentLengthAboveLimit() async {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "audio/mpeg",
        data: Data([1, 2, 3]),
        includesContentLength: true
      ),
      maximumByteCount: 2
    )
    defer { harness.finish() }

    await assertDownloadError(.audioTooLarge) {
      try await harness.downloader.downloadAudio(
        from: harness.url
      )
    }
  }

  func testRejectsFinalFileSizeAboveLimitWithoutContentLength()
    async {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "audio/mpeg",
        data: Data([1, 2, 3]),
        includesContentLength: false
      ),
      maximumByteCount: 2
    )
    defer { harness.finish() }

    await assertDownloadError(.audioTooLarge) {
      try await harness.downloader.downloadAudio(
        from: harness.url
      )
    }
  }

  func testRejectsNonAudioSuccessResponse() async {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "text/html; charset=utf-8",
        data: Data("<html></html>".utf8)
      )
    )
    defer { harness.finish() }

    await assertDownloadError(.unsupportedContentType) {
      try await harness.downloader.downloadAudio(
        from: harness.url
      )
    }
  }

  func testCancellationRemainsCancellation() async throws {
    let harness = DownloaderHarness(
      stub: .init(
        contentType: "audio/mpeg",
        data: Data([1, 2, 3]),
        responseDelay: 2
      )
    )
    defer { harness.finish() }
    let task = Task {
      try await harness.downloader.downloadAudio(
        from: harness.url
      )
    }

    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  private func assertDownloadError(
    _ expected: RoutineTTSAudioDownloadError,
    operation: () async throws -> Data
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected \(expected).")
    } catch let error as RoutineTTSAudioDownloadError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Expected download error, got \(error)")
    }
  }
}

@MainActor
private final class DownloaderHarness {
  let url: URL
  let downloader: URLSessionRoutineTTSAudioDownloader

  private let session: URLSession

  init(
    stub: RoutineTTSAudioHTTPStub,
    maximumByteCount: Int = 20 * 1_024 * 1_024
  ) {
    url = URL(
      string: "https://audio.example.test/\(UUID().uuidString).mp3"
    )!
    RoutineTTSAudioStubURLProtocol.register(stub, for: url)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [
      RoutineTTSAudioStubURLProtocol.self,
    ]
    session = URLSession(configuration: configuration)
    downloader = URLSessionRoutineTTSAudioDownloader(
      session: session,
      maximumByteCount: maximumByteCount
    )
  }

  var capturedRequest: URLRequest? {
    RoutineTTSAudioStubURLProtocol.capturedRequest(for: url)
  }

  func finish() {
    session.invalidateAndCancel()
    RoutineTTSAudioStubURLProtocol.unregister(url)
  }
}

nonisolated private struct RoutineTTSAudioHTTPStub: Sendable {
  let statusCode: Int
  let contentType: String?
  let data: Data
  let includesContentLength: Bool
  let responseDelay: TimeInterval

  init(
    statusCode: Int = 200,
    contentType: String?,
    data: Data,
    includesContentLength: Bool = true,
    responseDelay: TimeInterval = 0
  ) {
    self.statusCode = statusCode
    self.contentType = contentType
    self.data = data
    self.includesContentLength = includesContentLength
    self.responseDelay = responseDelay
  }
}

nonisolated private final class RoutineTTSAudioStubURLProtocol:
  URLProtocol,
  @unchecked Sendable {
  private static let storage = RoutineTTSAudioURLProtocolStorage()

  private let workLock = NSLock()
  private var responseWorkItem: DispatchWorkItem?

  static func register(
    _ stub: RoutineTTSAudioHTTPStub,
    for url: URL
  ) {
    storage.register(stub, for: url)
  }

  static func unregister(_ url: URL) {
    storage.unregister(url)
  }

  static func capturedRequest(for url: URL) -> URLRequest? {
    storage.capturedRequest(for: url)
  }

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url else {
      return false
    }
    return storage.hasStub(for: url)
  }

  override class func canonicalRequest(
    for request: URLRequest
  ) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url,
          let stub = Self.storage.stub(for: url) else {
      client?.urlProtocol(
        self,
        didFailWithError: URLError(.resourceUnavailable)
      )
      return
    }
    Self.storage.capture(request, for: url)

    let workItem = DispatchWorkItem { [weak self] in
      self?.send(stub, for: url)
    }
    workLock.lock()
    responseWorkItem = workItem
    workLock.unlock()

    if stub.responseDelay > 0 {
      DispatchQueue.global().asyncAfter(
        deadline: .now() + stub.responseDelay,
        execute: workItem
      )
    } else {
      workItem.perform()
    }
  }

  override func stopLoading() {
    workLock.lock()
    let workItem = responseWorkItem
    responseWorkItem = nil
    workLock.unlock()
    workItem?.cancel()
  }

  private func send(
    _ stub: RoutineTTSAudioHTTPStub,
    for url: URL
  ) {
    workLock.lock()
    let isCancelled = responseWorkItem?.isCancelled ?? true
    workLock.unlock()
    guard !isCancelled else {
      return
    }

    var headers: [String: String] = [:]
    if let contentType = stub.contentType {
      headers["Content-Type"] = contentType
    }
    if stub.includesContentLength {
      headers["Content-Length"] = "\(stub.data.count)"
    }
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: stub.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    ) else {
      client?.urlProtocol(
        self,
        didFailWithError: URLError(.badServerResponse)
      )
      return
    }

    client?.urlProtocol(
      self,
      didReceive: response,
      cacheStoragePolicy: .notAllowed
    )
    if !stub.data.isEmpty {
      client?.urlProtocol(self, didLoad: stub.data)
    }
    client?.urlProtocolDidFinishLoading(self)
  }
}

nonisolated private final class RoutineTTSAudioURLProtocolStorage:
  @unchecked Sendable {
  private let lock = NSLock()
  private var stubs: [URL: RoutineTTSAudioHTTPStub] = [:]
  private var requests: [URL: URLRequest] = [:]

  func register(
    _ stub: RoutineTTSAudioHTTPStub,
    for url: URL
  ) {
    lock.lock()
    defer { lock.unlock() }
    stubs[url] = stub
    requests[url] = nil
  }

  func unregister(_ url: URL) {
    lock.lock()
    defer { lock.unlock() }
    stubs[url] = nil
    requests[url] = nil
  }

  func hasStub(for url: URL) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return stubs[url] != nil
  }

  func stub(for url: URL) -> RoutineTTSAudioHTTPStub? {
    lock.lock()
    defer { lock.unlock() }
    return stubs[url]
  }

  func capture(_ request: URLRequest, for url: URL) {
    lock.lock()
    defer { lock.unlock() }
    requests[url] = request
  }

  func capturedRequest(for url: URL) -> URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return requests[url]
  }
}
