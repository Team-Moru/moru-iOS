//
//  RoutineTTSAudioDownloader.swift
//  Moru
//

import AVFAudio
import Foundation

nonisolated struct RoutineTTSAudioDownloadRequest: Equatable, Sendable {
  let remoteURL: URL

  init(remoteURL: URL) {
    self.remoteURL = remoteURL
  }
}

nonisolated struct RoutineTTSAudioDownloadedFile: Equatable, Sendable {
  let fileURL: URL
  let byteCount: Int64
}

nonisolated enum RoutineTTSAudioDownloadError: Error, Equatable, Sendable {
  case invalidSourceURL
  case rejectedRedirect
  case invalidResponse
  case unsuccessfulStatus(Int)
  case unsupportedContentType
  case emptyBody
  case fileTooLarge
  case undecodableAudio
  case transportFailure
  case cancelled
}

nonisolated struct RoutineTTSAudioDownloadPolicy: Sendable {
  static let maximumAudioBytes: Int64 = 10 * 1_024 * 1_024

  let maximumBytes: Int64
  let sourceValidator: @Sendable (URL) -> Bool
  let redirectValidator: @Sendable (_ source: URL, _ destination: URL) -> Bool

  init(
    maximumBytes: Int64 = Self.maximumAudioBytes,
    sourceValidator: @escaping @Sendable (URL) -> Bool = { url in
      guard let host = url.host?.lowercased() else { return false }
      return host == "amazonaws.com" || host.hasSuffix(".amazonaws.com")
    },
    redirectValidator: @escaping @Sendable (URL, URL) -> Bool = { source, destination in
      source.host?.lowercased() == destination.host?.lowercased()
    }
  ) {
    precondition(maximumBytes > 0)
    self.maximumBytes = maximumBytes
    self.sourceValidator = sourceValidator
    self.redirectValidator = redirectValidator
  }
}

nonisolated struct RoutineTTSAudioDecodeProbe: Sendable {
  private let probe: @Sendable (URL) throws -> Void

  init(probe: @escaping @Sendable (URL) throws -> Void) {
    self.probe = probe
  }

  func validate(fileAt url: URL) throws {
    try probe(url)
  }

  static let system = RoutineTTSAudioDecodeProbe { url in
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0 else {
      throw RoutineTTSAudioDownloadError.undecodableAudio
    }
  }
}

nonisolated protocol RoutineTTSAudioDownloading: Sendable {
  func download(
    _ request: RoutineTTSAudioDownloadRequest,
    stagingDirectory: URL
  ) async throws -> RoutineTTSAudioDownloadedFile
}

nonisolated final class RoutineTTSAudioDownloader:
  RoutineTTSAudioDownloading,
  @unchecked Sendable {
  private let configuration: URLSessionConfiguration
  private let policy: RoutineTTSAudioDownloadPolicy
  private let decodeProbe: RoutineTTSAudioDecodeProbe
  private let fileManager: FileManager

  init(
    configuration: URLSessionConfiguration = .routineTTSAudioEphemeral,
    policy: RoutineTTSAudioDownloadPolicy = RoutineTTSAudioDownloadPolicy(),
    decodeProbe: RoutineTTSAudioDecodeProbe = .system,
    fileManager: FileManager = .default
  ) {
    self.configuration = configuration.copy() as! URLSessionConfiguration
    Self.harden(self.configuration)
    self.policy = policy
    self.decodeProbe = decodeProbe
    self.fileManager = fileManager
  }

  func download(
    _ request: RoutineTTSAudioDownloadRequest,
    stagingDirectory: URL
  ) async throws -> RoutineTTSAudioDownloadedFile {
    guard Self.isAllowedHTTPSURL(request.remoteURL),
          policy.sourceValidator(request.remoteURL) else {
      throw RoutineTTSAudioDownloadError.invalidSourceURL
    }

    try Task.checkCancellation()
    try fileManager.createDirectory(
      at: stagingDirectory,
      withIntermediateDirectories: true
    )
    let partialURL = stagingDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: false)
      .appendingPathExtension("partial")
    let publishedURL = stagingDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: false)
      .appendingPathExtension("mp3")
    guard fileManager.createFile(atPath: partialURL.path, contents: nil) else {
      throw RoutineTTSAudioDownloadError.transportFailure
    }
    do {
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen],
        ofItemAtPath: partialURL.path
      )
    } catch {
      try? fileManager.removeItem(at: partialURL)
      throw RoutineTTSAudioDownloadError.transportFailure
    }

    do {
      let delegate = try RoutineTTSAudioStreamDelegate(
        partialURL: partialURL,
        originalURL: request.remoteURL,
        policy: policy
      )
      let session = URLSession(
        configuration: configuration,
        delegate: delegate,
        delegateQueue: nil
      )
      defer { session.finishTasksAndInvalidate() }

      var urlRequest = URLRequest(
        url: request.remoteURL,
        cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
      )
      urlRequest.httpShouldHandleCookies = false
      urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

      let byteCount = try await delegate.perform(request: urlRequest, in: session)
      try Task.checkCancellation()
      do {
        try decodeProbe.validate(fileAt: partialURL)
      } catch {
        throw RoutineTTSAudioDownloadError.undecodableAudio
      }
      try fileManager.moveItem(at: partialURL, to: publishedURL)
      return RoutineTTSAudioDownloadedFile(
        fileURL: publishedURL,
        byteCount: byteCount
      )
    } catch is CancellationError {
      try? fileManager.removeItem(at: partialURL)
      try? fileManager.removeItem(at: publishedURL)
      throw RoutineTTSAudioDownloadError.cancelled
    } catch let error as RoutineTTSAudioDownloadError {
      try? fileManager.removeItem(at: partialURL)
      try? fileManager.removeItem(at: publishedURL)
      throw error
    } catch {
      try? fileManager.removeItem(at: partialURL)
      try? fileManager.removeItem(at: publishedURL)
      throw RoutineTTSAudioDownloadError.transportFailure
    }
  }

  static func isAllowedHTTPSURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
      && url.host?.isEmpty == false
      && (url.port == nil || url.port == 443)
      && url.user == nil
      && url.password == nil
      && url.fragment == nil
  }

  private static func harden(_ configuration: URLSessionConfiguration) {
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpAdditionalHeaders = [:]
  }
}

nonisolated private final class RoutineTTSAudioStreamDelegate:
  NSObject,
  URLSessionDataDelegate,
  URLSessionTaskDelegate,
  @unchecked Sendable {
  private let lock = NSLock()
  private let fileHandle: FileHandle
  private let originalURL: URL
  private let policy: RoutineTTSAudioDownloadPolicy

  private var continuation: CheckedContinuation<Int64, Error>?
  private var task: URLSessionDataTask?
  private var byteCount: Int64 = 0
  private var pendingError: RoutineTTSAudioDownloadError?
  private var finished = false

  init(
    partialURL: URL,
    originalURL: URL,
    policy: RoutineTTSAudioDownloadPolicy
  ) throws {
    fileHandle = try FileHandle(forWritingTo: partialURL)
    self.originalURL = originalURL
    self.policy = policy
  }

  deinit {
    try? fileHandle.close()
  }

  func perform(request: URLRequest, in session: URLSession) async throws -> Int64 {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.withLock {
          self.continuation = continuation
          let task = session.dataTask(with: request)
          self.task = task
          task.resume()
        }
      }
    } onCancel: {
      self.cancel()
    }
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let response = response as? HTTPURLResponse,
          let finalURL = response.url,
          RoutineTTSAudioDownloader.isAllowedHTTPSURL(finalURL),
          policy.sourceValidator(finalURL) else {
      reject(.invalidResponse, completionHandler: completionHandler)
      return
    }
    guard response.statusCode == 200 else {
      reject(.unsuccessfulStatus(response.statusCode), completionHandler: completionHandler)
      return
    }
    let mimeType = response.mimeType?.lowercased()
    guard mimeType == "audio/mpeg" || mimeType == "audio/mp3" else {
      reject(.unsupportedContentType, completionHandler: completionHandler)
      return
    }
    if response.expectedContentLength > policy.maximumBytes {
      reject(.fileTooLarge, completionHandler: completionHandler)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    let shouldCancel = lock.withLock { () -> Bool in
      guard pendingError == nil else { return true }
      guard Int64(data.count) <= policy.maximumBytes - byteCount else {
        pendingError = .fileTooLarge
        return true
      }
      do {
        try fileHandle.write(contentsOf: data)
        byteCount += Int64(data.count)
        return false
      } catch {
        pendingError = .transportFailure
        return true
      }
    }
    if shouldCancel {
      dataTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let destination = request.url,
          RoutineTTSAudioDownloader.isAllowedHTTPSURL(destination),
          policy.redirectValidator(originalURL, destination) else {
      lock.withLock { pendingError = .rejectedRedirect }
      completionHandler(nil)
      return
    }
    var sanitized = request
    sanitized.httpShouldHandleCookies = false
    sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
    sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
    completionHandler(sanitized)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (
      URLSession.AuthChallengeDisposition,
      URLCredential?
    ) -> Void
  ) {
    if challenge.protectionSpace.authenticationMethod
      == NSURLAuthenticationMethodServerTrust {
      completionHandler(.performDefaultHandling, nil)
    } else {
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let result: Result<Int64, Error> = lock.withLock {
      if let pendingError {
        return .failure(pendingError)
      }
      if let error {
        if (error as NSError).code == NSURLErrorCancelled {
          return .failure(RoutineTTSAudioDownloadError.cancelled)
        }
        return .failure(RoutineTTSAudioDownloadError.transportFailure)
      }
      guard byteCount > 0 else {
        return .failure(RoutineTTSAudioDownloadError.emptyBody)
      }
      return .success(byteCount)
    }
    finish(result)
  }

  private func reject(
    _ error: RoutineTTSAudioDownloadError,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    lock.withLock { pendingError = error }
    completionHandler(.cancel)
  }

  private func cancel() {
    lock.withLock {
      pendingError = .cancelled
      task?.cancel()
    }
  }

  private func finish(_ result: Result<Int64, Error>) {
    let continuation: CheckedContinuation<Int64, Error>? = lock.withLock {
      guard !finished else { return nil }
      finished = true
      let value = self.continuation
      self.continuation = nil
      task = nil
      return value
    }
    try? fileHandle.close()
    continuation?.resume(with: result)
  }
}

nonisolated extension URLSessionConfiguration {
  static var routineTTSAudioEphemeral: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpAdditionalHeaders = [:]
    return configuration
  }
}
