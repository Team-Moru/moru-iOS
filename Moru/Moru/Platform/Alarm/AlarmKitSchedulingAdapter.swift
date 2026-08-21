//
//  AlarmKitSchedulingAdapter.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import AlarmKit
import Foundation
import OSLog
import SwiftUI

@MainActor
enum AlarmKitStopController {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Moru",
    category: "AlarmRuntime"
  )

  static func stopIfNeeded(id: UUID) throws {
    try stopIfNeeded(
      currentState: {
        try AlarmManager.shared.alarms
          .first(where: { $0.id == id })?
          .state
      },
      stop: {
        try AlarmManager.shared.stop(id: id)
      }
    )
  }

  static func stopIfNeeded(
    currentState: () throws -> Alarm.State?,
    stop: () throws -> Void
  ) throws {
    do {
      guard requiresStop(try currentState()) else {
        logger.info("alarm_stop_already_inactive")
        return
      }
    } catch {
      logger.info("alarm_stop_state_unavailable")
    }

    do {
      try stop()
      logger.info("alarm_stop_succeeded")
    } catch {
      do {
        if !requiresStop(try currentState()) {
          logger.info("alarm_stop_became_inactive")
          return
        }
      } catch {
        logger.info("alarm_stop_recheck_unavailable")
      }

      let nsError = error as NSError
      logger.error(
        "alarm_stop_failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
      )
      throw error
    }
  }

  private static func requiresStop(_ state: Alarm.State?) -> Bool {
    guard let state else {
      return false
    }

    switch state {
    case .alerting, .countdown, .paused:
      return true
    case .scheduled:
      return false
    @unknown default:
      return true
    }
  }
}

@MainActor
final class AlarmKitSchedulingAdapter: AlarmScheduling {
  let backend = AlarmDeliveryBackend.alarmKit

  func authorizationState() async -> AlarmAuthorizationState {
    Self.makeAuthorizationState(from: AlarmManager.shared.authorizationState)
  }

  func requestAuthorization() async throws -> AlarmAuthorizationState {
    let state = try await AlarmManager.shared.requestAuthorization()
    return Self.makeAuthorizationState(from: state)
  }

  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String] {
    let ingress = AlarmIngressEnvelope(
      alarmID: request.scheduleID,
      routineID: request.routineID,
      scheduleID: request.scheduleID,
      kind: .recurring,
      fireDate: Date(),
      nonce: UUID()
    )
    try await schedule(
      id: request.scheduleID,
      routineName: request.routineName,
      schedule: Self.makeSchedule(from: request),
      ingress: ingress
    )
    return [request.scheduleID.uuidString.lowercased()]
  }

  func scheduleSnooze(_ request: AlarmSnoozeRequest) async throws -> [String] {
    try await schedule(
      id: request.alarmID,
      routineName: request.routineName,
      schedule: .fixed(request.fireDate),
      ingress: request.ingressEnvelope
    )
    return [request.alarmID.uuidString.lowercased()]
  }

  func stop(id: UUID) async throws {
    try AlarmKitStopController.stopIfNeeded(id: id)
  }

  func cancel(identifiers: [String]) async throws {
    for identifier in identifiers {
      guard let id = UUID(uuidString: identifier) else {
        continue
      }
      try AlarmManager.shared.cancel(id: id)
    }
  }

  func snapshot() async throws -> AlarmPlatformSnapshot {
    AlarmPlatformSnapshot(
      backend: backend,
      identifiers: Set(
        try AlarmManager.shared.alarms.map { $0.id.uuidString.lowercased() }
      )
    )
  }

  static func makeSchedule(from request: AlarmScheduleRequest) -> Alarm.Schedule {
    let time = Alarm.Schedule.Relative.Time(
      hour: request.hour,
      minute: request.minute
    )
    let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(
      request.weekdays.map(makeLocaleWeekday)
    )
    return .relative(
      Alarm.Schedule.Relative(time: time, repeats: recurrence)
    )
  }

  private func schedule(
    id: UUID,
    routineName: String,
    schedule: Alarm.Schedule,
    ingress: AlarmIngressEnvelope
  ) async throws {
    let openRoutineButton = AlarmButton(
      text: "루틴 시작",
      textColor: .white,
      systemImageName: "arrow.right.circle.fill"
    )
    let presentation: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      presentation = AlarmPresentation.Alert(
        title: "\(routineName) 시작할 시간이에요",
        secondaryButton: openRoutineButton,
        secondaryButtonBehavior: .custom
      )
    } else {
      let stopButton = AlarmButton(
        text: "알람 끄기",
        textColor: .white,
        systemImageName: "stop.circle.fill"
      )
      presentation = AlarmPresentation.Alert(
        title: "\(routineName) 시작할 시간이에요",
        stopButton: stopButton,
        secondaryButton: openRoutineButton,
        secondaryButtonBehavior: .custom
      )
    }
    let metadata = MoruAlarmMetadata(
      ingress: ingress,
      routineName: routineName
    )
    let attributes = AlarmAttributes<MoruAlarmMetadata>(
      presentation: AlarmPresentation(alert: presentation),
      metadata: metadata,
      tintColor: AppColor.babyBlue350
    )
    let intent = OpenMoruRoutineIntent(ingress: ingress)
    let configuration = AlarmManager.AlarmConfiguration<MoruAlarmMetadata>.alarm(
      schedule: schedule,
      attributes: attributes,
      secondaryIntent: intent
    )

    _ = try await AlarmManager.shared.schedule(
      id: id,
      configuration: configuration
    )
  }

  private static func makeLocaleWeekday(_ weekday: Weekday) -> Locale.Weekday {
    switch weekday {
    case .sunday:
      .sunday
    case .monday:
      .monday
    case .tuesday:
      .tuesday
    case .wednesday:
      .wednesday
    case .thursday:
      .thursday
    case .friday:
      .friday
    case .saturday:
      .saturday
    }
  }

  private static func makeAuthorizationState(
    from state: AlarmManager.AuthorizationState
  ) -> AlarmAuthorizationState {
    switch state {
    case .notDetermined:
      .notDetermined
    case .authorized:
      .authorized
    case .denied:
      .denied
    @unknown default:
      .unavailable
    }
  }
}
