//
//  AlarmNotificationContracts.swift
//  Moru
//

import CryptoKit
import Foundation

enum AlarmNotificationPermissionState: Sendable, Equatable {
  case notDetermined
  case denied
  case authorized
}

struct AlarmNotificationScheduleRequest: Hashable {
  let routineID: UUID
  let scheduleID: UUID
  let routineName: String
  let hour: Int
  let minute: Int
  let weekdays: [Weekday]
  let resetGeneration: UInt64
  let desiredScheduleFingerprint: String

  init(
    routineID: UUID,
    scheduleID: UUID,
    routineName: String,
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    resetGeneration: UInt64,
    desiredScheduleFingerprint: String
  ) {
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.routineName = routineName
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays
    self.resetGeneration = resetGeneration
    self.desiredScheduleFingerprint = desiredScheduleFingerprint
  }

  var normalizedWeekdays: [Weekday] {
    Array(Set(weekdays)).sorted { $0.rawValue < $1.rawValue }
  }

  static func validationError(
    hour: Int,
    minute: Int,
    weekdays: [Weekday]
  ) -> AlarmScheduleValidationError? {
    guard (0...23).contains(hour) else {
      return .invalidHour(hour)
    }
    guard (0...59).contains(minute) else {
      return .invalidMinute(minute)
    }
    guard !weekdays.isEmpty else {
      return .emptyWeekdays
    }
    guard Set(weekdays).count == weekdays.count else {
      return .duplicateWeekdays
    }
    return nil
  }

  static func desiredScheduleFingerprint(
    routineID: UUID,
    scheduleID: UUID,
    routineName: String,
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    resetGeneration: UInt64
  ) -> String {
    let normalizedWeekdays = Array(Set(weekdays))
      .sorted { $0.rawValue < $1.rawValue }
      .map(\.rawValue)
      .map(String.init)
      .joined(separator: ",")
    let encodedRoutineName = Data(routineName.utf8).base64EncodedString()
    let canonicalValue = [
      "schemaVersion=1",
      "routineID=\(routineID.uuidString.lowercased())",
      "scheduleID=\(scheduleID.uuidString.lowercased())",
      "routineNameBase64=\(encodedRoutineName)",
      "hour=\(hour)",
      "minute=\(minute)",
      "weekdays=\(normalizedWeekdays)",
      "resetGeneration=\(resetGeneration)"
    ].joined(separator: "\n")
    return sha256(canonicalValue)
  }

  static func cancellationFingerprint(
    routineID: UUID,
    scheduleID: UUID,
    resetGeneration: UInt64
  ) -> String {
    sha256([
      "schemaVersion=1",
      "kind=cancellation",
      "routineID=\(routineID.uuidString.lowercased())",
      "scheduleID=\(scheduleID.uuidString.lowercased())",
      "resetGeneration=\(resetGeneration)"
    ].joined(separator: "\n"))
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

enum AlarmScheduleValidationError: Error, Equatable {
  case invalidHour(Int)
  case invalidMinute(Int)
  case emptyWeekdays
  case duplicateWeekdays
}

@MainActor
protocol AlarmNotificationScheduling: AnyObject {
  func authorizationState() async -> AlarmNotificationPermissionState
  func requestAuthorization() async throws -> AlarmNotificationPermissionState
  func replace(_ request: AlarmNotificationScheduleRequest) async throws
  func cancel(scheduleID: UUID) async throws
}

@MainActor
protocol AlarmPlatformStateRepository: AnyObject {
  func fetchAll() throws -> [AlarmPlatformSnapshot]
  func fetch(scheduleID: UUID) throws -> AlarmPlatformSnapshot?
  func save(_ snapshot: AlarmPlatformSnapshot) throws
}

struct AlarmMutationFreezeToken: Hashable, Sendable {
  let id: UUID

  init(id: UUID = UUID()) {
    self.id = id
  }
}

@MainActor
protocol AlarmScheduleMutating: AnyObject {
  func freezeAndDrain() async throws -> AlarmMutationFreezeToken
  func commit(
    routines: [Routine],
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws
  func delete(
    routineID: UUID,
    scheduleID: UUID?,
    localCommit: @escaping @MainActor () throws -> Void
  ) async throws
  func reconcile(routines: [Routine]) async throws
  func cancelAll(
    scheduleIDs: [UUID],
    using token: AlarmMutationFreezeToken
  ) async throws
  func thaw(_ token: AlarmMutationFreezeToken)
  func permissionState() async -> AlarmNotificationPermissionState
}

enum NotificationAlarmMutationError: Error, Equatable, LocalizedError {
  case invalidSchedule
  case permissionDenied
  case platformFailure
  case localCommitFailure
  case storageFailure
  case mutationFrozen
  case generationUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidSchedule:
      return "The alarm schedule is invalid."
    case .permissionDenied:
      return "Notification permission is denied."
    case .platformFailure:
      return "The notification platform operation failed."
    case .localCommitFailure:
      return "The local alarm change could not be saved."
    case .storageFailure:
      return "The alarm platform state could not be saved."
    case .mutationFrozen:
      return "Alarm mutations are temporarily frozen."
    case .generationUnavailable:
      return "The current reset generation is unavailable."
    }
  }
}

enum AlarmPlatformStateRepositoryError: Error, Equatable {
  case duplicateSchedule(UUID)
}
