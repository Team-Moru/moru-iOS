//
//  AlarmSchedulingModels.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation

enum AlarmDeliveryBackend: String, Codable, Hashable {
  case alarmKit
  case localNotification
}

enum AlarmAuthorizationState: String, Codable, Hashable {
  case notDetermined
  case authorized
  case denied
  case unavailable
}

enum AlarmDeliveryState: String, Codable, Hashable {
  case scheduled
  case authorizationRequired
  case repairRequired
}

enum AlarmIngressKind: String, Codable, Hashable, Sendable {
  case recurring
  case snooze
}

enum AlarmIngressLaunchTarget: String, Codable, Hashable, Sendable {
  case alarmRing
  case scheduledRoutine
}

nonisolated struct AlarmIngressEnvelope: Codable, Hashable, Sendable {
  static let notificationUserInfoKey = "moru.alarm.ingress"

  let alarmID: UUID
  let routineID: UUID
  let scheduleID: UUID
  let kind: AlarmIngressKind
  let fireDate: Date
  let nonce: UUID
  let launchTarget: AlarmIngressLaunchTarget

  nonisolated init(
    alarmID: UUID,
    routineID: UUID,
    scheduleID: UUID,
    kind: AlarmIngressKind,
    fireDate: Date,
    nonce: UUID,
    launchTarget: AlarmIngressLaunchTarget = .alarmRing
  ) {
    self.alarmID = alarmID
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.kind = kind
    self.fireDate = fireDate
    self.nonce = nonce
    self.launchTarget = launchTarget
  }

  nonisolated func refreshingOccurrence(
    fireDate: Date,
    nonce: UUID = UUID()
  ) -> AlarmIngressEnvelope {
    AlarmIngressEnvelope(
      alarmID: alarmID,
      routineID: routineID,
      scheduleID: scheduleID,
      kind: kind,
      fireDate: fireDate,
      nonce: nonce,
      launchTarget: launchTarget
    )
  }

  nonisolated func routing(
    to launchTarget: AlarmIngressLaunchTarget
  ) -> AlarmIngressEnvelope {
    AlarmIngressEnvelope(
      alarmID: alarmID,
      routineID: routineID,
      scheduleID: scheduleID,
      kind: kind,
      fireDate: fireDate,
      nonce: nonce,
      launchTarget: launchTarget
    )
  }

  nonisolated func encodedString() throws -> String {
    let data = try JSONEncoder().encode(self)
    guard let value = String(data: data, encoding: .utf8) else {
      throw AlarmIngressEnvelopeCodingError.invalidUTF8
    }
    return value
  }

  nonisolated static func decode(_ value: String) throws -> AlarmIngressEnvelope {
    guard let data = value.data(using: .utf8) else {
      throw AlarmIngressEnvelopeCodingError.invalidUTF8
    }
    return try JSONDecoder().decode(AlarmIngressEnvelope.self, from: data)
  }

  private enum CodingKeys: String, CodingKey {
    case alarmID
    case routineID
    case scheduleID
    case kind
    case fireDate
    case nonce
    case launchTarget
  }

  nonisolated init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    alarmID = try container.decode(UUID.self, forKey: .alarmID)
    routineID = try container.decode(UUID.self, forKey: .routineID)
    scheduleID = try container.decode(UUID.self, forKey: .scheduleID)
    kind = try container.decode(AlarmIngressKind.self, forKey: .kind)
    fireDate = try container.decode(Date.self, forKey: .fireDate)
    nonce = try container.decode(UUID.self, forKey: .nonce)
    launchTarget = try container.decodeIfPresent(
      AlarmIngressLaunchTarget.self,
      forKey: .launchTarget
    ) ?? .alarmRing
  }
}

enum AlarmIngressEnvelopeCodingError: Error {
  case invalidUTF8
}

struct AlarmScheduleRequest: Codable, Hashable {
  let routineID: UUID
  let scheduleID: UUID
  let routineName: String
  let hour: Int
  let minute: Int
  let weekdays: [Weekday]
  let soundName: String
  let fingerprint: String

  init(
    routineID: UUID,
    scheduleID: UUID,
    routineName: String,
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    soundName: String,
    fingerprint: String? = nil
  ) {
    let sortedWeekdays = weekdays.sortedByDisplayOrder()
    self.routineID = routineID
    self.scheduleID = scheduleID
    self.routineName = routineName
    self.hour = hour
    self.minute = minute
    self.weekdays = sortedWeekdays
    self.soundName = soundName
    self.fingerprint = fingerprint ?? Self.makeFingerprint(
      routineID: routineID,
      scheduleID: scheduleID,
      routineName: routineName,
      hour: hour,
      minute: minute,
      weekdays: sortedWeekdays,
      soundName: soundName
    )
  }

  init?(routine: Routine) {
    guard routine.isActive,
          let schedule = routine.alarmSchedule,
          schedule.isEnabled,
          !schedule.weekdays.isEmpty else {
      return nil
    }

    self.init(
      routineID: routine.id,
      scheduleID: schedule.id,
      routineName: routine.name,
      hour: schedule.hour,
      minute: schedule.minute,
      weekdays: schedule.weekdays,
      soundName: schedule.soundName
    )
  }

  private static func makeFingerprint(
    routineID: UUID,
    scheduleID: UUID,
    routineName: String,
    hour: Int,
    minute: Int,
    weekdays: [Weekday],
    soundName: String
  ) -> String {
    let weekdayValue = weekdays.map { String($0.rawValue) }.joined(separator: ",")
    return [
      routineID.uuidString.lowercased(),
      scheduleID.uuidString.lowercased(),
      routineName,
      String(hour),
      String(minute),
      weekdayValue,
      soundName,
    ].joined(separator: "|")
  }
}

struct AlarmSnoozeRequest: Codable, Hashable {
  let alarmID: UUID
  let scheduleID: UUID
  let routineID: UUID
  let routineName: String
  let fireDate: Date

  var ingressEnvelope: AlarmIngressEnvelope {
    AlarmIngressEnvelope(
      alarmID: alarmID,
      routineID: routineID,
      scheduleID: scheduleID,
      kind: .snooze,
      fireDate: fireDate,
      nonce: UUID()
    )
  }
}

struct AlarmDeliveryRecord: Codable, Hashable {
  let request: AlarmScheduleRequest
  var backend: AlarmDeliveryBackend?
  var state: AlarmDeliveryState
  var platformIdentifiers: [String]
  var lastErrorMessage: String?
  var updatedAt: Date

  var scheduleID: UUID {
    request.scheduleID
  }

  var routineID: UUID {
    request.routineID
  }
}

struct SnoozedAlarmRecord: Codable, Hashable, Identifiable {
  let id: UUID
  let scheduleID: UUID
  let routineID: UUID
  let fireDate: Date
  let backend: AlarmDeliveryBackend
  let platformIdentifiers: [String]
  let createdAt: Date
}

struct AlarmPlatformSnapshot: Equatable {
  let backend: AlarmDeliveryBackend
  let identifiers: Set<String>
}

struct AlarmRingContext: Equatable, Hashable {
  let ingress: AlarmIngressEnvelope
  let routineName: String
  let routineMinutes: Int

  func routing(to launchTarget: AlarmIngressLaunchTarget) -> AlarmRingContext {
    AlarmRingContext(
      ingress: ingress.routing(to: launchTarget),
      routineName: routineName,
      routineMinutes: routineMinutes
    )
  }
}

enum AlarmIngressIgnoredReason: Equatable {
  case stale
  case routineUnavailable
  case routineInactive
  case alarmDisabled
  case scheduleMismatch
  case deliveryUnavailable
  case snoozeUnavailable
}

enum AlarmIngressResolution: Equatable {
  case route(AlarmRingContext)
  case ignored(AlarmIngressIgnoredReason)
  case temporarilyUnavailable
}

enum AlarmRuntimeError: Error, Equatable {
  case invalidSnoozeMinutes
  case routeNoLongerAvailable
  case authorizationRequired
  case schedulingFailed
  case persistenceFailed
  case stopFailed
  case cancellationFailed
}

enum AlarmScheduleMutation {
  case synchronize(routines: [Routine])
  case delete(scheduleID: UUID)
}

struct AlarmMutationResult: Equatable {
  var records: [AlarmDeliveryRecord]

  var requiresRepair: Bool {
    records.contains { $0.state != .scheduled }
  }

  static let empty = AlarmMutationResult(records: [])
}
