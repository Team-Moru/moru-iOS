//
//  RoutineTTSAudioFileStore.swift
//  Moru
//

import Foundation

nonisolated struct RoutineTTSAudioAssetManifestItem:
  Equatable,
  Hashable,
  Sendable {
  let localRoutineID: UUID
  let localStepID: UUID
  let serverStepID: Int64
  let cachedRelativePath: String
  let orderIndex: Int
}

nonisolated enum RoutineTTSAudioFileStoreError: Error, Equatable {
  case emptyAudio
  case invalidServerStepID
  case invalidRelativePath
}

nonisolated final class RoutineTTSAudioFileStore: @unchecked Sendable {
  private let rootDirectory: URL
  private let fileManager: FileManager
  private let lock = NSLock()

  init(
    rootDirectory: URL,
    fileManager: FileManager = .default
  ) {
    self.rootDirectory = rootDirectory.standardizedFileURL
    self.fileManager = fileManager
  }

  convenience init(fileManager: FileManager = .default) {
    let cacheRoot = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory

    self.init(
      rootDirectory: cacheRoot
        .appendingPathComponent("Moru", isDirectory: true)
        .appendingPathComponent("RoutineTTS", isDirectory: true),
      fileManager: fileManager
    )
  }

  func store(
    _ data: Data,
    localRoutineID: UUID,
    localStepID: UUID,
    serverStepID: Int64
  ) throws -> String {
    guard !data.isEmpty else {
      throw RoutineTTSAudioFileStoreError.emptyAudio
    }
    guard serverStepID > 0 else {
      throw RoutineTTSAudioFileStoreError.invalidServerStepID
    }

    let relativePath = Self.relativePath(
      localRoutineID: localRoutineID,
      localStepID: localStepID,
      serverStepID: serverStepID
    )
    guard let destinationURL = validatedURL(for: relativePath) else {
      throw RoutineTTSAudioFileStoreError.invalidRelativePath
    }

    lock.lock()
    defer { lock.unlock() }

    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destinationURL, options: .atomic)
    return relativePath
  }

  func cachedAudioURL(relativePath: String) -> URL? {
    guard let url = validatedURL(for: relativePath) else {
      return nil
    }

    lock.lock()
    defer { lock.unlock() }

    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let fileType = attributes[.type] as? FileAttributeType,
          fileType == .typeRegular,
          let fileSize = attributes[.size] as? NSNumber,
          fileSize.intValue > 0 else {
      return nil
    }

    return url
  }

  func removeAssets(localRoutineID: UUID, localStepID: UUID) throws {
    let relativePath = [
      localRoutineID.uuidString.lowercased(),
      localStepID.uuidString.lowercased(),
    ].joined(separator: "/")
    guard let directoryURL = validatedURL(for: relativePath) else {
      throw RoutineTTSAudioFileStoreError.invalidRelativePath
    }

    lock.lock()
    defer { lock.unlock() }

    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return
    }
    try fileManager.removeItem(at: directoryURL)
  }

  func removeAssets(localRoutineID: UUID) throws {
    let relativePath = localRoutineID.uuidString.lowercased()
    guard let directoryURL = validatedURL(for: relativePath) else {
      throw RoutineTTSAudioFileStoreError.invalidRelativePath
    }

    lock.lock()
    defer { lock.unlock() }

    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return
    }
    try fileManager.removeItem(at: directoryURL)
  }

  func removeAllAssets() throws {
    lock.lock()
    defer { lock.unlock() }

    guard fileManager.fileExists(atPath: rootDirectory.path) else {
      return
    }
    try fileManager.removeItem(at: rootDirectory)
  }

  static func relativePath(
    localRoutineID: UUID,
    localStepID: UUID,
    serverStepID: Int64
  ) -> String {
    [
      localRoutineID.uuidString.lowercased(),
      localStepID.uuidString.lowercased(),
      "\(serverStepID).mp3",
    ].joined(separator: "/")
  }

  private func validatedURL(for relativePath: String) -> URL? {
    guard !relativePath.isEmpty,
          !relativePath.hasPrefix("/") else {
      return nil
    }

    let candidate = rootDirectory
      .appendingPathComponent(relativePath)
      .standardizedFileURL
    let rootPath = rootDirectory.path

    guard candidate.path.hasPrefix(rootPath + "/") else {
      return nil
    }
    return candidate
  }
}
