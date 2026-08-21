//
//  RoutineTTSPrefetchPersistence.swift
//  Moru
//


import CryptoKit
import Foundation
import Observation
import OSLog

nonisolated enum RoutineTTSPrefetchJobState: String, Codable, Sendable {
  case pendingRemote
  case downloading
  case completed
  case retryScheduled
}

nonisolated enum RoutineTTSPrefetchAssetState: String, Codable, Sendable {
  case queued
  case downloading
  case completed
}

nonisolated struct RoutineTTSPrefetchAsset: Codable, Equatable, Sendable {
  let id: UUID
  let cacheKey: RoutineTTSAudioCacheKey
  var state: RoutineTTSPrefetchAssetState

  init(
    id: UUID = UUID(),
    cacheKey: RoutineTTSAudioCacheKey,
    state: RoutineTTSPrefetchAssetState = .queued
  ) {
    self.id = id
    self.cacheKey = cacheKey
    self.state = state
  }
}

/// The durable key deliberately contains no routine title or spoken content.
/// A one-way fingerprint lets playback reject a locally edited routine without
/// persisting that content beside the background-transfer queue.
nonisolated struct RoutineTTSPrefetchJob: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let memberID: Int64
  let selectionVersion: Int64?
  let selectedTTSID: Int64?
  let assetKind: RoutineTTSAudioCacheKey.AssetKind
  let routineGroupLocalID: UUID?
  let routineLocalID: UUID?
  let routineFingerprint: String?
  let routineGroupRemoteID: Int64?
  let routineRemoteID: Int64?
  var state: RoutineTTSPrefetchJobState
  var assets: [RoutineTTSPrefetchAsset]
  var remoteAttemptCount: Int
  var nextRemoteAttemptAt: Date?
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64? = nil,
    assetKind: RoutineTTSAudioCacheKey.AssetKind,
    routineGroupLocalID: UUID? = nil,
    routineLocalID: UUID? = nil,
    routineFingerprint: String? = nil,
    routineGroupRemoteID: Int64? = nil,
    routineRemoteID: Int64? = nil,
    state: RoutineTTSPrefetchJobState,
    assets: [RoutineTTSPrefetchAsset] = [],
    remoteAttemptCount: Int = 0,
    nextRemoteAttemptAt: Date? = nil,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.memberID = memberID
    self.selectionVersion = selectionVersion
    self.selectedTTSID = selectedTTSID
    self.assetKind = assetKind
    self.routineGroupLocalID = routineGroupLocalID
    self.routineLocalID = routineLocalID
    self.routineFingerprint = routineFingerprint
    self.routineGroupRemoteID = routineGroupRemoteID
    self.routineRemoteID = routineRemoteID
    self.state = state
    self.assets = assets
    self.remoteAttemptCount = remoteAttemptCount
    self.nextRemoteAttemptAt = nextRemoteAttemptAt
    self.updatedAt = updatedAt
  }

  func hasSameDurableKey(as other: Self) -> Bool {
    memberID == other.memberID
      && selectionVersion == other.selectionVersion
      && selectedTTSID == other.selectedTTSID
      && assetKind == other.assetKind
      && routineGroupLocalID == other.routineGroupLocalID
      && routineLocalID == other.routineLocalID
  }

  static func fingerprint(title: String, type: RoutineStepType) -> String {
    let normalized = title
      .precomposedStringWithCanonicalMapping
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let input = Data("\(type)|\(normalized)".utf8)
    return SHA256.hash(data: input)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

nonisolated protocol RoutineTTSPrefetchJobStoring: Sendable {
  func allJobs() async throws -> [RoutineTTSPrefetchJob]
  @discardableResult
  func upsert(_ job: RoutineTTSPrefetchJob) async throws -> RoutineTTSPrefetchJob
  func replace(_ job: RoutineTTSPrefetchJob) async throws
  func remove(jobID: UUID) async throws
  func removeAllJobs() async throws
  @discardableResult
  func removeStaleJobs(
    keepingMemberID memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) async throws -> Int
}

actor FileRoutineTTSPrefetchJobStore: RoutineTTSPrefetchJobStoring {
  private static let formatVersion = 1

  private struct Envelope: Codable {
    let formatVersion: Int
    let jobs: [RoutineTTSPrefetchJob]
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private var jobs: [RoutineTTSPrefetchJob]
  private var isLoaded: Bool

  init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default
  ) throws {
    self.fileManager = fileManager
    self.fileURL = try fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    let parent = self.fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parent,
      withIntermediateDirectories: true
    )
    try Self.excludeFromBackup(parent)

    guard fileManager.fileExists(atPath: self.fileURL.path) else {
      jobs = []
      isLoaded = true
      return
    }
    let data: Data
    do {
      data = try Data(contentsOf: self.fileURL)
    } catch {
      jobs = []
      isLoaded = false
      // A protected volume can be temporarily unreadable during a system
      // background launch. Never erase the durable queue on a read failure.
      return
    }
    do {
      let envelope = try Self.decoder.decode(Envelope.self, from: data)
      guard envelope.formatVersion == Self.formatVersion else {
        jobs = []
        isLoaded = true
        try? fileManager.removeItem(at: self.fileURL)
        return
      }
      jobs = envelope.jobs
      isLoaded = true
    } catch {
      jobs = []
      isLoaded = true
      // Atomic writes make malformed content an actual corruption signal,
      // unlike a protected-file read failure handled above.
      try? fileManager.removeItem(at: self.fileURL)
    }
  }

  func allJobs() throws -> [RoutineTTSPrefetchJob] {
    try ensureLoaded()
    return jobs
  }

  @discardableResult
  func upsert(_ job: RoutineTTSPrefetchJob) throws -> RoutineTTSPrefetchJob {
    try ensureLoaded()
    var replacement = job
    if let index = jobs.firstIndex(where: { $0.hasSameDurableKey(as: job) }) {
      replacement = RoutineTTSPrefetchJob(
        id: jobs[index].id,
        memberID: job.memberID,
        selectionVersion: job.selectionVersion,
        selectedTTSID: job.selectedTTSID,
        assetKind: job.assetKind,
        routineGroupLocalID: job.routineGroupLocalID,
        routineLocalID: job.routineLocalID,
        routineFingerprint: job.routineFingerprint,
        routineGroupRemoteID: job.routineGroupRemoteID,
        routineRemoteID: job.routineRemoteID,
        state: job.state,
        assets: job.assets,
        remoteAttemptCount: job.remoteAttemptCount,
        nextRemoteAttemptAt: job.nextRemoteAttemptAt,
        updatedAt: job.updatedAt
      )
      jobs[index] = replacement
    } else {
      jobs.append(replacement)
    }
    try persist()
    return replacement
  }

  func replace(_ job: RoutineTTSPrefetchJob) throws {
    try ensureLoaded()
    guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
      throw RoutineTTSAudioCacheError.storageFailure
    }
    jobs[index] = job
    try persist()
  }

  func remove(jobID: UUID) throws {
    try ensureLoaded()
    let originalCount = jobs.count
    jobs.removeAll { $0.id == jobID }
    guard jobs.count != originalCount else { return }
    try persist()
  }

  func removeAllJobs() throws {
    try ensureLoaded()
    guard !jobs.isEmpty else { return }
    jobs.removeAll()
    try persist()
  }

  @discardableResult
  func removeStaleJobs(
    keepingMemberID memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64?
  ) throws -> Int {
    try ensureLoaded()
    let originalCount = jobs.count
    jobs.removeAll {
      $0.memberID != memberID
        || $0.selectionVersion != selectionVersion
        || $0.selectedTTSID != selectedTTSID
    }
    let removedCount = originalCount - jobs.count
    if removedCount > 0 {
      try persist()
    }
    return removedCount
  }

  private func persist() throws {
    let envelope = Envelope(
      formatVersion: Self.formatVersion,
      jobs: jobs
    )
    let data = try Self.encoder.encode(envelope)
    try data.write(
      to: fileURL,
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    )
    try Self.excludeFromBackup(fileURL)
  }

  private func ensureLoaded() throws {
    guard !isLoaded else { return }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      // Do not overwrite an existing queue until it becomes readable again.
      throw RoutineTTSAudioCacheError.storageFailure
    }
    do {
      let envelope = try Self.decoder.decode(Envelope.self, from: data)
      guard envelope.formatVersion == Self.formatVersion else {
        jobs = []
        isLoaded = true
        try? fileManager.removeItem(at: fileURL)
        return
      }
      jobs = envelope.jobs
      isLoaded = true
    } catch {
      jobs = []
      isLoaded = true
      try? fileManager.removeItem(at: fileURL)
    }
  }

  private static func defaultFileURL(
    fileManager: FileManager
  ) throws -> URL {
    guard let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw RoutineTTSAudioCacheError.storageFailure
    }
    return applicationSupport
      .appendingPathComponent("MoruRoutineTTSPrefetch", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
      .appendingPathComponent("jobs.json", isDirectory: false)
  }

  private static func excludeFromBackup(_ url: URL) throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableURL = url
    try mutableURL.setResourceValues(values)
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }
}

@MainActor
enum RoutineTTSPreparationDisplayState: Equatable {
  case idle
  case preparing
  case ready
  case retryScheduled
}

@MainActor
enum RoutineTTSPreparationComponent: Hashable {
  case routineIntro
  case commonCues
}

/// Shared observable state for Profile. Logs contain state names only; member,
/// routine, voice, URL, and spoken text are never emitted.
@MainActor
@Observable
final class RoutineTTSPreparationStatusCenter {
  private enum ComponentState {
    case preparing
    case ready
    case retryScheduled
  }

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.teammoru.Moru",
    category: "RoutineTTSPrefetch"
  )
  private var memberID: Int64?
  private var selectionVersion: Int64?
  private var selectedTTSID: Int64?
  private var componentStates: [RoutineTTSPreparationComponent: ComponentState] = [:]

  private(set) var state: RoutineTTSPreparationDisplayState = .idle

  func begin(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64? = nil
  ) {
    self.memberID = memberID
    self.selectionVersion = selectionVersion
    self.selectedTTSID = selectedTTSID
    componentStates = [
      .routineIntro: .preparing,
      .commonCues: .preparing,
    ]
    publish(.preparing)
  }

  func beginIfNeeded(
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64? = nil
  ) {
    guard self.memberID != memberID
            || self.selectionVersion != selectionVersion
            || self.selectedTTSID != selectedTTSID
            || componentStates.isEmpty else {
      return
    }
    begin(
      memberID: memberID,
      selectionVersion: selectionVersion,
      selectedTTSID: selectedTTSID
    )
  }

  func report(
    _ state: RoutineTTSPreparationDisplayState,
    component: RoutineTTSPreparationComponent,
    memberID: Int64,
    selectionVersion: Int64?,
    selectedTTSID: Int64? = nil
  ) {
    if self.memberID == nil {
      self.memberID = memberID
      self.selectionVersion = selectionVersion
      self.selectedTTSID = selectedTTSID
    }
    guard self.memberID == memberID,
          self.selectionVersion == selectionVersion,
          self.selectedTTSID == selectedTTSID else {
      return
    }
    switch state {
    case .preparing:
      componentStates[component] = .preparing
    case .ready:
      componentStates[component] = .ready
    case .retryScheduled:
      componentStates[component] = .retryScheduled
    case .idle:
      componentStates[component] = nil
    }
    refreshAggregate()
  }

  func reset() {
    memberID = nil
    selectionVersion = nil
    selectedTTSID = nil
    componentStates.removeAll()
    publish(.idle)
  }

  private func refreshAggregate() {
    let next: RoutineTTSPreparationDisplayState
    if componentStates.values.contains(where: { $0 == .preparing }) {
      next = .preparing
    } else if componentStates.values.contains(where: { $0 == .retryScheduled }) {
      next = .retryScheduled
    } else if !componentStates.isEmpty
                && componentStates.values.allSatisfy({ $0 == .ready }) {
      next = .ready
    } else {
      next = .idle
    }
    publish(next)
  }

  private func publish(_ next: RoutineTTSPreparationDisplayState) {
    guard state != next else { return }
    state = next
    logger.notice("TTS prefetch state: \(String(describing: next), privacy: .public)")
  }
}
