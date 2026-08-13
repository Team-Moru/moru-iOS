//
//  RoutineTTSAudioCache.swift
//  Moru
//

import CryptoKit
import Foundation

nonisolated struct RoutineTTSAudioCacheKey: Hashable, Sendable {
  let accountID: String
  let namespace: String
  let routineGroupID: Int64
  let routineID: Int64
  let stepID: Int64
  let remoteURL: URL

  init(
    accountID: String,
    namespace: String,
    routineGroupID: Int64,
    routineID: Int64,
    stepID: Int64,
    remoteURL: URL
  ) {
    self.accountID = accountID
    self.namespace = namespace
    self.routineGroupID = routineGroupID
    self.routineID = routineID
    self.stepID = stepID
    self.remoteURL = remoteURL
  }
}

nonisolated struct RoutineTTSAudioCachePolicy: Equatable, Sendable {
  let maximumFileBytes: Int64
  let maximumAccountBytes: Int64
  let maximumTotalBytes: Int64
  let freshTimeToLive: TimeInterval
  let maximumStaleAge: TimeInterval

  init(
    maximumFileBytes: Int64 = RoutineTTSAudioDownloadPolicy.maximumAudioBytes,
    maximumAccountBytes: Int64 = 50 * 1_024 * 1_024,
    maximumTotalBytes: Int64 = 100 * 1_024 * 1_024,
    freshTimeToLive: TimeInterval = 24 * 60 * 60,
    maximumStaleAge: TimeInterval = 7 * 24 * 60 * 60
  ) {
    precondition(maximumFileBytes > 0)
    precondition(maximumAccountBytes >= maximumFileBytes)
    precondition(maximumTotalBytes >= maximumAccountBytes)
    precondition(freshTimeToLive >= 0)
    precondition(maximumStaleAge >= freshTimeToLive)
    self.maximumFileBytes = maximumFileBytes
    self.maximumAccountBytes = maximumAccountBytes
    self.maximumTotalBytes = maximumTotalBytes
    self.freshTimeToLive = freshTimeToLive
    self.maximumStaleAge = maximumStaleAge
  }
}

nonisolated enum RoutineTTSAudioCacheError: Error, Equatable, Sendable {
  case invalidKey
  case invalidSourceFile
  case fileTooLarge
  case storageFailure
}

actor RoutineTTSAudioCache {
  typealias Clock = @Sendable () -> Date
  typealias Loader = @Sendable (_ stagingDirectory: URL) async throws
    -> RoutineTTSAudioDownloadedFile

  private static let formatVersion = 1
  private static let audioExtension = "audio"
  private static let metadataExtension = "json"
  private static let stagingDirectoryName = ".staging"

  private let rootDirectory: URL
  private let policy: RoutineTTSAudioCachePolicy
  private let now: Clock
  private let fileManager: FileManager
  private var inFlight: [String: InFlight] = [:]
  private var accountGenerations: [String: UInt64] = [:]
  private var globalGeneration: UInt64 = 0

  init(
    rootDirectory: URL? = nil,
    policy: RoutineTTSAudioCachePolicy = RoutineTTSAudioCachePolicy(),
    now: @escaping Clock = Date.init,
    fileManager: FileManager = .default
  ) throws {
    let resolvedRoot = try rootDirectory ?? Self.defaultRootDirectory(
      fileManager: fileManager
    )
    self.rootDirectory = resolvedRoot
    self.policy = policy
    self.now = now
    self.fileManager = fileManager
    try fileManager.createDirectory(
      at: resolvedRoot,
      withIntermediateDirectories: true
    )
    try Self.excludeFromBackup(resolvedRoot)
    try Self.cleanupIncompleteEntries(
      under: resolvedRoot,
      fileManager: fileManager
    )
  }

  func cachedFileURL(
    for key: RoutineTTSAudioCacheKey,
    allowStale: Bool = false
  ) -> URL? {
    guard let identity = try? identity(for: key),
          let entry = validatedEntry(identity: identity, at: now()) else {
      return nil
    }
    let age = max(0, now().timeIntervalSince(entry.metadata.createdAt))
    if age > policy.maximumStaleAge {
      removeEntry(identity: identity)
      return nil
    }
    guard allowStale || age <= policy.freshTimeToLive else {
      return nil
    }
    var touched = entry.metadata
    touched.lastAccessedAt = now()
    guard (try? writeMetadata(touched, to: identity.metadataURL)) != nil else {
      removeEntry(identity: identity)
      return nil
    }
    return identity.audioURL
  }

  func storeDownloadedFile(
    at sourceURL: URL,
    for key: RoutineTTSAudioCacheKey
  ) throws -> URL {
    let identity = try identity(for: key)
    do {
      let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
      guard let size = attributes[.size] as? NSNumber,
            size.int64Value > 0 else {
        throw RoutineTTSAudioCacheError.invalidSourceFile
      }
      guard size.int64Value <= policy.maximumFileBytes else {
        throw RoutineTTSAudioCacheError.fileTooLarge
      }
    } catch let error as RoutineTTSAudioCacheError {
      throw error
    } catch {
      throw RoutineTTSAudioCacheError.invalidSourceFile
    }
    let data: Data
    do {
      data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
    } catch {
      throw RoutineTTSAudioCacheError.invalidSourceFile
    }
    guard !data.isEmpty else {
      throw RoutineTTSAudioCacheError.invalidSourceFile
    }
    guard data.count <= policy.maximumFileBytes else {
      throw RoutineTTSAudioCacheError.fileTooLarge
    }

    do {
      try fileManager.createDirectory(
        at: identity.accountDirectory,
        withIntermediateDirectories: true
      )
      try Self.excludeFromBackup(identity.accountDirectory)
      let partialAudioURL = identity.accountDirectory
        .appendingPathComponent(".\(UUID().uuidString).partial")
      defer { try? fileManager.removeItem(at: partialAudioURL) }
      try data.write(
        to: partialAudioURL,
        options: [.atomic, .completeFileProtectionUnlessOpen]
      )

      let timestamp = now()
      let metadata = Metadata(
        formatVersion: Self.formatVersion,
        cacheKeyDigest: identity.cacheKeyDigest,
        contentDigest: Self.sha256Hex(data),
        byteCount: Int64(data.count),
        createdAt: timestamp,
        lastAccessedAt: timestamp
      )

      // Metadata is the commit marker. Readers never accept an audio-only entry.
      removeEntry(identity: identity)
      try fileManager.moveItem(at: partialAudioURL, to: identity.audioURL)
      do {
        try writeMetadata(metadata, to: identity.metadataURL)
      } catch {
        try? fileManager.removeItem(at: identity.audioURL)
        throw error
      }
      try Self.excludeFromBackup(identity.audioURL)
      try Self.excludeFromBackup(identity.metadataURL)
      enforceQuotas(protecting: identity.cacheKeyDigest)
      return identity.audioURL
    } catch let error as RoutineTTSAudioCacheError {
      throw error
    } catch {
      removeEntry(identity: identity)
      throw RoutineTTSAudioCacheError.storageFailure
    }
  }

  func fileURL(
    for key: RoutineTTSAudioCacheKey,
    allowStale: Bool = false,
    loader: @escaping Loader
  ) async throws -> URL {
    if let cached = cachedFileURL(for: key, allowStale: allowStale) {
      return cached
    }
    let identity = try identity(for: key)
    if let existing = inFlight[identity.cacheKeyDigest] {
      return try await existing.task.value
    }

    let capturedAccountGeneration = accountGenerations[identity.accountDigest, default: 0]
    let capturedGlobalGeneration = globalGeneration
    let token = UUID()
    let stagingDirectory = identity.stagingRootDirectory
      .appendingPathComponent(token.uuidString, isDirectory: true)
    do {
      try fileManager.createDirectory(
        at: stagingDirectory,
        withIntermediateDirectories: true
      )
      try Self.excludeFromBackup(stagingDirectory)
      try Self.applyCompleteProtectionUnlessOpen(
        to: stagingDirectory,
        fileManager: fileManager
      )
    } catch {
      throw RoutineTTSAudioCacheError.storageFailure
    }
    let task = Task { [self] in
      defer { try? fileManager.removeItemIfPresent(at: stagingDirectory) }
      let downloaded = try await loader(stagingDirectory)
      defer { try? fileManager.removeItem(at: downloaded.fileURL) }
      try Task.checkCancellation()
      guard accountGenerations[identity.accountDigest, default: 0]
        == capturedAccountGeneration,
        globalGeneration == capturedGlobalGeneration else {
        throw CancellationError()
      }
      return try storeDownloadedFile(at: downloaded.fileURL, for: key)
    }
    inFlight[identity.cacheKeyDigest] = InFlight(
      token: token,
      task: task,
      accountDigest: identity.accountDigest
    )
    defer {
      if inFlight[identity.cacheKeyDigest]?.token == token {
        inFlight[identity.cacheKeyDigest] = nil
      }
    }
    return try await task.value
  }

  func purge(accountID: String, namespace: String) throws {
    guard !accountID.isEmpty, !namespace.isEmpty else {
      throw RoutineTTSAudioCacheError.invalidKey
    }
    let accountDigest = Self.accountDigest(accountID: accountID)
    cancelInFlight(accountDigest: accountDigest)
    accountGenerations[accountDigest, default: 0] &+= 1
    let directory = rootDirectory
      .appendingPathComponent(accountDigest, isDirectory: true)
      .appendingPathComponent(
        Self.namespaceDigest(namespace),
        isDirectory: true
      )
    do {
      try fileManager.removeItemIfPresent(at: directory)
    } catch {
      throw RoutineTTSAudioCacheError.storageFailure
    }
  }

  func purge(accountID: String) throws {
    guard !accountID.isEmpty else {
      throw RoutineTTSAudioCacheError.invalidKey
    }
    let accountDigest = Self.accountDigest(accountID: accountID)
    cancelInFlight(accountDigest: accountDigest)
    accountGenerations[accountDigest, default: 0] &+= 1
    let directory = rootDirectory.appendingPathComponent(
      accountDigest,
      isDirectory: true
    )
    do {
      try fileManager.removeItemIfPresent(at: directory)
    } catch {
      throw RoutineTTSAudioCacheError.storageFailure
    }
  }

  func purgeAll() throws {
    for operation in inFlight.values {
      operation.task.cancel()
    }
    inFlight.removeAll()
    globalGeneration &+= 1
    do {
      for child in try fileManager.contentsOfDirectory(
        at: rootDirectory,
        includingPropertiesForKeys: nil
      ) {
        try fileManager.removeItem(at: child)
      }
    } catch {
      throw RoutineTTSAudioCacheError.storageFailure
    }
  }

  func removeFile(for key: RoutineTTSAudioCacheKey) throws {
    let identity = try identity(for: key)
    removeEntry(identity: identity)
  }

  private func identity(for key: RoutineTTSAudioCacheKey) throws -> Identity {
    guard !key.accountID.isEmpty,
          !key.namespace.isEmpty,
          key.routineGroupID > 0,
          key.routineID > 0,
          key.stepID > 0,
          let normalizedURL = Self.normalizedOriginAndPath(key.remoteURL) else {
      throw RoutineTTSAudioCacheError.invalidKey
    }
    let accountDigest = Self.accountDigest(accountID: key.accountID)
    let digest = Self.digest(
      components: [
        key.accountID,
        key.namespace,
        String(key.routineGroupID),
        String(key.routineID),
        String(key.stepID),
        normalizedURL,
      ]
    )
    let accountRoot = rootDirectory.appendingPathComponent(
      accountDigest,
      isDirectory: true
    )
    let accountDirectory = accountRoot.appendingPathComponent(
      Self.namespaceDigest(key.namespace),
      isDirectory: true
    )
    return Identity(
      cacheKeyDigest: digest,
      accountDigest: accountDigest,
      accountRoot: accountRoot,
      accountDirectory: accountDirectory,
      audioURL: accountDirectory
        .appendingPathComponent(digest)
        .appendingPathExtension(Self.audioExtension),
      metadataURL: accountDirectory
        .appendingPathComponent(digest)
        .appendingPathExtension(Self.metadataExtension),
      stagingRootDirectory: accountDirectory.appendingPathComponent(
        Self.stagingDirectoryName,
        isDirectory: true
      )
    )
  }

  private func validatedEntry(
    identity: Identity,
    at timestamp: Date
  ) -> ValidatedEntry? {
    guard fileManager.fileExists(atPath: identity.audioURL.path),
          fileManager.fileExists(atPath: identity.metadataURL.path) else {
      removeEntry(identity: identity)
      return nil
    }
    do {
      let metadataData = try Data(contentsOf: identity.metadataURL)
      let metadata = try JSONDecoder.routineTTSDecoder
        .decode(Metadata.self, from: metadataData)
      guard metadata.formatVersion == Self.formatVersion,
            metadata.cacheKeyDigest == identity.cacheKeyDigest,
            metadata.byteCount > 0,
            metadata.byteCount <= policy.maximumFileBytes,
            metadata.createdAt <= timestamp.addingTimeInterval(60),
            metadata.lastAccessedAt <= timestamp.addingTimeInterval(60) else {
        throw RoutineTTSAudioCacheError.invalidSourceFile
      }
      let attributes = try fileManager.attributesOfItem(
        atPath: identity.audioURL.path
      )
      guard let size = attributes[.size] as? NSNumber,
            size.int64Value == metadata.byteCount else {
        throw RoutineTTSAudioCacheError.invalidSourceFile
      }
      let data = try Data(contentsOf: identity.audioURL, options: [.mappedIfSafe])
      guard Int64(data.count) == metadata.byteCount,
            Self.sha256Hex(data) == metadata.contentDigest else {
        throw RoutineTTSAudioCacheError.invalidSourceFile
      }
      return ValidatedEntry(metadata: metadata)
    } catch {
      removeEntry(identity: identity)
      return nil
    }
  }

  private func writeMetadata(_ metadata: Metadata, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let data = try encoder.encode(metadata)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }

  private func enforceQuotas(protecting protectedDigest: String) {
    guard let entries = try? allEntries() else { return }
    if let protectedEntry = entries.first(where: {
      $0.cacheKeyDigest == protectedDigest
    }) {
      evict(
        entries.filter { $0.accountRoot == protectedEntry.accountRoot },
        toMaximumBytes: policy.maximumAccountBytes,
        protecting: protectedDigest
      )
    }
    guard let refreshed = try? allEntries() else { return }
    evict(
      refreshed,
      toMaximumBytes: policy.maximumTotalBytes,
      protecting: protectedDigest
    )
  }

  private func evict(
    _ entries: [DiskEntry],
    toMaximumBytes maximumBytes: Int64,
    protecting protectedDigest: String
  ) {
    var currentBytes = entries.reduce(Int64(0)) { $0 + $1.metadata.byteCount }
    for entry in entries.sorted(by: {
      $0.metadata.lastAccessedAt < $1.metadata.lastAccessedAt
    }) where currentBytes > maximumBytes && entry.cacheKeyDigest != protectedDigest {
      try? fileManager.removeItemIfPresent(at: entry.audioURL)
      try? fileManager.removeItemIfPresent(at: entry.metadataURL)
      currentBytes -= entry.metadata.byteCount
    }
  }

  private func allEntries() throws -> [DiskEntry] {
    guard let enumerator = fileManager.enumerator(
      at: rootDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else { return [] }
    var result: [DiskEntry] = []
    for case let metadataURL as URL in enumerator
    where metadataURL.pathExtension == Self.metadataExtension {
      guard let metadata = try? JSONDecoder.routineTTSDecoder
        .decode(Metadata.self, from: Data(contentsOf: metadataURL)) else {
        try? fileManager.removeItem(at: metadataURL)
        continue
      }
      let audioURL = metadataURL
        .deletingPathExtension()
        .appendingPathExtension(Self.audioExtension)
      guard fileManager.fileExists(atPath: audioURL.path) else {
        try? fileManager.removeItem(at: metadataURL)
        continue
      }
      result.append(
        DiskEntry(
          cacheKeyDigest: metadata.cacheKeyDigest,
          accountRoot: metadataURL
            .deletingLastPathComponent()
            .deletingLastPathComponent(),
          audioURL: audioURL,
          metadataURL: metadataURL,
          metadata: metadata
        )
      )
    }
    return result
  }

  private func removeEntry(identity: Identity) {
    try? fileManager.removeItemIfPresent(at: identity.audioURL)
    try? fileManager.removeItemIfPresent(at: identity.metadataURL)
  }

  private static func defaultRootDirectory(
    fileManager: FileManager
  ) throws -> URL {
    guard let caches = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first else {
      throw RoutineTTSAudioCacheError.storageFailure
    }
    return caches
      .appendingPathComponent("MoruRoutineTTS", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
  }

  private static func normalizedOriginAndPath(_ url: URL) -> String? {
    guard RoutineTTSAudioDownloader.isAllowedHTTPSURL(url),
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let host = components.host?.lowercased() else {
      return nil
    }
    components.scheme = "https"
    components.host = host
    components.query = nil
    components.fragment = nil
    let port = components.port
    components.port = port == 443 ? nil : port
    return components.string
  }

  private func cancelInFlight(accountDigest: String) {
    let matching = inFlight.filter { $0.value.accountDigest == accountDigest }
    for (key, operation) in matching {
      operation.task.cancel()
      inFlight[key] = nil
    }
  }

  private static func accountDigest(accountID: String) -> String {
    digest(components: ["account", accountID])
  }

  private static func namespaceDigest(_ namespace: String) -> String {
    digest(components: ["namespace", namespace])
  }

  private static func digest(components: [String]) -> String {
    var input = Data()
    for component in components {
      let bytes = Data(component.utf8)
      var length = UInt64(bytes.count).bigEndian
      withUnsafeBytes(of: &length) { input.append(contentsOf: $0) }
      input.append(bytes)
    }
    return sha256Hex(input)
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func excludeFromBackup(_ url: URL) throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableURL = url
    try mutableURL.setResourceValues(values)
  }

  private static func applyCompleteProtectionUnlessOpen(
    to url: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUnlessOpen],
      ofItemAtPath: url.path
    )
  }

  private static func cleanupIncompleteEntries(
    under root: URL,
    fileManager: FileManager
  ) throws {
    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: []
    ) else { return }
    var audioURLs: Set<URL> = []
    var metadataURLs: Set<URL> = []
    for case let url as URL in enumerator {
      if url.lastPathComponent == stagingDirectoryName {
        enumerator.skipDescendants()
        try? fileManager.removeItem(at: url)
      } else if url.lastPathComponent.contains(".partial") {
        try? fileManager.removeItem(at: url)
      } else if url.pathExtension == audioExtension {
        audioURLs.insert(url.deletingPathExtension())
      } else if url.pathExtension == metadataExtension {
        metadataURLs.insert(url.deletingPathExtension())
      }
    }
    for orphan in audioURLs.subtracting(metadataURLs) {
      try? fileManager.removeItem(at: orphan.appendingPathExtension(audioExtension))
    }
    for orphan in metadataURLs.subtracting(audioURLs) {
      try? fileManager.removeItem(at: orphan.appendingPathExtension(metadataExtension))
    }
  }

  private struct Identity {
    let cacheKeyDigest: String
    let accountDigest: String
    let accountRoot: URL
    let accountDirectory: URL
    let audioURL: URL
    let metadataURL: URL
    let stagingRootDirectory: URL
  }

  private struct Metadata: Codable {
    let formatVersion: Int
    let cacheKeyDigest: String
    let contentDigest: String
    let byteCount: Int64
    let createdAt: Date
    var lastAccessedAt: Date
  }

  private struct ValidatedEntry {
    let metadata: Metadata
  }

  private struct DiskEntry {
    let cacheKeyDigest: String
    let accountRoot: URL
    let audioURL: URL
    let metadataURL: URL
    let metadata: Metadata
  }

  private struct InFlight {
    let token: UUID
    let task: Task<URL, Error>
    let accountDigest: String
  }
}

nonisolated private extension JSONDecoder {
  static var routineTTSDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }
}

nonisolated private extension FileManager {
  func removeItemIfPresent(at url: URL) throws {
    guard fileExists(atPath: url.path) else { return }
    try removeItem(at: url)
  }
}
