//
//  RoutineTTSAudioDownloader.swift
//  Moru
//

import Foundation

nonisolated protocol RoutineTTSAudioDownloading: Sendable {
  func downloadAudio(from url: URL) async throws -> Data
}

nonisolated enum RoutineTTSAudioDownloadError:
  Error,
  Equatable,
  Sendable {
  case insecureURL
  case invalidResponse
  case unsupportedContentType
  case httpStatus(Int)
  case emptyAudio
  case audioTooLarge
}

actor URLSessionRoutineTTSAudioDownloader:
  RoutineTTSAudioDownloading {
  private let session: URLSession
  private let maximumByteCount: Int

  init(
    session: URLSession = URLSession(
      configuration: .ephemeral
    ),
    maximumByteCount: Int = 20 * 1_024 * 1_024
  ) {
    self.session = session
    self.maximumByteCount = maximumByteCount
  }

  func downloadAudio(from url: URL) async throws -> Data {
    guard url.scheme?.lowercased() == "https",
          let host = url.host,
          !host.isEmpty else {
      throw RoutineTTSAudioDownloadError.insecureURL
    }

    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 30
    )
    request.setValue("audio/mpeg, audio/*", forHTTPHeaderField: "Accept")

    do {
      let (temporaryURL, response) = try await session.download(
        for: request
      )
      try Task.checkCancellation()

      guard let response = response as? HTTPURLResponse else {
        throw RoutineTTSAudioDownloadError.invalidResponse
      }
      guard let finalURL = response.url,
            finalURL.scheme?.lowercased() == "https",
            let finalHost = finalURL.host,
            !finalHost.isEmpty else {
        throw RoutineTTSAudioDownloadError.insecureURL
      }
      guard (200..<300).contains(response.statusCode) else {
        throw RoutineTTSAudioDownloadError.httpStatus(
          response.statusCode
        )
      }
      guard Self.isSupportedContentType(response.mimeType) else {
        throw RoutineTTSAudioDownloadError.unsupportedContentType
      }
      guard response.expectedContentLength < 0
        || response.expectedContentLength <= Int64(maximumByteCount) else {
        throw RoutineTTSAudioDownloadError.audioTooLarge
      }

      let resourceValues = try temporaryURL.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey]
      )
      guard resourceValues.isRegularFile == true,
            let fileSize = resourceValues.fileSize else {
        throw RoutineTTSAudioDownloadError.invalidResponse
      }
      guard fileSize > 0 else {
        throw RoutineTTSAudioDownloadError.emptyAudio
      }
      guard fileSize <= maximumByteCount else {
        throw RoutineTTSAudioDownloadError.audioTooLarge
      }

      let data = try Data(
        contentsOf: temporaryURL,
        options: [.mappedIfSafe]
      )
      guard data.count == fileSize else {
        throw RoutineTTSAudioDownloadError.invalidResponse
      }
      return data
    } catch let error as URLError
    where error.code == .cancelled || Task.isCancelled {
      throw CancellationError()
    }
  }

  private static func isSupportedContentType(
    _ mimeType: String?
  ) -> Bool {
    guard let mimeType = mimeType?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(),
      !mimeType.isEmpty else {
      return false
    }

    return mimeType.hasPrefix("audio/")
      || mimeType == "application/octet-stream"
  }
}
