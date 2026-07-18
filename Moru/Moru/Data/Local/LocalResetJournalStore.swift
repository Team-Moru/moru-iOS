//
//  LocalResetJournalStore.swift
//  Moru
//

import Darwin
import Foundation

nonisolated enum LocalResetJournalStoreError: Error, Equatable, LocalizedError {
  case corrupt(String)
  case unsupportedFormatVersion(Int)
  case revisionOverflow
  case generationOverflow
  case operationNotFound(UUID)
  case invalidTransition(from: LocalResetJournalPhase, to: LocalResetJournalPhase)
  case invalidRetryPhase(LocalResetJournalPhase)
  case writeFailed(String)
  case writeVerificationFailed
  case readFailed(String)

  var errorDescription: String? {
    switch self {
    case .corrupt(let reason):
      return "The local reset journal is corrupt: \(reason)."
    case .unsupportedFormatVersion(let version):
      return "The local reset journal format version \(version) is unsupported."
    case .revisionOverflow:
      return "The local reset journal revision overflowed."
    case .generationOverflow:
      return "The local reset generation overflowed."
    case .operationNotFound(let operationID):
      return "The local reset operation \(operationID.uuidString) was not found."
    case .invalidTransition(let from, let to):
      return "The local reset journal cannot transition from \(from.rawValue) to \(to.rawValue)."
    case .invalidRetryPhase(let phase):
      return "The local reset journal cannot retry from \(phase.rawValue)."
    case .writeFailed(let reason):
      return "The local reset journal could not be written: \(reason)."
    case .writeVerificationFailed:
      return "The local reset journal write could not be verified."
    case .readFailed(let reason):
      return "The local reset journal could not be read: \(reason)."
    }
  }
}
nonisolated protocol LocalResetJournalSynchronizing: AnyObject {
  func synchronize(at url: URL, isDirectory: Bool) throws
}

nonisolated final class LocalResetJournalFileSynchronizer:
  LocalResetJournalSynchronizing,
  @unchecked Sendable {
  func synchronize(at url: URL, isDirectory: Bool) throws {
    let flags = O_RDONLY | (isDirectory ? O_DIRECTORY : 0)
    let descriptor = Darwin.open(url.path, flags)
    guard descriptor >= 0 else {
      throw LocalResetJournalStoreError.writeFailed(Self.posixErrorDescription())
    }
    defer {
      Darwin.close(descriptor)
    }

    guard Darwin.fsync(descriptor) == 0 else {
      throw LocalResetJournalStoreError.writeFailed(Self.posixErrorDescription())
    }
  }

  private static func posixErrorDescription() -> String {
    String(cString: strerror(errno))
  }
}

nonisolated protocol LocalResetJournalStoring: AnyObject {
  func load() throws -> LocalResetJournalEntry?
  func currentGeneration() throws -> UInt64
  func begin(operationID: UUID, at date: Date) throws -> LocalResetJournalEntry
  func advance(
    operationID: UUID,
    to phase: LocalResetJournalPhase,
    at date: Date
  ) throws -> LocalResetJournalEntry
  func seal(
    operationID: UUID,
    scheduleIDs: [UUID],
    at date: Date
  ) throws -> LocalResetJournalEntry
  func resume(operationID: UUID, at date: Date) throws -> LocalResetJournalEntry
  func preflightAdvance(
    operationID: UUID,
    to phase: LocalResetJournalPhase
  ) throws
  func markRetryRequired(
    operationID: UUID,
    resuming phase: LocalResetJournalPhase,
    at date: Date
  ) throws -> LocalResetJournalEntry
}

nonisolated final class LocalResetJournalStore: LocalResetJournalStoring, @unchecked Sendable {
  private static let processLock = NSLock()

  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let synchronizer: any LocalResetJournalSynchronizing

  init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default,
    synchronizer: any LocalResetJournalSynchronizing = LocalResetJournalFileSynchronizer()
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    self.fileManager = fileManager
    self.synchronizer = synchronizer
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    decoder = JSONDecoder()
  }

  func load() throws -> LocalResetJournalEntry? {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    return try loadLocked()
  }
  func currentGeneration() throws -> UInt64 {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    return try loadLocked()?.generation ?? 1
  }

  func begin(operationID: UUID, at date: Date) throws -> LocalResetJournalEntry {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let current = try loadLocked()
    if let current, !current.phase.isTerminal {
      return current
    }

    let generation = try increment(current?.generation ?? 1, overflow: .generationOverflow)
    let revision = try increment(current?.revision, overflow: .revisionOverflow)
    let entry = LocalResetJournalEntry(
      operationID: operationID,
      revision: revision,
      generation: generation,
      phase: .freezeRequested,
      createdAt: date,
      updatedAt: date
    )
    try persistLocked(entry)
    return entry
  }

  func advance(
    operationID: UUID,
    to phase: LocalResetJournalPhase,
    at date: Date
  ) throws -> LocalResetJournalEntry {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let current = try requireCurrentLocked(operationID: operationID)
    guard Self.canAdvance(from: current.phase, to: phase) else {
      throw LocalResetJournalStoreError.invalidTransition(from: current.phase, to: phase)
    }

    let entry = LocalResetJournalEntry(
      operationID: current.operationID,
      revision: try increment(current.revision, overflow: .revisionOverflow),
      generation: current.generation,
      phase: phase,
      sealedScheduleIDs: current.sealedScheduleIDs,
      createdAt: current.createdAt,
      updatedAt: date
    )
    try persistLocked(entry)
    return entry
  }
  func preflightAdvance(
    operationID: UUID,
    to phase: LocalResetJournalPhase
  ) throws {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let current = try requireCurrentLocked(operationID: operationID)
    guard Self.canAdvance(from: current.phase, to: phase) else {
      throw LocalResetJournalStoreError.invalidTransition(from: current.phase, to: phase)
    }
    _ = try increment(current.revision, overflow: .revisionOverflow)
  }

  func seal(
    operationID: UUID,
    scheduleIDs: [UUID],
    at date: Date
  ) throws -> LocalResetJournalEntry {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let current = try requireCurrentLocked(operationID: operationID)
    guard current.phase == .gathering else {
      throw LocalResetJournalStoreError.invalidTransition(from: current.phase, to: .sealed)
    }

    let entry = LocalResetJournalEntry(
      operationID: current.operationID,
      revision: try increment(current.revision, overflow: .revisionOverflow),
      generation: current.generation,
      phase: .sealed,
      sealedScheduleIDs: Self.canonicalScheduleIDs(scheduleIDs),
      createdAt: current.createdAt,
      updatedAt: date
    )
    try persistLocked(entry)
    return entry
  }

  func resume(operationID: UUID, at date: Date) throws -> LocalResetJournalEntry {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let current = try requireCurrentLocked(operationID: operationID)
    guard current.phase == .retryRequired, let resumePhase = current.resumePhase else {
      throw LocalResetJournalStoreError.invalidTransition(from: current.phase, to: current.phase)
    }

    let entry = LocalResetJournalEntry(
      operationID: current.operationID,
      revision: try increment(current.revision, overflow: .revisionOverflow),
      generation: current.generation,
      phase: resumePhase,
      sealedScheduleIDs: current.sealedScheduleIDs,
      createdAt: current.createdAt,
      updatedAt: date
    )
    try persistLocked(entry)
    return entry
  }

  func markRetryRequired(
    operationID: UUID,
    resuming phase: LocalResetJournalPhase,
    at date: Date
  ) throws -> LocalResetJournalEntry {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let current = try requireCurrentLocked(operationID: operationID)
    guard current.phase == phase, Self.isRetryable(phase) else {
      throw LocalResetJournalStoreError.invalidRetryPhase(phase)
    }

    let entry = LocalResetJournalEntry(
      operationID: current.operationID,
      revision: try increment(current.revision, overflow: .revisionOverflow),
      generation: current.generation,
      phase: .retryRequired,
      resumePhase: phase,
      sealedScheduleIDs: current.sealedScheduleIDs,
      createdAt: current.createdAt,
      updatedAt: date
    )
    try persistLocked(entry)
    return entry
  }

  static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let applicationSupportURL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return applicationSupportURL
      .appendingPathComponent("MORU", isDirectory: true)
      .appendingPathComponent("LocalResetJournal.json", isDirectory: false)
  }

  private func loadLocked() throws -> LocalResetJournalEntry? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw LocalResetJournalStoreError.readFailed(error.localizedDescription)
    }

    let entry: LocalResetJournalEntry
    do {
      entry = try decoder.decode(LocalResetJournalEntry.self, from: data)
    } catch {
      throw LocalResetJournalStoreError.corrupt(error.localizedDescription)
    }

    try validate(entry)
    return entry
  }

  private func requireCurrentLocked(operationID: UUID) throws -> LocalResetJournalEntry {
    guard let current = try loadLocked(), current.operationID == operationID else {
      throw LocalResetJournalStoreError.operationNotFound(operationID)
    }
    return current
  }

  private func persistLocked(_ entry: LocalResetJournalEntry) throws {
    try validate(entry)

    let directoryURL = fileURL.deletingLastPathComponent()
    let requiresParentSynchronization =
      !fileManager.fileExists(atPath: directoryURL.path) ||
      !fileManager.fileExists(atPath: fileURL.path)
    let directoryAttributes: [FileAttributeKey: Any] = [
      .posixPermissions: NSNumber(value: 0o700)
    ]
    let fileAttributes: [FileAttributeKey: Any] = [
      .posixPermissions: NSNumber(value: 0o600),
      .protectionKey: FileProtectionType.complete
    ]

    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: directoryAttributes
      )
      try fileManager.setAttributes(directoryAttributes, ofItemAtPath: directoryURL.path)
      if requiresParentSynchronization {
        try synchronize(at: directoryURL.deletingLastPathComponent(), isDirectory: true)
      }
    } catch let error as LocalResetJournalStoreError {
      throw error
    } catch {
      throw LocalResetJournalStoreError.writeFailed(error.localizedDescription)
    }

    let data: Data
    do {
      data = try encoder.encode(entry)
    } catch {
      throw LocalResetJournalStoreError.writeFailed(error.localizedDescription)
    }

    let temporaryURL = directoryURL.appendingPathComponent(
      ".LocalResetJournal-\(UUID().uuidString).tmp",
      isDirectory: false
    )
    defer {
      if fileManager.fileExists(atPath: temporaryURL.path) {
        try? fileManager.removeItem(at: temporaryURL)
      }
    }

    guard fileManager.createFile(
      atPath: temporaryURL.path,
      contents: data,
      attributes: fileAttributes
    ) else {
      throw LocalResetJournalStoreError.writeFailed("Unable to create a journal temporary file.")
    }

    do {
      let readback = try Data(contentsOf: temporaryURL)
      guard readback == data else {
        throw LocalResetJournalStoreError.writeVerificationFailed
      }
    } catch let error as LocalResetJournalStoreError {
      throw error
    } catch {
      throw LocalResetJournalStoreError.writeFailed(error.localizedDescription)
    }
    try synchronize(at: temporaryURL, isDirectory: false)

    do {
      if fileManager.fileExists(atPath: fileURL.path) {
        _ = try fileManager.replaceItemAt(
          fileURL,
          withItemAt: temporaryURL,
          backupItemName: nil,
          options: []
        )
      } else {
        try fileManager.moveItem(at: temporaryURL, to: fileURL)
      }
      try fileManager.setAttributes(fileAttributes, ofItemAtPath: fileURL.path)

      let readback = try Data(contentsOf: fileURL)
      guard readback == data else {
        throw LocalResetJournalStoreError.writeVerificationFailed
      }
    } catch let error as LocalResetJournalStoreError {
      throw error
    } catch {
      throw LocalResetJournalStoreError.writeFailed(error.localizedDescription)
    }
    try synchronize(at: directoryURL, isDirectory: true)
  }

  private func validate(_ entry: LocalResetJournalEntry) throws {
    guard entry.formatVersion == LocalResetJournalEntry.currentFormatVersion else {
      throw LocalResetJournalStoreError.unsupportedFormatVersion(entry.formatVersion)
    }
    guard entry.revision > 0, entry.generation > 0 else {
      throw LocalResetJournalStoreError.corrupt(
        "revision and generation must be greater than zero"
      )
    }
    guard Self.isStrictlySorted(entry.sealedScheduleIDs) else {
      throw LocalResetJournalStoreError.corrupt("sealed schedule IDs are not strictly sorted")
    }

    switch entry.phase {
    case .freezeRequested, .gathering:
      guard entry.resumePhase == nil, entry.sealedScheduleIDs.isEmpty else {
        throw LocalResetJournalStoreError.corrupt("a pre-seal phase contains sealed data")
      }
    case .sealed, .cancelling, .swiftDataDeleting, .coordinatorClearing, .completed:
      guard entry.resumePhase == nil else {
        throw LocalResetJournalStoreError.corrupt("a forward phase contains a retry phase")
      }
    case .retryRequired:
      guard let resumePhase = entry.resumePhase, Self.isRetryable(resumePhase) else {
        throw LocalResetJournalStoreError.corrupt("retryRequired has an invalid resume phase")
      }
      if resumePhase == .gathering, !entry.sealedScheduleIDs.isEmpty {
        throw LocalResetJournalStoreError.corrupt("a pre-seal retry contains sealed data")
      }
    }
  }

  private func increment(
    _ value: UInt64?,
    overflow error: LocalResetJournalStoreError
  ) throws -> UInt64 {
    let value = value ?? 0
    let (incremented, didOverflow) = value.addingReportingOverflow(1)
    guard !didOverflow else {
      throw error
    }
    return incremented
  }

  private static func canAdvance(
    from: LocalResetJournalPhase,
    to: LocalResetJournalPhase
  ) -> Bool {
    switch (from, to) {
    case (.freezeRequested, .gathering),
         (.sealed, .cancelling),
         (.cancelling, .swiftDataDeleting),
         (.swiftDataDeleting, .coordinatorClearing),
         (.coordinatorClearing, .completed):
      return true
    default:
      return false
    }
  }

  private static func isRetryable(_ phase: LocalResetJournalPhase) -> Bool {
    switch phase {
    case .gathering, .cancelling, .swiftDataDeleting, .coordinatorClearing:
      return true
    case .freezeRequested, .sealed, .completed, .retryRequired:
      return false
    }
  }

  private static func canonicalScheduleIDs(_ scheduleIDs: [UUID]) -> [UUID] {
    Array(Set(scheduleIDs)).sorted { left, right in
      canonicalUUID(left).utf8.lexicographicallyPrecedes(canonicalUUID(right).utf8)
    }
  }

  private static func isStrictlySorted(_ scheduleIDs: [UUID]) -> Bool {
    zip(scheduleIDs, scheduleIDs.dropFirst()).allSatisfy { left, right in
      canonicalUUID(left).utf8.lexicographicallyPrecedes(canonicalUUID(right).utf8)
    }
  }

  private static func canonicalUUID(_ id: UUID) -> String {
    id.uuidString.lowercased()
  }
  private func synchronize(
    at url: URL,
    isDirectory: Bool
  ) throws {
    do {
      try synchronizer.synchronize(at: url, isDirectory: isDirectory)
    } catch let error as LocalResetJournalStoreError {
      throw error
    } catch {
      throw LocalResetJournalStoreError.writeFailed(error.localizedDescription)
    }
  }
}
