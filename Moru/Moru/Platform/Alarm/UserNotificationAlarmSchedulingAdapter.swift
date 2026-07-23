//
//  UserNotificationAlarmSchedulingAdapter.swift
//  Moru
//
//  Created by Codex on 7/23/26.
//

import Foundation
import UserNotifications

@MainActor
final class UserNotificationAlarmSchedulingAdapter: AlarmScheduling {
  static let identifierPrefix = "moru.alarm."

  let backend = AlarmDeliveryBackend.localNotification
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func authorizationState() async -> AlarmAuthorizationState {
    let settings = await center.notificationSettings()
    return Self.makeAuthorizationState(from: settings.authorizationStatus)
  }

  func requestAuthorization() async throws -> AlarmAuthorizationState {
    _ = try await center.requestAuthorization(options: [.alert, .sound])
    return await authorizationState()
  }

  func scheduleRecurring(_ request: AlarmScheduleRequest) async throws -> [String] {
    var scheduledIdentifiers: [String] = []

    do {
      for weekday in request.weekdays {
        let identifier = Self.requestIdentifier(
          scheduleID: request.scheduleID,
          weekday: weekday
        )
        let notificationRequest = UNNotificationRequest(
          identifier: identifier,
          content: makeContent(request),
          trigger: UNCalendarNotificationTrigger(
            dateMatching: DateComponents(
              hour: request.hour,
              minute: request.minute,
              weekday: weekday.rawValue
            ),
            repeats: true
          )
        )
        try await center.add(notificationRequest)
        scheduledIdentifiers.append(identifier)
      }
      return scheduledIdentifiers
    } catch {
      center.removePendingNotificationRequests(
        withIdentifiers: scheduledIdentifiers
      )
      throw error
    }
  }

  func cancel(identifiers: [String]) async throws {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func snapshot() async throws -> AlarmPlatformSnapshot {
    let identifiers = await center.pendingNotificationRequests()
      .map(\.identifier)
      .filter { $0.hasPrefix(Self.identifierPrefix) }
    return AlarmPlatformSnapshot(
      backend: backend,
      identifiers: Set(identifiers)
    )
  }

  static func requestIdentifier(
    scheduleID: UUID,
    weekday: Weekday
  ) -> String {
    "\(identifierPrefix)\(scheduleID.uuidString.lowercased()).weekday.\(weekday.rawValue)"
  }

  private func makeContent(_ request: AlarmScheduleRequest) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "\(request.routineName) 시작할 시간이에요"
    content.body = "MORU를 열어 루틴을 시작해 주세요."
    content.sound = .default
    content.userInfo = [
      "alarmID": request.scheduleID.uuidString,
      "routineID": request.routineID.uuidString,
      "scheduleID": request.scheduleID.uuidString,
      "kind": "recurring",
    ]
    return content
  }

  private static func makeAuthorizationState(
    from status: UNAuthorizationStatus
  ) -> AlarmAuthorizationState {
    switch status {
    case .notDetermined:
      .notDetermined
    case .denied:
      .denied
    case .authorized, .provisional, .ephemeral:
      .authorized
    @unknown default:
      .unavailable
    }
  }
}
